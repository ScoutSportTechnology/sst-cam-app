// U2 — scoreboard persistence + clock reconcile + away-ended handling.
//
// Proves the plan's U2 scenarios end-to-end against the parity mock and a
// real (in-memory) Drift store shared across "app kills" (containers):
// AE1 restore, AE4 away-ended finalize, drift correction, period-end
// auto-fire, device keying, firmware-view fallback, summary absent/mismatch,
// crash-between-finalize-and-clear, wire-vs-local failure split, and the
// poll-truth uncommanded-stop follower.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sst_cam_app/core/ble/ble_providers.dart';
import 'package:sst_cam_app/core/models/device.dart';
import 'package:sst_cam_app/core/models/match.dart';
import 'package:sst_cam_app/core/models/session_snapshot.dart';
import 'package:sst_cam_app/core/models/telemetry.dart';
import 'package:sst_cam_app/core/state/connect_controller.dart';
import 'package:sst_cam_app/core/state/persisted_match_store.dart';
import 'package:sst_cam_app/features/camera/camera_state.dart'
    show activeCameraIdProvider;
import 'package:sst_cam_app/features/match/session/session_state.dart';
import 'package:sst_cam_app/mock/emulator/mock_ble_service.dart';

import '../../../test_helpers.dart';

const _kDeviceA = 'SST-CAM-001';
const _kDeviceB = 'SST-CAM-002';

MatchState _fwMatch(
  String uuid, {
  int scoreA = 0,
  int scoreB = 0,
  int? elapsed,
  bool? clockRunning,
  int period = 1,
  MatchStatus status = MatchStatus.active,
}) => MatchState(
  status: status,
  currentPeriod: period,
  timeRemainingSeconds: 0,
  scoreA: scoreA,
  scoreB: scoreB,
  teamAId: 'team-a-uuid',
  teamBId: 'Eastfield FC',
  updatedAt: DateTime.now(),
  elapsedSeconds: elapsed,
  clockRunning: clockRunning,
  matchUuid: uuid,
);

DeviceTelemetry _telemetry({required bool isRecording}) => DeviceTelemetry(
  storageFreeBytes: 1024,
  storageTotalBytes: 2048,
  wifiState: WifiState.connected,
  internetReachable: true,
  tempCelsius: 40,
  ramUsedPct: 50,
  cpuUsedPct: 50,
  uptimeSeconds: 100,
  isRecording: isRecording,
  isStreaming: false,
);

/// Store whose load always throws — the local-failure half of the
/// wire-vs-local split.
class _ThrowingStore implements PersistedMatchStore {
  @override
  Future<PersistedLiveMatch?> load(String deviceId) async =>
      throw StateError('simulated store failure');

  @override
  Future<void> save(String deviceId, PersistedLiveMatch match) async {}

  @override
  Future<void> clear(String deviceId, String matchUuid) async {}
}

