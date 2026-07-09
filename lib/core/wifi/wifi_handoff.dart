import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../models/device.dart';
import '../state/camera_selection.dart' show activeCameraIdProvider;
import '../ble/ble_providers.dart';
import '../services/log_service.dart';
import '../state/reconnect_controller.dart';
import 'wifi_providers.dart';
import 'wifi_service.dart' show WifiService;

final _log = Logger('WifiHandoff');

/// Bounded retry policy for the BLE-driven WiFi bring-up. Overridable in
/// tests (compressed timescale) via [wifiBringUpRetryProvider].
class WifiBringUpRetry {
  const WifiBringUpRetry({
    this.maxAttempts = 2,
    this.delay = const Duration(seconds: 3),
  });

  /// Total bring-up attempts per BLE `connected` edge (first try included).
  final int maxAttempts;

  /// Gap between a failed attempt and the retry.
  final Duration delay;
}

final wifiBringUpRetryProvider = Provider<WifiBringUpRetry>(
  (_) => const WifiBringUpRetry(),
);

/// Single owner of the WiFi Direct group lifecycle. Watches the active BLE
/// camera and its connection state; brings the WiFi group up automatically
/// when BLE connects, tears it down on manual disconnect, camera change, or
/// auto-reconnect give-up. An UNEXPECTED BLE drop does NOT tear the group
/// down while the U6 reconnect loop is still eligible — the firmware keeps
/// its side up and the app must rejoin, not cycle (group re-formation kills
/// Argus capture mid-session).
///
/// The handoff is intentionally one-way (BLE first, then WiFi) and uses the
/// credentials returned by the firmware over BLE — see
/// `WifiDirectGroupResponse` in proto/wifi.proto. There is no hardcoded
/// fallback.
///
/// **Lean recovery model.** The app does NOT drive WiFi reconnection. The
/// firmware's group has a stable, persistent SSID/PSK, so once the phone has
/// joined it the OS owns rejoining the saved network across re-forms (a new
/// match, a firmware restart, a transient drop). This controller therefore runs
/// no reconnect timers and does not re-form the group in response to wifi-state
/// transitions — that reactive loop was the source of the SSID-flap storm.
/// Reachability is verified lazily, right before a WiFi action (download / live
/// preview), by the consumer via [WifiService.isCameraReachable].
///
/// The one exception is the BRING-UP itself: a connectGroup that fails after
/// its internal join retries has already released the firmware group, so the
/// lean model has nothing left to rejoin. That single case gets a bounded
/// retry keyed to the BLE `connected` edge (see [_bringUp]) — a fresh
/// StartWifiDirect re-forms the group and the join runs like a first connect.
///
/// This Notifier exposes no state to the UI; it only runs side effects.
/// Mount it once at the root of the widget tree (see lib/app.dart) so it
/// stays alive for the app's lifetime — Notifiers are lazy and won't run
/// without a reader.
class WifiHandoffController extends Notifier<void> {
  String? _activeId;
  CameraConnectionState? _lastBleState;
  ReconnectPhase? _lastReconnectPhase;
  Timer? _debounce;
  Timer? _retry;

  /// How long a connection state must hold before we act on it. Rapid
  /// connect/disconnect flaps would otherwise churn the WiFi group
  /// (connect→disconnect→connect), widening the firmware P2P join race and
  /// surfacing as intermittent "wifi failed". Collapsing flaps to the final
  /// stable state removes that churn.
  static const _debounceDelay = Duration(milliseconds: 400);

