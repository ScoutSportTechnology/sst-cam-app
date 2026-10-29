import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
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

// ---------------------------------------------------------------------------
// Shared-WiFi (STA) migration — authenticated preview reachability probe (U6)
// ---------------------------------------------------------------------------

/// How long the app waits for the authenticated STA/LAN preview to answer
/// before declaring the network unreachable (isolation) and denying the
/// migration. This MUST be strictly shorter than [kFirmwareSelfRevertWindow]
/// so the app's confirm/deny always beats the firmware's backstop timer — the
/// app owns the verdict; the firmware timeout only covers a crashed app
/// (KTD5 / OQ1). Enforced by an assertion at construction and in tests.
///
/// U2 (R2): this is the retry BUDGET, and it is the load-bearing fix for
/// one-tap connect — NOT the firmware's best-effort gratuitous ARP (U1), which
/// a neighbour is free to ignore for a FAILED neigh entry. On the first tap the
/// phone may hold a stale/negative ARP entry for the camera's just-appeared STA
/// IP, so the first attempt fails fast (EHOSTUNREACH); the loop must fit several
/// retries so at least one lands after the kernel re-resolves. At [_kProbeRetryDelay]
/// (1.2s) spacing, a 12s budget affords ~9 fast-fail retries while still leaving
/// an 8s margin under the 20s self-revert for the BLE confirm round-trip.
const Duration kPreviewProbeTimeout = Duration(seconds: 12);

/// The firmware's self-revert backstop: if no confirm arrives within this
/// window after entering `Migrating`, the camera reverts to S1 on its own.
/// Mirrored here only to keep the app probe strictly shorter (documented, not
/// enforced on the wire).
const Duration kFirmwareSelfRevertWindow = Duration(seconds: 20);

/// Fixed RTSP port + path the firmware serves the migration preview on
/// (`rtsp://<previewEndpoint>:8554/preview`).
const int _kPreviewRtspPort = 8554;
const String _kPreviewRtspPath = '/preview';

/// Delay between probe attempts. The camera's STA IP only appeared moments ago,
/// so the first connect can hit a STALE NEGATIVE ARP entry on the phone
/// (EHOSTUNREACH / errno 113 returned instantly without re-resolving). That
/// failed connect kicks a fresh ARP resolution; this delay (> the ~1s ARP
/// retransmit) lets the retry resolve and succeed.
const Duration _kProbeRetryDelay = Duration(milliseconds: 1200);

/// Per-attempt connect/read ceiling so one stuck attempt can't eat the whole
/// probe budget (the outer [RtspDescribeProbe.timeout] bounds the retry loop).
const Duration _kProbeAttemptTimeout = Duration(seconds: 3);

/// Probes whether the camera's authenticated STA/LAN preview is reachable
/// (OQ2). Injected via [previewProbeProvider] so tests drive the reachable /
/// isolated branches without a real socket.
abstract class PreviewReachabilityProbe {
  /// Returns true when the preview at [endpoint] answers an AUTHENTICATED probe
  /// (so it exercises both routing AND auth), false on isolation / auth failure
  /// / timeout. [credential] is the "user:pass" Basic-auth pair. Never throws.
  Future<bool> probe(String endpoint, String credential);
}

/// Default probe: an authenticated RTSP `DESCRIBE` against
/// `rtsp://<endpoint>:8554/preview`. This is the cheapest check that also
/// exercises auth — a client-isolated AP fails the TCP connect (routing) while
/// a routable-but-unauthorized endpoint answers `401`; only a `2xx` counts as
/// reachable. Bounded by [kPreviewProbeTimeout].
class RtspDescribeProbe implements PreviewReachabilityProbe {
  // Not const: the invariant is a runtime assert (a Duration comparison is not
  // const-evaluable) — the app probe timeout MUST be strictly shorter than the
  // firmware self-revert window.
  RtspDescribeProbe({
    this.timeout = kPreviewProbeTimeout,
    this.port = _kPreviewRtspPort,
    Future<bool> Function(String host)? bindToWifi,
    Future<void> Function()? clearBinding,
  }) : _bindToWifi = bindToWifi,
       _clearBinding = clearBinding,
       assert(
         timeout < kFirmwareSelfRevertWindow,
         'app probe timeout must be strictly shorter than the firmware '
         'self-revert window',
       );

  final Duration timeout;

  /// The RTSP port to probe. Fixed at [_kPreviewRtspPort] in production;
  /// injectable so tests can point at a local server.
  final int port;