void main() {
  setUpAll(TestWidgetsFlutterBinding.ensureInitialized);

  final db = useInMemoryDb();
  late MockBleService mock;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    mock = MockBleService(
      scanDeviceAppearDelays: const [Duration.zero, Duration.zero],
      connectionDelay: Duration.zero,
      failureRate: 0.0,
      randomSeed: 42,
    );
  });

  tearDown(() => mock.dispose());

  ProviderContainer makeContainer({List<Override> extra = const []}) {
    final container = ProviderContainer(
      overrides: [
        bleServiceProvider.overrideWithValue(mock),
        ...dbOverrides(db.value),
        ...extra,
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  /// Load the seeded upcoming match into the controller and kick off.
  void startMatch(ProviderContainer c, {String matchId = seedMatchUp1Id}) {
    final ctl = c.read(liveMatchProvider.notifier);
    ctl.loadFromUpcoming(
      matchId: matchId,
      teamShortName: 'NRA',
      teamName: 'Northside Rovers U14',
      opponent: 'vs Eastfield FC',
      numPeriods: 2,
      periodLengthSeconds: 2100,
    );
    ctl.startPeriod(startRecording: true);
  }

  void scoreGoals(ProviderContainer c, {int home = 0, int away = 0}) {
    final ctl = c.read(liveMatchProvider.notifier);
    for (var i = 0; i < home; i++) {
      ctl.addEvent(type: 'Goal', teamLabel: 'NRA');
    }
    for (var i = 0; i < away; i++) {
      ctl.addEvent(type: 'Goal', teamLabel: 'Eastfield FC');
    }
  }

  group('AE1 — kill mid-recording, reopen, connect', () {
    test('scoreboard restores 2–1, recording in progress, clock = firmware '
        'elapsed, app scores pushed via SetMatchState', () async {
      // Session 1: connected camera, kickoff, 2–1, then the app dies.
      final c1 = makeContainer();
      c1.read(activeCameraIdProvider.notifier).state = _kDeviceA;
      startMatch(c1);
      scoreGoals(c1, home: 2, away: 1);
      await pumpEventQueue(); // flush the unawaited persist writes
      c1.dispose(); // app kill — only the Drift store survives

      // Firmware kept the session alive through the kill.
      mock.snapshotMatchState = _fwMatch(
        seedMatchUp1Id,
        elapsed: 900,
        clockRunning: true,
      );
      mock.mockSessionPhase = SessionPhase.recording;
      mock.isRecordingActive = true;
      mock.snapshotRecordingElapsedSeconds = 950;

      // Session 2: fresh container (fresh in-memory providers), same store.
      final c2 = makeContainer();
      await c2.read(connectControllerProvider).connect(_kDeviceA);

      final live = c2.read(liveMatchProvider);
      expect(live.scoreHome, 2);
      expect(live.scoreAway, 1);
      expect(live.phase, MatchPhase.period);
      expect(live.rec, RecState.recording);
      // Firmware clock wins — it is the only clock that ran (and the U7
      // parity mock keeps it ticking in real time, so adopted >= injected).
      expect(live.elapsedSeconds, greaterThanOrEqualTo(900));
      expect(live.timer, MatchTimer.running);
      // Events survived the kill.
      expect(
        live.events.where((e) => e.label.startsWith('Goal')),
        hasLength(3),
      );
      // App scores are the wire authority; clock fields stay unset.
      final push = mock.lastSetMatchState;
      expect(push, isNotNull);
      expect(push!.scoreA, 2);
      expect(push.scoreB, 1);
      expect(push.elapsedSeconds, isNull);
      expect(push.clockRunning, isNull);
      // No away-ended notice — this is a silent rejoin.
      expect(c2.read(sessionNoticeProvider), isNull);
      expect(c2.read(connectLocalIssueProvider), isNull);
    });

    test(
      'persisted match for camera A never hydrates against camera B',
      () async {
        final c1 = makeContainer();
        c1.read(activeCameraIdProvider.notifier).state = _kDeviceA;
        startMatch(c1);
        scoreGoals(c1, home: 2, away: 1);
        await pumpEventQueue();
        c1.dispose();

        // Camera B runs a session with the SAME uuid (pathological, but the
        // device key must hold regardless).
        mock.snapshotMatchState = _fwMatch(seedMatchUp1Id, elapsed: 300);
        mock.mockSessionPhase = SessionPhase.recording;

        final c2 = makeContainer();
        await c2.read(connectControllerProvider).connect(_kDeviceB);

        // No restore — camera B has no persisted match; the firmware view is
        // adopted instead (fw scores 0–0, not the 2–1 persisted under camera A).
        expect(mock.lastSetMatchState, isNull);
        final live = c2.read(liveMatchProvider);
        expect(live.scoreHome, 0);
        expect(live.scoreAway, 0);
      },
    );

    test('app killed before first persist → firmware-derived view, no crash, '
        'no SetMatchState push', () async {
      mock.snapshotMatchState = _fwMatch(
        seedMatchUp2Id,
        scoreA: 1,
        scoreB: 2,
        elapsed: 1000,
        clockRunning: true,
        period: 2,
      );
      mock.mockSessionPhase = SessionPhase.recording;
      mock.isRecordingActive = true;

      final c = makeContainer();
      await c.read(connectControllerProvider).connect(_kDeviceA);

      final live = c.read(liveMatchProvider);
      expect(live.phase, MatchPhase.period);
      expect(live.scoreHome, 1);
      expect(live.scoreAway, 2);
      expect(live.currentPeriod, 2);
      // >= because the U7 parity mock's clock ticks in real time.
      expect(live.elapsedSeconds, greaterThanOrEqualTo(1000));
      expect(live.rec, RecState.recording);
      expect(live.awayName, 'Eastfield FC');
      expect(c.read(liveMatchProvider.notifier).matchId, seedMatchUp2Id);
      expect(mock.lastSetMatchState, isNull);
      expect(c.read(sessionNoticeProvider), isNull);
    });
  });

  group('AE4 (app half) — ended while away', () {
    Future<void> persistMidMatch({String uuid = seedMatchUp1Id}) async {
      final c1 = makeContainer();
      c1.read(activeCameraIdProvider.notifier).state = _kDeviceA;
      startMatch(c1, matchId: uuid);
      scoreGoals(c1, home: 2, away: 1);
      await pumpEventQueue();
      c1.dispose();
    }

    test('auto-stop summary → notice with end reason, team_matches finalized, '
        'live store cleared', () async {
      await persistMidMatch();
      // Firmware auto-stopped while away: idle snapshot + matching summary.
      mock.mockLastSessionSummary = const LastSessionSummary(
        matchUuid: seedMatchUp1Id,
        endReason: SessionEndReason.autoStop,
        endClockSeconds: 2832,
        fileValid: true,
      );

      final c2 = makeContainer();
      await c2.read(connectControllerProvider).connect(_kDeviceA);

      expect(c2.read(sessionNoticeProvider), contains('auto-stopped'));
      final row = await db.value.teamsDao.getMatchById(seedMatchUp1Id);
      expect(row!.kind, 'past');
      expect(row.result, '2-1');
      final store = DriftPersistedMatchStore(db.value);
      expect(await store.load(_kDeviceA), isNull);
      expect(c2.read(connectLocalIssueProvider), isNull);
    });

    test('saved-at-clock end reason renders the end clock', () async {
      await persistMidMatch();
      mock.mockLastSessionSummary = const LastSessionSummary(
        matchUuid: seedMatchUp1Id,
        endReason: SessionEndReason.appStop,
        endClockSeconds: 47 * 60 + 12,
      );
      final c2 = makeContainer();
      await c2.read(connectControllerProvider).connect(_kDeviceA);
      expect(c2.read(sessionNoticeProvider), contains('saved at 47:12'));
    });

    test('camera-restarted end reason points at the recording', () async {
      await persistMidMatch();
      mock.mockLastSessionSummary = const LastSessionSummary(
        matchUuid: seedMatchUp1Id,
        endReason: SessionEndReason.reboot,
      );
      final c2 = makeContainer();
      await c2.read(connectControllerProvider).connect(_kDeviceA);
      expect(
        c2.read(sessionNoticeProvider),
        contains('camera restarted, check the recording'),
      );
    });

    test('summary absent (older firmware) → generic notice, finalization '
        'still completes', () async {
      await persistMidMatch();
      // Idle snapshot, no last-session summary at all.
      final c2 = makeContainer();
      await c2.read(connectControllerProvider).connect(_kDeviceA);

      expect(c2.read(sessionNoticeProvider), 'Match ended while away.');
      final row = await db.value.teamsDao.getMatchById(seedMatchUp1Id);
      expect(row!.kind, 'past');
      expect(row.result, '2-1');
      expect(await DriftPersistedMatchStore(db.value).load(_kDeviceA), isNull);
    });

    test('summary uuid mismatch → no cross-match data in the notice, '
        'persisted match still finalized', () async {
      await persistMidMatch();
      mock.mockLastSessionSummary = const LastSessionSummary(
        matchUuid: 'a-completely-different-match',
        endReason: SessionEndReason.autoStop,
        endClockSeconds: 999,
      );
      final c2 = makeContainer();
      await c2.read(connectControllerProvider).connect(_kDeviceA);

      // Generic — the mismatching summary's reason/clock never leak in.
      expect(c2.read(sessionNoticeProvider), 'Match ended while away.');
      final row = await db.value.teamsDao.getMatchById(seedMatchUp1Id);
      expect(row!.kind, 'past');
    });

    test('camera rebooted mid-match then started match Z → stale match '
        'finalized via away-ended FIRST, then Z adopted', () async {
      await persistMidMatch(); // match X = seedMatchUp1Id
      mock.snapshotMatchState = _fwMatch(
        seedMatchUp2Id,
        scoreA: 1,
        elapsed: 60,
        clockRunning: true,
      );
      mock.mockSessionPhase = SessionPhase.recording;

      final c2 = makeContainer();
      await c2.read(connectControllerProvider).connect(_kDeviceA);

      // X settled: notice + finalized + cleared exactly once.
      expect(c2.read(sessionNoticeProvider), 'Match ended while away.');
      final rowX = await db.value.teamsDao.getMatchById(seedMatchUp1Id);
      expect(rowX!.kind, 'past');
      expect(rowX.result, '2-1');
      // X's row is gone — cleared exactly once by the away-ended path (Z may
      // or may not have persisted its own row by now, but never X's).
      final persisted = await DriftPersistedMatchStore(
        db.value,
      ).load(_kDeviceA);
      expect(persisted?.matchUuid, isNot(seedMatchUp1Id));
      // Z adopted as the live view.
      final live = c2.read(liveMatchProvider);
      expect(c2.read(liveMatchProvider.notifier).matchId, seedMatchUp2Id);
      expect(live.scoreHome, 1);
      expect(live.phase, MatchPhase.period);
      expect(mock.lastSetMatchState, isNull);
    });

    test('crash between finalize and clear → idempotent re-finalize, no '
        'notice, no double data', () async {
      // Simulate the crash window: an ENDED match still sitting in the store
      // (finalize ran, clear didn't).
      final store = DriftPersistedMatchStore(db.value);
      await db.value.teamsDao.finalizeMatch(
        seedMatchUp1Id,
        result: '2-1',
        eventsJson: '[]',
      );
      await store.save(
        _kDeviceA,
        const PersistedLiveMatch(
          matchUuid: seedMatchUp1Id,
          libraryMatchId: seedMatchUp1Id,
          scoreA: 2,
          scoreB: 1,
          phase: PersistedMatchPhase.ended,
        ),
      );

      final c = makeContainer();
      await c.read(connectControllerProvider).connect(_kDeviceA);

      // Silent settlement: same result rewritten (idempotent), row cleared.
      expect(c.read(sessionNoticeProvider), isNull);
      final row = await db.value.teamsDao.getMatchById(seedMatchUp1Id);
      expect(row!.kind, 'past');
      expect(row.result, '2-1');
      expect(await store.load(_kDeviceA), isNull);
    });
  });

  group('Wire vs local failure split', () {
    test('a local store failure does NOT make the camera unconnectable — '
        'connect succeeds, issue surfaced separately', () async {
      mock.snapshotMatchState = _fwMatch(seedMatchUp1Id, elapsed: 100);
      mock.mockSessionPhase = SessionPhase.recording;

      final c = makeContainer(
        extra: [
          persistedMatchStoreProvider.overrideWithValue(_ThrowingStore()),
        ],
      );

      CameraConnectionState? current;
      mock.connectionStateStream(_kDeviceA).listen((s) => current = s);

      // No throw:
      await c.read(connectControllerProvider).connect(_kDeviceA);

      expect(current, CameraConnectionState.connected);
      expect(c.read(connectLocalIssueProvider), contains('could not be read'));
    });

    test('store unreadable but memory still holds the running match → memory '
        'scores pushed, firmware clock adopted', () async {
      mock.snapshotMatchState = _fwMatch(
        seedMatchUp1Id,
        elapsed: 321,
        clockRunning: true,
      );
      mock.mockSessionPhase = SessionPhase.recording;
      mock.isRecordingActive = true;

      final c = makeContainer(
        extra: [
          persistedMatchStoreProvider.overrideWithValue(_ThrowingStore()),
        ],
      );
      c.read(activeCameraIdProvider.notifier).state = _kDeviceA;
      startMatch(c);
      scoreGoals(c, home: 2);

      await c.read(connectControllerProvider).connect(_kDeviceA);

      final push = mock.lastSetMatchState;
      expect(push!.scoreA, 2);
      expect(push.scoreB, 0);
      final live = c.read(liveMatchProvider);
      expect(live.scoreHome, 2);
      // >= because the U7 parity mock's clock ticks in real time.
      expect(live.elapsedSeconds, greaterThanOrEqualTo(321));
      expect(live.rec, RecState.recording);
      expect(c.read(connectLocalIssueProvider), contains('could not be read'));
    });
  });

  group('Clock — drift correction + period-end auto-fire', () {
    test(
      'elapsed derives from the wall-clock anchor, not tick counting',
      () async {
        final c = makeContainer();
        final ctl = c.read(liveMatchProvider.notifier);
        var now = DateTime(2026, 7, 6, 15, 0, 0);
        ctl.clock = () => now;
        startMatch(c);
        // 30 wall seconds pass but only ONE tick arrives (a throttled UI
        // timer): the clock must not lose the 29 missing ticks.
        now = now.add(const Duration(seconds: 30));
        ctl.tick();
        expect(c.read(liveMatchProvider).elapsedSeconds, 30);
      },
    );

    test('2 s poll corrects a drifted local clock while connected', () async {
      final c = makeContainer();
      c.read(activeCameraIdProvider.notifier).state = _kDeviceA;
      final ctl = c.read(liveMatchProvider.notifier);
      startMatch(c);
      expect(c.read(liveMatchProvider).elapsedSeconds, 0);

      // Firmware says 45 s — the local clock (0 s, drifted) follows.
      ctl.onFirmwareMatchState(
        _fwMatch(seedMatchUp1Id, elapsed: 45, clockRunning: true),
      );
      expect(c.read(liveMatchProvider).elapsedSeconds, 45);
    });

    test('poll for a DIFFERENT match uuid never touches the clock', () async {
      final c = makeContainer();
      final ctl = c.read(liveMatchProvider.notifier);
      startMatch(c);
      ctl.onFirmwareMatchState(
        _fwMatch('some-other-match', elapsed: 500, clockRunning: true),
      );
      expect(c.read(liveMatchProvider).elapsedSeconds, 0);
    });

    test('clock-running disagreement (pause command in flight) skips the '
        'sample instead of flapping', () async {
      final c = makeContainer();
      final ctl = c.read(liveMatchProvider.notifier);
      startMatch(c);
      ctl.toggleTimer(); // locally paused; fw still says running
      ctl.onFirmwareMatchState(
        _fwMatch(seedMatchUp1Id, elapsed: 500, clockRunning: true),
      );
      expect(c.read(liveMatchProvider).elapsedSeconds, 0);
      expect(c.read(liveMatchProvider).timer, MatchTimer.paused);
    });

    test(
      'adopted elapsed >= period length fires the period end exactly once',
      () async {
        final c = makeContainer();
        final ctl = c.read(liveMatchProvider.notifier);
        startMatch(c); // periodLengthSeconds 2100
        ctl.onFirmwareMatchState(
          _fwMatch(seedMatchUp1Id, elapsed: 2400, clockRunning: true),
        );
        var live = c.read(liveMatchProvider);
        expect(live.phase, MatchPhase.periodBreak);
        expect(live.elapsedSeconds, 2100);
        expect(
          live.events.where((e) => e.label == 'End period 1'),
          hasLength(1),
        );
        // A second late sample must not refire (phase left `period`).
        ctl.onFirmwareMatchState(
          _fwMatch(seedMatchUp1Id, elapsed: 2500, clockRunning: true),
        );
        live = c.read(liveMatchProvider);
        expect(live.phase, MatchPhase.periodBreak);
        expect(
          live.events.where((e) => e.label == 'End period 1'),
          hasLength(1),
        );
      },
    );

    test('restore with firmware elapsed past the period length fires the '
        'period end once on rejoin', () async {
      final c1 = makeContainer();
      c1.read(activeCameraIdProvider.notifier).state = _kDeviceA;
      startMatch(c1);
      await pumpEventQueue();
      c1.dispose();

      mock.snapshotMatchState = _fwMatch(
        seedMatchUp1Id,
        elapsed: 2200, // past the 2100 s period length
        clockRunning: true,
      );
      mock.mockSessionPhase = SessionPhase.recording;

      final c2 = makeContainer();
      await c2.read(connectControllerProvider).connect(_kDeviceA);

      final live = c2.read(liveMatchProvider);
      expect(live.phase, MatchPhase.periodBreak);
      expect(live.elapsedSeconds, 2100);
      expect(live.events.where((e) => e.label == 'End period 1'), hasLength(1));
    });

    test('the 2 s poll stream feeds the controller through '
        'liveMatchFirmwareSyncProvider', () async {
      final c = makeContainer();
      c.read(activeCameraIdProvider.notifier).state = _kDeviceA;
      // Keep the sync provider alive the way MatchPage's watch does.
      c.listen<void>(liveMatchFirmwareSyncProvider, (_, _) {});
      c.read(liveMatchFirmwareSyncProvider);
      startMatch(c);
      await pumpEventQueue();

      mock.emitMatchState(
        _kDeviceA,
        _fwMatch(seedMatchUp1Id, elapsed: 77, clockRunning: true),
      );
      await pumpEventQueue();

      expect(c.read(liveMatchProvider).elapsedSeconds, 77);
    });
  });

  group('Poll truth — uncommanded transitions', () {
    test('observed recording→idle without a command → controller follows '
        'firmware, shows the notice, never throws', () async {
      final c = makeContainer();
      final ctl = c.read(liveMatchProvider.notifier);
      startMatch(c); // rec: recording
      expect(c.read(liveMatchProvider).rec, RecState.recording);

      ctl.onFirmwareTelemetry(_telemetry(isRecording: true)); // observed on
      ctl.onFirmwareTelemetry(_telemetry(isRecording: false)); // uncommanded

      expect(c.read(liveMatchProvider).rec, RecState.idle);
      expect(c.read(sessionNoticeProvider), 'Recording stopped on the camera.');
    });

    test('a start-lag false (never observed recording) is NOT an uncommanded '
        'stop', () async {
      final c = makeContainer();
      final ctl = c.read(liveMatchProvider.notifier);
      startMatch(c);
      // The firmware hasn't flipped yet right after the start command.
      ctl.onFirmwareTelemetry(_telemetry(isRecording: false));
      expect(c.read(liveMatchProvider).rec, RecState.recording);
      expect(c.read(sessionNoticeProvider), isNull);
    });

    test('an app-side pause is never treated as an uncommanded stop', () async {
      final c = makeContainer();
      final ctl = c.read(liveMatchProvider.notifier);
      startMatch(c);
      ctl.onFirmwareTelemetry(_telemetry(isRecording: true));
      ctl.toggleRecPause(); // → paused (user intent)
      ctl.onFirmwareTelemetry(_telemetry(isRecording: false));
      expect(c.read(liveMatchProvider).rec, RecState.paused);
      expect(c.read(sessionNoticeProvider), isNull);
    });
  });

  group('Integration — disconnect, local scores unsent, rejoin', () {
    test('app scores win via SetMatchState, firmware clock wins', () async {
      // Connect for real so the whole path runs through the controller.
      final c = makeContainer();
      await c.read(connectControllerProvider).connect(_kDeviceA);
      startMatch(c);
      await pumpEventQueue();

      // Unexpected drop; the user keeps scoring while disconnected.
      await mock.disconnect(_kDeviceA);
      scoreGoals(c, home: 1);
      await pumpEventQueue();

      // Firmware ran on: clock advanced, scores still 0–0 (deltas unsent).
      mock.snapshotMatchState = _fwMatch(
        seedMatchUp1Id,
        elapsed: 600,
        clockRunning: true,
      );
      mock.mockSessionPhase = SessionPhase.recording;
      mock.isRecordingActive = true;

      await c.read(connectControllerProvider).connect(_kDeviceA);

      final live = c.read(liveMatchProvider);
      expect(live.scoreHome, 1); // app score kept
      // Firmware clock adopted (>= because the U7 mock clock keeps ticking).
      expect(live.elapsedSeconds, greaterThanOrEqualTo(600));
      expect(live.phase, MatchPhase.period);
      final push = mock.lastSetMatchState;
      expect(push!.scoreA, 1);
      expect(push.scoreB, 0);
      expect(push.elapsedSeconds, isNull);
      // Overlay divergence during the gap is accepted, not an error: the
      // handshake completed clean.
      expect(c.read(connectLocalIssueProvider), isNull);
      expect(c.read(sessionNoticeProvider), isNull);
    });
  });

  group('Normal end — single finalize path', () {
    test(
      'finalizeToLibrary flips the row to past and clears the store last',
      () async {
        final c = makeContainer();
        c.read(activeCameraIdProvider.notifier).state = _kDeviceA;
        final ctl = c.read(liveMatchProvider.notifier);
        startMatch(c);
        scoreGoals(c, home: 3, away: 2);
        ctl.endPeriod();
        ctl.startPeriod();
        ctl.endPeriod();
        ctl.endMatch();
        await pumpEventQueue();

        await ctl.finalizeToLibrary();

        final row = await db.value.teamsDao.getMatchById(seedMatchUp1Id);
        expect(row!.kind, 'past');
        expect(row.result, '3-2');
        expect(
          await DriftPersistedMatchStore(db.value).load(_kDeviceA),
          isNull,
        );
      },
    );
  });
}
