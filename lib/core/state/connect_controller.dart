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
import 'package:logging/logging.dart';

import '../ble/ble_providers.dart';
import '../ble/ble_service.dart';
import '../models/command.dart';
import '../models/preview_layout.dart';
import '../models/session_snapshot.dart';
import '../services/log_service.dart';
import '../wifi/wifi_providers.dart' show previewLayoutProvider;
import '../../features/camera/camera_state.dart'
    show activeCameraIdProvider, activeOutputCameraProvider;
import '../../features/match/session/session_state.dart'
    show
        LiveMatchController,
        awayEndedNoticeText,
        finalizeLiveMatchRecord,
        isLiveMatchRunning,
        liveMatchProvider,
        sessionNoticeProvider;
import 'last_camera.dart';
import 'persisted_match_store.dart';

/// The last session snapshot adopted by a completed handshake, or null when
/// no handshake has completed (or the last one failed). Read by consumers
/// that need firmware actuals the selection providers don't carry — activity
/// flags, recording elapsed, match state/clock (U2 restore), per-camera
/// health (U3 gate folds this with live telemetry), last-session summary.
final _log = Logger('ConnectController');

final sessionSnapshotProvider = StateProvider<SessionSnapshot?>((_) => null);

/// A LOCAL follow-up failure from the last handshake's reconcile (persisted
/// store read, scoreboard restore, away-ended finalize). Distinct from wire
/// failures by design: a Drift hiccup must never make the camera
/// unconnectable, so the connect still succeeds and the problem surfaces
/// here instead. Null when the last handshake's local work completed clean.
final connectLocalIssueProvider = StateProvider<String?>((_) => null);

final connectControllerProvider = Provider<ConnectController>(
  ConnectController.new,
);

class ConnectController {
  ConnectController(this._ref, {this.handshakeTimeout = _kHandshakeTimeout});

  final Ref _ref;

