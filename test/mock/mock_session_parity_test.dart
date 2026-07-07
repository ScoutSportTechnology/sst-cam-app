// U7 — mock firmware parity: full session semantics on the emulated firmware.
//
// Every behaviour asserted here mirrors a documented wire contract (proto
// §9/§9b/§10) or firmware plan unit (U1 session survival + auto-stop +
// finalize CAS + boot orphans, U2 SetMatchState absolute semantics, U3
// camera-failure finalize + health transitions). The mock IS a second source
// of contract truth (mock-parity learning): these tests pin its wire
// behaviour so app suites can't go green against fiction.

import 'package:flutter_test/flutter_test.dart';
import 'package:sst_cam_app/core/models/command.dart';
import 'package:sst_cam_app/core/models/device.dart';
import 'package:sst_cam_app/core/models/match.dart';
import 'package:sst_cam_app/core/models/session_snapshot.dart';
import 'package:sst_cam_app/core/models/telemetry.dart';
import 'package:sst_cam_app/core/models/wifi.dart';
import 'package:sst_cam_app/mock/emulator/mock_ble_service.dart';

const _kDeviceId = 'SST-CAM-001';

PushSessionConfig _config({
  String matchUuid = 'm-1',
  int autoStopMinutes = 2,
}) => PushSessionConfig(
  matchUuid: matchUuid,
  userUuid: 'u-1',
  sport: 'soccer',
  numPeriods: 2,
  periodLengthSeconds: 2100,
  videoOutputPath: '/videos/u-1/$matchUuid/',
  thumbnailOutputPath: '/thumbs/u-1/$matchUuid/',
  autoStopMinutes: autoStopMinutes,
);

MatchState _match({
  String uuid = 'm-1',
  int elapsed = 600,
  bool clockRunning = true,
  int scoreA = 0,
  int scoreB = 0,
  int period = 1,
}) => MatchState(
  status: MatchStatus.active,
  currentPeriod: period,
  timeRemainingSeconds: 0,
  scoreA: scoreA,
  scoreB: scoreB,
  teamAId: 'team-a',
  teamBId: 'team-b',
  updatedAt: DateTime.now(),
  elapsedSeconds: elapsed,
  clockRunning: clockRunning,
  matchUuid: uuid,
);