  @override
  void build() {
    ref.onDispose(() {
      _debounce?.cancel();
      _retry?.cancel();
    });

    final id = ref.watch(activeCameraIdProvider);
    // U6 auto-reconnect coupling: while the loop still claims the device the
    // group must stay up (the firmware keeps its side alive; the app rejoins,
    // never cycles — re-forming the group kills Argus capture mid-session).
    final reconnectPhase = ref.watch(
      reconnectControllerProvider.select((s) => s.phase),
    );

    if (id != _activeId) {
      final prev = _activeId;
      _activeId = id;
      _lastBleState = null;
      // A camera change (or the manual-disconnect clear) is never a loop
      // give-up signal for the NEW id — resync the phase tracker silently.
      _lastReconnectPhase = reconnectPhase;
      _debounce?.cancel();
      _retry?.cancel();
      if (prev != null) {
        unawaited(
          ref
              .read(wifiServiceProvider)
              .disconnectGroup(prev)
              .catchError(
                (Object e) => _log.warn('disconnectGroup(prev) failed: $e'),
              ),
        );
      }
    }
    if (id == null) return;

    final wifi = ref.read(wifiServiceProvider);
    final bleState = ref.watch(connectionStateProvider(id)).valueOrNull;

    // Reconnect-loop give-up (bluetooth off / protocol mismatch): the group
    // was retained across the drop for a rejoin that will now never come —
    // this is the deferred teardown. `reconnecting → idle` is NOT a give-up
    // (success and manual stops land there with their own teardown paths).
    if (reconnectPhase != _lastReconnectPhase) {
      final wasEligible = _lastReconnectPhase == ReconnectPhase.reconnecting;
      _lastReconnectPhase = reconnectPhase;
      if (wasEligible && reconnectPhase == ReconnectPhase.gaveUp) {
        _debounce?.cancel();
        _retry?.cancel();
        unawaited(
          wifi
              .disconnectGroup(id)
              .catchError(
                (Object e) => _log.warn('disconnectGroup(give-up) failed: $e'),
              ),
        );
      }
    }

    // BLE-driven group lifecycle: bring WiFi up when BLE connects, tear it down
    // when BLE disconnects. That is the controller's whole job — rejoining a
    // dropped-but-stable group is the OS's responsibility (lean model).
    if (bleState != _lastBleState) {
      _lastBleState = bleState;
      _debounce?.cancel();
      _retry?.cancel();
      switch (bleState) {
        case CameraConnectionState.connected:
          _debounce = Timer(_debounceDelay, () => _bringUp(id, wifi, 1));
        case CameraConnectionState.disconnected:
          _debounce = Timer(_debounceDelay, () {
            // Session-aware retention (U6): an UNEXPECTED drop arms the
            // auto-reconnect loop, and while it still claims this device the
            // app must rejoin the firmware's still-up group — suppress the
            // teardown. It runs later on loop give-up (branch above), or now
            // for a manual disconnect / non-eligible drop (loop idle).
            if (ref.read(reconnectControllerProvider).isReconnecting(id)) {
              return;
            }
            unawaited(
              wifi
                  .disconnectGroup(id)
                  .catchError(
                    (Object e) => _log.warn('disconnectGroup failed: $e'),
                  ),
            );
          });
        default:
          break;
      }
    }
  }

  /// One bring-up attempt, with a BOUNDED retry on failure.
  ///
  /// Swallow + log the failure. The Android P2P join can fail transiently
  /// (WifiP2p connect failed) and connectGroup THROWS on a failed join; an
  /// unawaited throw is an unhandled async error that crashes the app.
  ///
  /// The retry exists for the field bug (2026-07-07, real Jetson + phone):
  /// after a manual disconnect → reconnect the firmware returned the STALE
  /// still-up group's credentials, the phone's P2P join failed every attempt
  /// (assoc-reject, then BUSY), and the failure path had already told the
  /// firmware to release the group (StopWifiDirect) — so nothing ever
  /// re-formed it and the preview sat on "RECONNECTING…" forever. Because the
  /// failed attempt released the firmware group, re-running connectGroup
  /// re-creates it FRESH via StartWifiDirect, which is exactly the join that
  /// succeeds. This is NOT the banned reactive wifi-state loop (the SSID-flap
  /// storm): it is keyed to the BLE `connected` edge only, bounded by
  /// [WifiBringUpRetry.maxAttempts], and cancelled by any BLE state change,
  /// camera change, or give-up teardown.
  void _bringUp(String id, WifiService wifi, int attempt) {
    final policy = ref.read(wifiBringUpRetryProvider);
    _log.info(
      'WiFi-Direct bring-up for $id (attempt $attempt/${policy.maxAttempts})',
    );
    unawaited(
      wifi
          .connectGroup(id)
          .then<void>(
            (_) => _log.info('WiFi-Direct group up for $id'),
            onError: (Object e) {
              _log.warn(
                'connectGroup failed '
                '(attempt $attempt/${policy.maxAttempts}): $e',
              );
              if (attempt >= policy.maxAttempts) return;
              _retry?.cancel();
              _retry = Timer(policy.delay, () {
                // Re-check the world before retrying: the retry is only valid
                // while THIS camera is still the active, BLE-connected one.
                if (_activeId != id ||
                    _lastBleState != CameraConnectionState.connected) {
                  return;
                }
                _log.info('retrying WiFi bring-up (fresh group) for $id');
                _bringUp(id, wifi, attempt + 1);
              });
            },
          ),
    );
  }
}

final wifiHandoffProvider = NotifierProvider<WifiHandoffController, void>(
  WifiHandoffController.new,
);
