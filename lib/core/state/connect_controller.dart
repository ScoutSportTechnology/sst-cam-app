// Universal connect handshake — the ONLY caller of [BleService.connect].
//
// Every connect (first connect, manual reconnect, app relaunch, camera
// reboot — and U6's auto-reconnect loop) runs the same §9b sequence:
//
//   connect (BLE link + MTU + discover + notify)   → state: reconciling
//   → GetDeviceInfo protocol gate                  (refuse on version skew)
//   → SetDeviceTime (phone wall clock)
//   → GetSessionSnapshot                           (firmware ACTUAL state)
//   → REHYDRATE providers from the snapshot        (adopt, never force-reset)
//   → RECONCILE app-owned intent                   (SetMatchState push)
//   → completeHandshake                            → state: connected
//
// Page-anchored connect logic is gone: the documented reconnect-edge
// unreliability of the connection-state stream (see the retired
// selection_sync.dart rationale) plus auto-reconnect demanded one shared
// entry point that anchors behavior at connect, not at disconnect edges.
//
// Failure model: any step failing (or the whole handshake timing out) drops
// the BLE link and surfaces a typed exception — the app never sits in a
// half-hydrated state. The handshake timeout lives HERE and nowhere else:
// Dart's `Future.timeout` does not cancel the underlying operation, so a
// caller-side wrapper (the old settings-banner `.timeout(5s)`) would disagree
// with the service about whether the connect was still in flight.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ble/ble_providers.dart';
import '../ble/ble_service.dart';
import '../models/command.dart';
import '../models/preview_layout.dart';
import '../models/session_snapshot.dart';
import '../wifi/wifi_providers.dart' show previewLayoutProvider;
import '../../features/camera/camera_state.dart'
    show activeCameraIdProvider, activeOutputCameraProvider;
import 'last_camera.dart';
import 'persisted_match_store.dart';

/// The last session snapshot adopted by a completed handshake, or null when
/// no handshake has completed (or the last one failed). Read by consumers
/// that need firmware actuals the selection providers don't carry — activity
/// flags, recording elapsed, match state/clock (U2 restore), per-camera
/// health (U3 gate folds this with live telemetry), last-session summary.
final sessionSnapshotProvider = StateProvider<SessionSnapshot?>((_) => null);

final connectControllerProvider = Provider<ConnectController>(
  ConnectController.new,
);

class ConnectController {
  ConnectController(this._ref);

  final Ref _ref;

  /// Sole budget for the whole connect + handshake. Generous on purpose: the
  /// platform BLE connect alone can take >10 s on a congested radio, and each
  /// handshake command already carries the service's per-command timeout.
  static const handshakeTimeout = Duration(seconds: 30);

  // In-flight dedup (lifecycle-correctness learning): concurrent connect
  // requests for the same device share one attempt — a double tap or a manual
  // tap racing U6's reconnect loop must never run two handshakes at once.
  final Map<String, Future<void>> _inFlight = {};

  /// Connect to [deviceId] and run the full handshake. Resolves once the
  /// device is `connected` (reconcile done, pollers running). Throws
  /// [BleProtocolVersionException] on version skew, [BleConnectionException]
  /// on link failure, [BleHandshakeException] on any handshake failure or
  /// timeout — in every failure case the link has already been dropped.
  Future<void> connect(String deviceId) {
    final existing = _inFlight[deviceId];
    if (existing != null) return existing;
    final attempt = _connect(deviceId);
    _inFlight[deviceId] = attempt;
    return attempt;
  }

  Future<void> _connect(String deviceId) async {
    final svc = _ref.read(bleServiceProvider);
    try {
      await _handshake(svc, deviceId).timeout(handshakeTimeout);

      // Success side effects shared by every former call site: mark the
      // camera active and persist it for the one-tap reconnect CTA
      // (best-effort — a persist failure must not fail the connect).
      _ref.read(activeCameraIdProvider.notifier).state = deviceId;
      unawaited(
        _ref.read(lastConnectedDeviceIdProvider.notifier).set(deviceId),
      );
    } catch (e) {
      // Drop the link on ANY failure so no half-hydrated state survives. A
      // late completion of the abandoned handshake cannot resurrect the
      // connection: completeHandshake() no-ops unless the device is still
      // `reconciling`, and the disconnect below moves it to `disconnected`.
      _ref.read(sessionSnapshotProvider.notifier).state = null;
      try {
        await svc.disconnect(deviceId);
      } catch (_) {
        // Best-effort teardown — surface the original failure, not this one.
      }
      if (e is TimeoutException) {
        throw const BleHandshakeException('Connect handshake timed out');
      }
      if (e is BleConnectionException ||
          e is BleProtocolVersionException ||
          e is BleHandshakeException ||
          e is BleTimeoutException) {
        rethrow;
      }
      throw BleHandshakeException('Connect handshake failed: $e');
    } finally {
      _inFlight.remove(deviceId);
    }
  }