void main() {
  setUpAll(TestWidgetsFlutterBinding.ensureInitialized);

  late MockBleService mock;

  setUp(() {
    mock = MockBleService(
      scanDeviceAppearDelays: const [Duration.zero, Duration.zero],
      connectionDelay: Duration.zero,
      failureRate: 0.0,
      randomSeed: 42,
    );
  });

  tearDown(() => mock.dispose());

  Future<SessionSnapshot> snapshot() async {
    final resp = await mock.sendCommand<SessionSnapshot>(
      _kDeviceId,
      GetSessionSnapshotCommand(),
    );
    expect(resp.isOk, isTrue);
    return resp.payload!;
  }

  Future<void> startRecording() async {
    final resp = await mock.sendCommand<void>(
      _kDeviceId,
      RecordingControlCommand(action: RecordingControlAction.start),
    );
    expect(resp.isOk, isTrue);
  }

  group('Session survives disconnects (fw U1 / proto §9b)', () {
    test('active session keeps running across an unexpected drop; the match '
        'clock and recording elapsed TICK while disconnected; the rejoin '
        'snapshot reflects the advanced clock', () async {
      var now = DateTime(2026, 7, 6, 12);
      mock.nowProvider = () => now;

      await mock.connect(_kDeviceId);
      mock.completeHandshake(_kDeviceId);
      await mock.pushSessionConfig(_kDeviceId, _config());
      await startRecording();
      mock.snapshotMatchState = _match(elapsed: 600, clockRunning: true);

      // The link dies. The firmware session runs on; a real gap elapses.
      mock.simulateUnexpectedDrop(_kDeviceId);
      now = now.add(const Duration(seconds: 95));

      await mock.connect(_kDeviceId); // rejoin
      final snap = await snapshot();

      expect(snap.sessionPhase, SessionPhase.recording);
      expect(snap.isRecording, isTrue);
      // §9b: "the firmware clock is authority — it is the only clock that
      // ran" — the gap advanced it.
      expect(snap.matchState!.elapsedSeconds, 600 + 95);
      expect(snap.matchState!.clockRunning, isTrue);
      // Monotonic recording elapsed also advanced across the gap.
      expect(snap.recordingElapsedSeconds, 95);
      // No summary: the session never ended.
      expect(snap.lastSession, isNull);
    });

    test('paused clock does NOT tick across a gap', () async {
      var now = DateTime(2026, 7, 6, 12);
      mock.nowProvider = () => now;
      mock.snapshotMatchState = _match(elapsed: 300, clockRunning: false);

      now = now.add(const Duration(seconds: 50));

      expect(mock.snapshotMatchState!.elapsedSeconds, 300);
    });
  });

  group('Auto-stop safety net (proto §9 auto_stop_minutes / fw U1)', () {
    test('fires after auto_stop_minutes on the compressed timescale: session '
        'finalizes to idle with an auto-stop summary and the group goes '
        'down', () async {
      var now = DateTime(2026, 7, 6, 12);
      mock.nowProvider = () => now;
      mock.autoStopMinuteUnit = const Duration(milliseconds: 5);

      await mock.connect(_kDeviceId);
      mock.completeHandshake(_kDeviceId);
      await mock.pushSessionConfig(
        _kDeviceId,
        _config(autoStopMinutes: 2), // 2 "minutes" → 10 ms
      );
      await mock.sendCommand<WifiDirectGroup>(
        _kDeviceId,
        StartWifiDirectCommand(),
      );
      await startRecording();
      mock.snapshotMatchState = _match(elapsed: 600, clockRunning: true);

      mock.simulateUnexpectedDrop(_kDeviceId);
      // The clock ran on unsupervised until the safety net fired.
      now = now.add(const Duration(seconds: 120));
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(mock.isRecordingActive, isFalse);
      expect(
        mock.mockWifiGroupUp,
        isFalse,
        reason: 'auto-stop tears the group down',
      );

      await mock.connect(_kDeviceId);
      final snap = await snapshot();
      expect(snap.sessionPhase, SessionPhase.idle);
      expect(snap.isRecording, isFalse);
      expect(snap.wifiGroupUp, isFalse);
      final summary = snap.lastSession!;
      expect(summary.endReason, SessionEndReason.autoStop);
      expect(summary.matchUuid, 'm-1');
      // End clock captured at finalize — the clock that ticked while away.
      expect(summary.endClockSeconds, 600 + 120);
      // Clean finalize: moov written, file playable.
      expect(summary.fileValid, isTrue);
    });

    test('reconnect cancels the armed timer — the session never auto-stops '
        'under supervision', () async {
      mock.autoStopMinuteUnit = const Duration(milliseconds: 5);
      await mock.connect(_kDeviceId);
      mock.completeHandshake(_kDeviceId);
      await mock.pushSessionConfig(
        _kDeviceId,
        _config(autoStopMinutes: 8), // 40 ms fuse
      );
      await startRecording();

      mock.simulateUnexpectedDrop(_kDeviceId);
      await mock.connect(_kDeviceId); // rejoin at timeout−ε: cancel wins

      // Well past where the fuse would have fired.
      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(mock.isRecordingActive, isTrue);
      final snap = await snapshot();
      expect(snap.sessionPhase, SessionPhase.recording);
      expect(snap.lastSession, isNull);
    });

    test('streaming-only session auto-stops too; no file → file_valid '
        'absent', () async {
      mock.autoStopMinuteUnit = const Duration(milliseconds: 5);
      await mock.connect(_kDeviceId);
      mock.completeHandshake(_kDeviceId);
      await mock.pushSessionConfig(_kDeviceId, _config(autoStopMinutes: 2));
      await mock.sendCommand<void>(
        _kDeviceId,
        StreamingControlCommand(action: StreamingControlAction.start),
      );

      mock.simulateUnexpectedDrop(_kDeviceId);
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(mock.isStreamingActive, isFalse);
      expect(mock.mockLastSessionSummary!.endReason, SessionEndReason.autoStop);
      expect(mock.mockLastSessionSummary!.fileValid, isNull);
    });
  });

  group('Finalize (fw U1 CAS + fw U3 camera failure)', () {
    test('injecting DOWN mid-recording finalizes with end-reason '
        'camera-failure; the FINALIZING window is observable in the '
        'snapshot', () async {
      mock.finalizeDuration = const Duration(milliseconds: 400);
      await mock.pushSessionConfig(_kDeviceId, _config());
      await startRecording();
      mock.snapshotMatchState = _match(elapsed: 240, clockRunning: false);

      mock.mockCamera0Health = CameraHealth.down; // fw U3 session hook

      // Snapshot read during the finalize window: a real FINALIZING state,
      // never a torn intermediate (proto §9b SessionPhase).
      final during = await snapshot();
      expect(during.sessionPhase, SessionPhase.finalizing);
      expect(during.isRecording, isFalse, reason: 'EOS already issued');
      expect(during.lastSession, isNull, reason: 'summary not yet written');
      expect(during.camera0Health, CameraHealth.down);

      await Future<void>.delayed(const Duration(milliseconds: 400));
      final after = await snapshot();
      expect(after.sessionPhase, SessionPhase.idle);
      final summary = after.lastSession!;
      expect(summary.endReason, SessionEndReason.cameraFailure);
      expect(summary.endClockSeconds, 240);
      expect(summary.fileValid, isTrue, reason: 'finalized cleanly');
    });

    test('app-commanded stop is a finalize trigger too: idle snapshot '
        'carries an app-stop summary; the group is NOT torn down', () async {
      await mock.pushSessionConfig(_kDeviceId, _config());
      await mock.sendCommand<WifiDirectGroup>(
        _kDeviceId,
        StartWifiDirectCommand(),
      );
      await startRecording();
      mock.snapshotMatchState = _match(elapsed: 500, clockRunning: false);

      await mock.sendCommand<void>(
        _kDeviceId,
        RecordingControlCommand(action: RecordingControlAction.stop),
      );

      final snap = await snapshot();
      expect(snap.sessionPhase, SessionPhase.idle);
      final summary = snap.lastSession!;
      expect(summary.endReason, SessionEndReason.appStop);
      expect(summary.endClockSeconds, 500);
      expect(summary.fileValid, isTrue);
      // App-commanded stop leaves the group to the app (only auto-stop and
      // reboot take it down).
      expect(snap.wifiGroupUp, isTrue);
    });

    test('stop when nothing is running mints no summary (idempotent, '
        'fw U1 command-race edge)', () async {
      await mock.sendCommand<void>(
        _kDeviceId,
        RecordingControlCommand(action: RecordingControlAction.stop),
      );
      expect(mock.mockLastSessionSummary, isNull);
    });
  });

  group('Per-camera health (fw U3 / proto DeviceTelemetry 15-16)', () {
    test('injected DOWN propagates identically through telemetry AND '
        'snapshot, and the wire refuses start-class commands', () async {
      mock.mockCamera1Health = CameraHealth.down;

      final tel = await mock.sendCommand<DeviceTelemetry>(
        _kDeviceId,
        GetTelemetryCommand(),
      );
      expect(tel.payload!.camera0Health, CameraHealth.ok);
      expect(tel.payload!.camera1Health, CameraHealth.down);

      final snap = await snapshot();
      expect(snap.camera0Health, CameraHealth.ok);
      expect(snap.camera1Health, CameraHealth.down);

      final start = await mock.sendCommand<void>(
        _kDeviceId,
        RecordingControlCommand(action: RecordingControlAction.start),
      );
      expect(start.isDeviceInoperable, isTrue);
      expect(mock.isRecordingActive, isFalse);
    });

    test('scripted RECOVERING → DOWN → OK sequence plays out over time '
        '(flap seam); no session, no finalize', () async {
      mock.scheduleCameraHealthSequence(0, const [
        CameraHealth.recovering,
        CameraHealth.down,
        CameraHealth.ok,
      ], interval: const Duration(milliseconds: 30));

      final seen = <CameraHealth>[mock.mockCamera0Health];
      final sw = Stopwatch()..start();
      while (sw.elapsed < const Duration(seconds: 2)) {
        final h = mock.mockCamera0Health;
        if (seen.last != h) seen.add(h);
        if (seen.contains(CameraHealth.down) && h == CameraHealth.ok) break;
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }

      expect(
        seen,
        containsAllInOrder([
          CameraHealth.recovering,
          CameraHealth.down,
          CameraHealth.ok,
        ]),
        reason: 'script must walk the full flap; saw $seen',
      );
      expect(mock.mockCamera0Health, CameraHealth.ok);
      expect(mock.mockLastSessionSummary, isNull);
    });

    test('a scripted DOWN mid-recording goes through the same finalize hook '
        'as a direct injection', () async {
      await mock.pushSessionConfig(_kDeviceId, _config());
      await startRecording();

      mock.scheduleCameraHealthSequence(1, const [
        CameraHealth.recovering,
        CameraHealth.down,
      ], interval: const Duration(milliseconds: 10));
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(mock.isRecordingActive, isFalse);
      expect(
        mock.mockLastSessionSummary!.endReason,
        SessionEndReason.cameraFailure,
      );
    });
  });

  group('Idempotent StartWifiDirect (proto §10)', () {
    test('second Start while the group is up returns the SAME credentials '
        'with zero re-formation; the group survives a BLE drop mid-session '
        'and the rejoin Start still does not re-form', () async {
      await mock.connect(_kDeviceId);
      mock.completeHandshake(_kDeviceId);
      await startRecording();

      final first = await mock.sendCommand<WifiDirectGroup>(
        _kDeviceId,
        StartWifiDirectCommand(),
      );
      expect(mock.wifiGroupFormationCount, 1);
      expect(mock.mockWifiGroupUp, isTrue);

      final second = await mock.sendCommand<WifiDirectGroup>(
        _kDeviceId,
        StartWifiDirectCommand(),
      );
      expect(second.payload!.ssid, first.payload!.ssid);
      expect(second.payload!.psk, first.payload!.psk);
      expect(mock.wifiGroupFormationCount, 1, reason: 'no re-formation');

      // BLE drops mid-session: the group stays up (fw U1 — OnDisconnect no
      // longer tears down WiFi while a session is active).
      mock.simulateUnexpectedDrop(_kDeviceId);
      expect(mock.mockWifiGroupUp, isTrue);
      final snap = await snapshot();
      expect(snap.wifiGroupUp, isTrue);

      // Rejoin path: the app's default path goes through StartWifiDirect.
      await mock.connect(_kDeviceId);
      final rejoin = await mock.sendCommand<WifiDirectGroup>(
        _kDeviceId,
        StartWifiDirectCommand(),
      );
      expect(rejoin.payload!.ssid, first.payload!.ssid);
      expect(mock.wifiGroupFormationCount, 1);
    });

    test('Stop takes the group down; the next Start re-forms', () async {
      await mock.sendCommand<WifiDirectGroup>(
        _kDeviceId,
        StartWifiDirectCommand(),
      );
      await mock.sendCommand<void>(_kDeviceId, StopWifiDirectCommand());
      expect(mock.mockWifiGroupUp, isFalse);

      await mock.sendCommand<WifiDirectGroup>(
        _kDeviceId,
        StartWifiDirectCommand(),
      );
      expect(mock.wifiGroupFormationCount, 2);
    });
  });

  group('SetMatchState — absolute semantics (proto §9b / fw U2)', () {
    test('present fields overwrite; ABSENT fields are left untouched; '
        'GetMatchState agrees with the push', () async {
      mock.snapshotMatchState = _match(
        uuid: 'm-9',
        elapsed: 300,
        clockRunning: false,
        scoreA: 1,
        scoreB: 1,
        period: 1,
      );

      // Partial absolute set: only score_a present.
      await mock.sendCommand<void>(_kDeviceId, SetMatchStateCommand(scoreA: 4));

      final ms = (await mock.sendCommand<MatchState>(
        _kDeviceId,
        GetMatchStateCommand(),
      )).payload!;
      expect(ms.scoreA, 4);
      expect(ms.scoreB, 1, reason: 'absent field untouched');
      expect(ms.currentPeriod, 1, reason: 'absent field untouched');
      expect(ms.elapsedSeconds, 300, reason: 'absent clock untouched');
      expect(ms.clockRunning, isFalse);
      expect(ms.matchUuid, 'm-9');

      // Snapshot reads the same truth.
      final snap = await snapshot();
      expect(snap.matchState!.scoreA, 4);
      expect(snap.matchState!.elapsedSeconds, 300);
    });

    test(
      'setting elapsed + clock_running re-anchors a ticking clock',
      () async {
        var now = DateTime(2026, 7, 6, 12);
        mock.nowProvider = () => now;

        await mock.sendCommand<void>(
          _kDeviceId,
          SetMatchStateCommand(elapsedSeconds: 100, clockRunning: true),
        );
        now = now.add(const Duration(seconds: 30));

        final ms = (await mock.sendCommand<MatchState>(
          _kDeviceId,
          GetMatchStateCommand(),
        )).payload!;
        expect(ms.elapsedSeconds, 130);
      },
    );
  });

  group('Boot-orphan reboot seam (fw U1 boot scan / AE2)', () {
    test('reboot mid-recording: bare drop, next connect reads a first-connect '
        'shape (idle, default selections, no match state) plus the orphan '
        'summary with file_valid=false', () async {
      await mock.connect(_kDeviceId);
      mock.completeHandshake(_kDeviceId);
      await mock.pushSessionConfig(_kDeviceId, _config(matchUuid: 'm-orphan'));
      await startRecording();
      mock.snapshotMatchState = _match(uuid: 'm-orphan', elapsed: 800);
      await mock.sendCommand<WifiDirectGroup>(
        _kDeviceId,
        StartWifiDirectCommand(),
      );
      await mock.sendCommand<void>(
        _kDeviceId,
        SetActiveCameraCommand(cameraIndex: 1),
      );

      final states = <CameraConnectionState>[];
      mock.connectionStateStream(_kDeviceId).listen(states.add);

      mock.simulateReboot(_kDeviceId);
      await Future<void>.delayed(Duration.zero);

      // Power loss: bare disconnected, never `disconnecting`.
      expect(states, [CameraConnectionState.disconnected]);

      await mock.connect(_kDeviceId);
      final snap = await snapshot();
      expect(snap.sessionPhase, SessionPhase.idle);
      expect(snap.isRecording, isFalse);
      expect(snap.matchState, isNull, reason: 'in-memory LiveMatch lost');
      expect(snap.activeCameraIndex, 0, reason: 'selections reset to defaults');
      expect(snap.wifiGroupUp, isFalse);
      final summary = snap.lastSession!;
      expect(summary.endReason, SessionEndReason.reboot);
      expect(summary.matchUuid, 'm-orphan');
      expect(
        summary.fileValid,
        isFalse,
        reason: 'crash artifact — moov never written',
      );
      expect(
        summary.endClockSeconds,
        isNull,
        reason: 'firmware never saw the end',
      );
    });

    test('streaming-only reboot leaves no orphan file → no summary', () async {
      await mock.connect(_kDeviceId);
      await mock.sendCommand<void>(
        _kDeviceId,
        StreamingControlCommand(action: StreamingControlAction.start),
      );

      mock.simulateReboot(_kDeviceId);

      await mock.connect(_kDeviceId);
      final snap = await snapshot();
      expect(snap.sessionPhase, SessionPhase.idle);
      expect(snap.lastSession, isNull);
    });
  });

  group('Telemetry activity-flag parity (proto DeviceTelemetry 11/12)', () {
    test('the proto GetTelemetry path reports live activity exactly like the '
        'stream path (fixed field-11/12 drift)', () async {
      await startRecording();
      await mock.sendCommand<void>(
        _kDeviceId,
        StreamingControlCommand(action: StreamingControlAction.start),
      );

      final tel = (await mock.sendCommand<DeviceTelemetry>(
        _kDeviceId,
        GetTelemetryCommand(),
      )).payload!;
      expect(tel.isRecording, isTrue);
      expect(tel.isStreaming, isTrue);
    });
  });
}