  /// Pins the process to the phone's Wi-Fi (STA) network before the connect and
  /// clears it after — without this, on Android a bare socket can egress the
  /// WiFi-Direct (P2P) interface and never reach a camera on the shared Wi-Fi,
  /// which reads as a false "isolation" (OQ2). Injected so tests assert the
  /// bind-before-connect / clear-in-finally order without a real socket.
  final Future<bool> Function(String host)? _bindToWifi;
  final Future<void> Function()? _clearBinding;

  @override
  Future<bool> probe(String endpoint, String credential) async {
    final host = endpoint.trim();
    if (host.isEmpty) return false;
    var bound = false;
    final deadline = DateTime.now().add(timeout);
    try {
      // Route the probe over the phone's Wi-Fi (STA), not the WiFi-Direct (P2P)
      // interface, before opening the socket (OQ2). Bind once — it holds for the
      // whole retry loop. Best-effort: on failure we fall back to unbound.
      bound = _bindToWifi != null && await _bindToWifi(host);

      // Retry until reachable or the deadline: the camera holds its STA IP for
      // the whole self-revert window, and the first attempt often fails on a
      // stale negative ARP entry (see [_kProbeRetryDelay]).
      while (true) {
        if (await _attemptOnce(host, credential, deadline)) return true;
        final remaining = deadline.difference(DateTime.now());
        if (remaining <= _kProbeRetryDelay) return false;
        await Future<void>.delayed(_kProbeRetryDelay);
      }
    } finally {
      if (bound) await _clearBinding?.call();
    }
  }

  /// One connect → authenticated RTSP DESCRIBE → status-line read. Returns true
  /// only on a 2xx; never throws (failures resolve to false so the caller can
  /// retry). Bounded by [deadline] and [_kProbeAttemptTimeout].
  Future<bool> _attemptOnce(
    String host,
    String credential,
    DateTime deadline,
  ) async {
    Socket? socket;
    try {
      var remaining = deadline.difference(DateTime.now());
      if (remaining.isNegative) return false;
      final connectTimeout = remaining < _kProbeAttemptTimeout
          ? remaining
          : _kProbeAttemptTimeout;
      socket = await Socket.connect(host, port, timeout: connectTimeout);
      final url = 'rtsp://$host:$port$_kPreviewRtspPath';
      final auth = base64.encode(utf8.encode(credential));
      socket.write(
        'DESCRIBE $url RTSP/1.0\r\n'
        'CSeq: 1\r\n'
        'Authorization: Basic $auth\r\n'
        'Accept: application/sdp\r\n'
        '\r\n',
      );
      await socket.flush();

      remaining = deadline.difference(DateTime.now());
      if (remaining.isNegative) return false;
      // Read ONLY until the RTSP status line arrives — RTSP is a persistent
      // connection (the server keeps the socket open after answering), so
      // reading to EOF would hang. A 2xx means routed AND authenticated.
      final buffer = StringBuffer();
      final readCap = remaining < _kProbeAttemptTimeout
          ? remaining
          : _kProbeAttemptTimeout;
      try {
        await for (final chunk
            in socket
                .cast<List<int>>()
                .transform(utf8.decoder)
                .timeout(readCap)) {
          buffer.write(chunk);
          if (buffer.toString().contains('\r\n')) break;
        }
      } on TimeoutException {
        // No response this attempt → parsed as unreachable below.
      }
      final statusLine = buffer.toString().split('\r\n').firstOrNull ?? '';
      final match = RegExp(r'RTSP/\d\.\d\s+(\d{3})').firstMatch(statusLine);
      final code = match == null ? 0 : int.tryParse(match.group(1)!) ?? 0;
      final reachable = code >= 200 && code < 300;
      if (!reachable) {
        debugPrint('[preview-probe] non-2xx status "$statusLine" → retrying');
      }
      return reachable;
    } on SocketException catch (e) {
      // No route to host (stale ARP) / refused / timeout → retry.
      debugPrint('[preview-probe] socket failure → retrying: ${e.osError}');
      return false;
    } on TimeoutException {
      debugPrint('[preview-probe] timed out → retrying');
      return false;
    } on Object catch (e) {
      debugPrint('[preview-probe] unexpected failure → retrying: $e');
      return false;
    } finally {
      socket?.destroy();
    }
  }
}

/// The active preview-reachability probe. Defaults to [RtspDescribeProbe] wired
/// to bind the process to the phone's Wi-Fi (STA) network for the probe;
/// overridden in tests with a fake that scripts reachable / isolated.
final previewProbeProvider = Provider<PreviewReachabilityProbe>((ref) {
  final wifi = ref.read(wifiServiceProvider);
  return RtspDescribeProbe(
    bindToWifi: wifi.bindProcessToWifi,
    clearBinding: wifi.clearProcessNetworkBinding,
  );
});

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