  Future<void> _handshake(BleService svc, String deviceId) async {
    // 1. Wire link. The service resolves at `reconciling` — session-affecting
    //    UI gates on `connected` only, so everything stays locked from here
    //    until completeHandshake() (prevents a Record tap racing the snapshot).
    await svc.connect(deviceId);

    // 2. Protocol gate — refuse the session on version skew before pushing
    //    or reading anything else (bluetooth.proto: consumers MUST refuse on
    //    mismatch, not silently proceed).
    final info = await svc.getDeviceInfo(deviceId);
    if (info == null) {
      throw const BleHandshakeException('device info read failed');
    }
    if (info.protocolVersion != kAppProtocolVersion) {
      throw BleProtocolVersionException(
        expected: kAppProtocolVersion,
        actual: info.protocolVersion,
      );
    }

    // 3. Time push — fixes device-LOCAL timestamps (file mtimes, summary
    //    fields); wire clocks stay monotonic so nothing else depends on it.
    final timeResp = await svc.sendCommand<void>(
      deviceId,
      SetDeviceTimeCommand(epochMs: DateTime.now().millisecondsSinceEpoch),
    );
    if (!timeResp.isOk) {
      throw BleHandshakeException(
        'device time push failed: '
        '${timeResp.errorMessage ?? timeResp.status.name}',
      );
    }

    // 4. Snapshot — the firmware's ACTUAL state (a session outlives the BLE
    //    connection; never assume idle/defaults).
    final snapResp = await svc.sendCommand<SessionSnapshot>(
      deviceId,
      GetSessionSnapshotCommand(),
    );
    final snapshot = snapResp.payload;
    if (!snapResp.isOk || snapshot == null) {
      throw BleHandshakeException(
        'session snapshot read failed: '
        '${snapResp.errorMessage ?? snapResp.status.name}',
      );
    }

    // 5. Rehydrate, 6. reconcile, 7. unlock.
    _rehydrate(deviceId, snapshot);
    await _reconcile(svc, deviceId, snapshot);
    svc.completeHandshake(deviceId);
  }

  /// Adopt the firmware's actual selections into the providers the UI already
  /// watches — adoption replaces the old force-reset-on-connect. Runtime
  /// facts (activity flags, recording elapsed, match state) ride
  /// [sessionSnapshotProvider] for the U2 restore / U3 health consumers.
  ///
  /// Observed state vs user intent stay separate values (settings-toggle
  /// learning): these providers hold *session-scoped observed selections*,
  /// not persisted preferences — adopting them never rewrites saved intent.
  void _rehydrate(String deviceId, SessionSnapshot snapshot) {
    // Absent selection fields (contractually only possible on firmware that
    // predates reporting) fall back to the firmware's fresh-session defaults
    // — the one thing the old reset behavior got right is that the UI must
    // match the firmware, never a stale app-side selection.
    _ref.read(activeOutputCameraProvider.notifier).state =
        snapshot.activeCameraIndex ?? 0;
    _ref.read(previewLayoutProvider(deviceId).notifier).state =
        snapshot.previewLayout ?? PreviewLayout.single;
    _ref.read(sessionSnapshotProvider.notifier).state = snapshot;
  }

  /// Push app-owned intent the firmware can't know. App scores are the
  /// authority (deltas made while disconnected never reached the firmware);
  /// the firmware clock is the authority (it is the only clock that ran) —
  /// so the push carries scores only and leaves every clock field unset
  /// (SetMatchState absent fields are left untouched on the firmware).
  Future<void> _reconcile(
    BleService svc,
    String deviceId,
    SessionSnapshot snapshot,
  ) async {
    final runningUuid = snapshot.matchState?.matchUuid;
    if (runningUuid == null || runningUuid.isEmpty) {
      // No session config was ever pushed — nothing to reconcile.
      return;
    }
    final persisted = await _ref
        .read(persistedMatchStoreProvider)
        .load(deviceId);
    if (persisted == null || persisted.matchUuid != runningUuid) {
      // Unknown running session (no persisted match for this uuid): adopt the
      // firmware-derived view silently — the snapshot is already exposed via
      // [sessionSnapshotProvider]; U2's restore path rebuilds the scoreboard
      // view from it. No SetMatchState push (nothing app-owned to assert).
      return;
    }
    final resp = await svc.sendCommand<void>(
      deviceId,
      SetMatchStateCommand(scoreA: persisted.scoreA, scoreB: persisted.scoreB),
    );
    if (!resp.isOk) {
      throw BleHandshakeException(
        'match-state reconcile failed: '
        '${resp.errorMessage ?? resp.status.name}',
      );
    }
  }
}