  /// Sole budget for the whole connect + handshake. Generous on purpose: the
  /// platform BLE connect alone can take >10 s on a congested radio, and each
  /// handshake command already carries the service's per-command timeout.
  /// The service's platform-connect budget (BleServiceImpl.connectTimeout)
  /// stays BELOW this wall so an unresponsive connect self-cancels instead of
  /// being abandoned mid-flight (Dart timeouts never cancel). Injectable so
  /// the reconnect regression tests can run the wall in milliseconds.
  static const _kHandshakeTimeout = Duration(seconds: 30);
  final Duration handshakeTimeout;

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
    if (existing != null) {
      _log.debug('connect($deviceId) joined in-flight attempt');
      return existing;
    }
    final attempt = _connect(deviceId);
    _inFlight[deviceId] = attempt;
    return attempt;
  }

  Future<void> _connect(String deviceId) async {
    final svc = _ref.read(bleServiceProvider);
    final sw = Stopwatch()..start();
    _log.info('connect start → $deviceId');
    try {
      await _handshake(svc, deviceId).timeout(handshakeTimeout);

      // Success side effects shared by every former call site: mark the
      // camera active and persist it for the one-tap reconnect CTA
      // (best-effort — a persist failure must not fail the connect).
      _ref.read(activeCameraIdProvider.notifier).state = deviceId;
      unawaited(
        _ref.read(lastConnectedDeviceIdProvider.notifier).set(deviceId),
      );
      _log.info('connect OK → $deviceId in ${sw.elapsedMilliseconds}ms');
    } catch (e, st) {
      // Log the raw cause (with the GATT code / platform message on the
      // attached error) before it is normalized to a typed exception below —
      // this is the line that makes a failed connect diagnosable after the
      // fact instead of only surfacing as a faded snackbar.
      _log.error(
        'connect FAILED → $deviceId after ${sw.elapsedMilliseconds}ms: $e',
        e,
        st,
      );
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
    _ref.read(connectLocalIssueProvider.notifier).state = null;

    // 1. Wire link. The service resolves at `reconciling` — session-affecting
    //    UI gates on `connected` only, so everything stays locked from here
    //    until completeHandshake() (prevents a Record tap racing the snapshot).
    _log.debug('handshake[1/7] link up $deviceId');
    await svc.connect(deviceId);

    // 2. Protocol gate — refuse the session on version skew before pushing
    //    or reading anything else (bluetooth.proto: consumers MUST refuse on
    //    mismatch, not silently proceed).
    _log.debug('handshake[2/7] protocol gate');
    final info = await svc.getDeviceInfo(deviceId);
    if (info == null) {
      throw const BleHandshakeException('device info read failed');
    }
    if (info.protocolVersion != kAppProtocolVersion) {
      _log.warn(
        'protocol skew: app=$kAppProtocolVersion fw=${info.protocolVersion}',
      );
      throw BleProtocolVersionException(
        expected: kAppProtocolVersion,
        actual: info.protocolVersion,
      );
    }
    _log.debug(
      'handshake[2/7] OK fw=${info.firmwareVersion} proto=${info.protocolVersion}',
    );

    // 3. Time push — fixes device-LOCAL timestamps (file mtimes, summary
    //    fields); wire clocks stay monotonic so nothing else depends on it.
    _log.debug('handshake[3/7] time push');
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
    _log.debug('handshake[4/7] snapshot');
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
    _log.info(
      'handshake snapshot: phase=${snapshot.sessionPhase} '
      'rec=${snapshot.isRecording} stream=${snapshot.isStreaming} '
      'cam=${snapshot.activeCameraIndex}',
    );

    // 5. Rehydrate, 6. reconcile, 7. unlock.
    _log.debug('handshake[5/7] rehydrate providers');
    _rehydrate(deviceId, snapshot);
    _log.debug('handshake[6/7] reconcile');
    await _reconcile(svc, deviceId, snapshot);
    _log.debug('handshake[7/7] complete → connected');
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

  /// Push app-owned intent the firmware can't know, and settle the app's
  /// persisted match against the firmware's actual session (U2).
  ///
  /// Authority split: app scores/events are the authority (deltas made while
  /// disconnected never reached the firmware) — pushed via an absolute
  /// [SetMatchStateCommand]; the firmware clock is the authority (it is the
  /// only clock that ran), so the push leaves every clock field unset
  /// (absent fields are left untouched on the firmware) and the app adopts
  /// the snapshot's elapsed/clock_running locally instead.
  ///
  /// Failure split: a failed WIRE push is a handshake failure (typed, link
  /// dropped). LOCAL follow-ups (store read, scoreboard restore, away-ended
  /// finalize) must never make the camera unconnectable — their failures land
  /// in [connectLocalIssueProvider] and the connect still succeeds.
  Future<void> _reconcile(
    BleService svc,
    String deviceId,
    SessionSnapshot snapshot,
  ) async {
    final ms = snapshot.matchState;
    final msUuid = ms?.matchUuid;
    final runningUuid = (msUuid != null && msUuid.isNotEmpty) ? msUuid : null;
    // A session is RUNNING only outside idle/finalizing — an idle snapshot
    // that still reports the last match's state is an ended session.
    final sessionActive =
        runningUuid != null &&
        snapshot.sessionPhase != SessionPhase.idle &&
        snapshot.sessionPhase != SessionPhase.finalizing;

    PersistedLiveMatch? persisted;
    try {
      persisted = await _ref.read(persistedMatchStoreProvider).load(deviceId);
    } catch (e) {
      _localIssue('Saved match state could not be read: $e');
    }

    final liveCtl = _ref.read(liveMatchProvider.notifier);
    _log.debug(
      'reconcile: sessionActive=$sessionActive runningUuid=$runningUuid '
      'persisted=${persisted?.matchUuid ?? "none"}',
    );

    // 1. Persisted match matches the running session → silent rejoin:
    //    push app scores (wire), restore the scoreboard, adopt the fw clock.
    if (persisted != null &&
        persisted.isMidMatch &&
        sessionActive &&
        persisted.matchUuid == runningUuid) {
      _log.info('reconcile branch 1: silent rejoin (persisted == running)');
      await _pushScores(svc, deviceId, persisted.scoreA, persisted.scoreB);
      try {
        liveCtl.restoreFromPersisted(
          persisted,
          firmwareElapsedSeconds: ms!.elapsedSeconds,
          firmwareClockRunning: ms.clockRunning,
          isRecording: snapshot.isRecording,
          isStreaming: snapshot.isStreaming,
        );
      } catch (e) {
        _localIssue('Scoreboard restore failed: $e');
      }
      return;
    }

    // 2. Nothing persisted but the in-memory controller still tracks the
    //    running match (persist failed earlier / store wiped, app NOT
    //    killed): the memory scores are equally app-authoritative.
    if (persisted == null &&
        sessionActive &&
        liveCtl.matchId == runningUuid &&
        isLiveMatchRunning(_ref.read(liveMatchProvider))) {
      _log.info('reconcile branch 2: rejoin from in-memory match');
      final live = _ref.read(liveMatchProvider);
      await _pushScores(svc, deviceId, live.scoreHome, live.scoreAway);
      try {
        liveCtl.adoptFirmwareRuntime(
          elapsedSeconds: ms!.elapsedSeconds,
          clockRunning: ms.clockRunning,
          isRecording: snapshot.isRecording,
          isStreaming: snapshot.isStreaming,
        );
      } catch (e) {
        _localIssue('Clock adoption failed: $e');
      }
      return;
    }

    // 3. Stale persisted match (ended while away, camera runs a different
    //    match, or a crash landed between finalize and clear) — settle it
    //    FIRST so the row is never orphaned and is cleared exactly once.
    if (persisted != null &&
        (!sessionActive || persisted.matchUuid != runningUuid)) {
      _log.info('reconcile branch 3: settle stale persisted match');
      try {
        await _settleStalePersisted(deviceId, snapshot, persisted, liveCtl);
      } catch (e) {
        _localIssue('Away-ended finalize failed: $e');
      }
    }

    // 4. A running session the app holds no data for → adopt the
    //    firmware-derived scoreboard view (silent rejoin, origin R3). No
    //    SetMatchState push — nothing app-owned to assert.
    if (sessionActive &&
        persisted?.matchUuid != runningUuid &&
        liveCtl.matchId != runningUuid) {
      _log.info('reconcile branch 4: adopt firmware-only session view');
      try {
        liveCtl.adoptFirmwareView(
          ms!,
          isRecording: snapshot.isRecording,
          isStreaming: snapshot.isStreaming,
        );
      } catch (e) {
        _localIssue('Session adoption failed: $e');
      }
    }
  }

  /// Absolute score push — the WIRE half of reconcile. Clock fields stay
  /// unset (firmware clock wins). Failure here is a handshake failure.
  Future<void> _pushScores(
    BleService svc,
    String deviceId,
    int scoreA,
    int scoreB,
  ) async {
    final resp = await svc.sendCommand<void>(
      deviceId,
      SetMatchStateCommand(scoreA: scoreA, scoreB: scoreB),
    );
    if (!resp.isOk) {
      throw BleHandshakeException(
        'match-state reconcile failed: '
        '${resp.errorMessage ?? resp.status.name}',
      );
    }
  }

  /// Settle a persisted match that no longer matches a running session.
  ///
  /// - Mid-match → "ended while away": one-line notice (the last-session
  ///   summary is used ONLY when its uuid equals the persisted match's —
  ///   cross-match data never reaches the notice), finalize the team_matches
  ///   row with the persisted app data, clear the live store last.
  /// - Ended → a crash landed between finalize and clear: re-run the
  ///   idempotent finalize silently.
  /// - Pre-kickoff → nothing to finalize; just clear the stray row.
  Future<void> _settleStalePersisted(
    String deviceId,
    SessionSnapshot snapshot,
    PersistedLiveMatch persisted,
    LiveMatchController liveCtl,
  ) async {
    if (persisted.isMidMatch) {
      final summary = snapshot.lastSession;
      final matched =
          (summary != null && summary.matchUuid == persisted.matchUuid)
          ? summary
          : null;
      _ref.read(sessionNoticeProvider.notifier).state = awayEndedNoticeText(
        matched,
      );
      // If the in-memory controller still shows this match live (disconnect
      // without an app kill), follow the firmware: the session is over.
      if (liveCtl.matchId == persisted.matchUuid) {
        liveCtl.followAwayEnd();
      }
      await finalizeLiveMatchRecord(
        _ref,
        deviceId: deviceId,
        record: persisted,
      );
      return;
    }
    if (persisted.phase == PersistedMatchPhase.ended) {
      await finalizeLiveMatchRecord(
        _ref,
        deviceId: deviceId,
        record: persisted,
      );
      return;
    }
    // Pre-kickoff row (defensive — persist-on-change never writes these).
    await _ref
        .read(persistedMatchStoreProvider)
        .clear(deviceId, persisted.matchUuid);
  }

  void _localIssue(String message) {
    // Local (non-wire) reconcile hiccup — the connect still succeeds, but the
    // problem must be recoverable from the log, not just the transient banner.
    _log.warn('local reconcile issue: $message');
    _ref.read(connectLocalIssueProvider.notifier).state = message;
  }
}
