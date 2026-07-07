// U1 — universal connect handshake (ConnectController).
//
// Proves the §9b connect sequence against the parity mock: protocol gate →
// time push → snapshot read → rehydrate (adopt, never force-reset) →
// reconcile (SetMatchState push / adopt) → connected, with typed failures
// that drop the link and leave no half-hydrated state.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sst_cam_app/core/ble/ble_providers.dart';
import 'package:sst_cam_app/core/ble/ble_service.dart';
import 'package:sst_cam_app/core/models/command.dart';
import 'package:sst_cam_app/core/models/device.dart';
import 'package:sst_cam_app/core/models/match.dart';
import 'package:sst_cam_app/core/models/preview_layout.dart';
import 'package:sst_cam_app/core/models/session_snapshot.dart';
import 'package:sst_cam_app/core/state/connect_controller.dart';
import 'package:sst_cam_app/core/state/last_camera.dart';
import 'package:sst_cam_app/core/state/persisted_match_store.dart';
import 'package:sst_cam_app/core/wifi/wifi_providers.dart'
    show previewLayoutProvider;
import 'package:sst_cam_app/features/camera/camera_state.dart'
    show activeCameraIdProvider, activeOutputCameraProvider;
import 'package:sst_cam_app/mock/emulator/mock_ble_service.dart';

const _kDeviceId = 'SST-CAM-001';

/// Store seam fake — the Drift-backed default is exercised in
/// test/features/match/session/session_persistence_test.dart; these reconcile
/// tests use a canned record.
class _FakeMatchStore implements PersistedMatchStore {
  _FakeMatchStore(this.record);
  final PersistedLiveMatch? record;
  final List<PersistedLiveMatch> saved = [];
  final List<(String, String)> cleared = [];

  @override
  Future<PersistedLiveMatch?> load(String deviceId) async => record;

  @override
  Future<void> save(String deviceId, PersistedLiveMatch match) async {
    saved.add(match);
  }

  @override
  Future<void> clear(String deviceId, String matchUuid) async {
    cleared.add((deviceId, matchUuid));
  }
}

MatchState _runningMatch(String uuid) => MatchState(
  status: MatchStatus.active,
  currentPeriod: 1,
  timeRemainingSeconds: 900,
  scoreA: 1,
  scoreB: 0,
  teamAId: 'team-a',
  teamBId: 'team-b',
  updatedAt: DateTime.now(),
  elapsedSeconds: 1200,
  clockRunning: true,
  matchUuid: uuid,
);

void main() {
  setUpAll(TestWidgetsFlutterBinding.ensureInitialized);

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

  ProviderContainer makeContainer({PersistedMatchStore? store}) {
    final container = ProviderContainer(
      overrides: [
        bleServiceProvider.overrideWithValue(mock),
        // The production default is the Drift-backed store; these tests pin
        // a fake (or the no-op store) so no database is in the loop.
        persistedMatchStoreProvider.overrideWithValue(
          store ?? const NoPersistedMatchStore(),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('Rehydrate — adopt from snapshot, never force-reset', () {
    test('connect to idle firmware adopts the snapshot selections (firmware '
        'actuals win over stale app-side selections)', () async {
      // Firmware actual state: camera 1, side-by-side (a session-scoped
      // selection that survived an app kill on the firmware side).
      mock.lastActiveCamera = 1;
      mock.lastPreviewLayout = PreviewLayout.sideBySide;

      final container = makeContainer();
      // Stale app-side selections from before the app was killed.
      container.read(activeOutputCameraProvider.notifier).state = 0;
      container.read(previewLayoutProvider(_kDeviceId).notifier).state =
          PreviewLayout.single;

      await container.read(connectControllerProvider).connect(_kDeviceId);

      // Adopted — NOT hardcoded defaults, NOT the stale app values.
      expect(container.read(activeOutputCameraProvider), 1);
      expect(
        container.read(previewLayoutProvider(_kDeviceId)),
        PreviewLayout.sideBySide,
      );
      final snapshot = container.read(sessionSnapshotProvider);
      expect(snapshot, isNotNull);
      expect(snapshot!.sessionPhase, SessionPhase.idle);
      expect(snapshot.isRecording, isFalse);
      // Success side effects shared by every call site.
      expect(container.read(activeCameraIdProvider), _kDeviceId);
      expect(
        await container.read(lastConnectedDeviceIdProvider.future),
        _kDeviceId,
      );
    });

    test('connect to recording firmware exposes the running session', () async {
      mock.isRecordingActive = true;
      mock.isStreamingActive = true;
      mock.snapshotRecordingElapsedSeconds = 754;
      mock.snapshotMatchState = _runningMatch('match-live');

      final container = makeContainer();
      await container.read(connectControllerProvider).connect(_kDeviceId);

      final snapshot = container.read(sessionSnapshotProvider)!;
      expect(snapshot.sessionPhase, SessionPhase.recording);
      expect(snapshot.isRecording, isTrue);
      expect(snapshot.isStreaming, isTrue);
      expect(snapshot.recordingElapsedSeconds, 754);
      // Firmware clock adopted — the only clock that ran. The parity mock's
      // clock TICKS in real time (U7), so the adopted value is at least the
      // injected base.
      expect(snapshot.matchState!.elapsedSeconds, greaterThanOrEqualTo(1200));
      expect(snapshot.matchState!.clockRunning, isTrue);
      expect(snapshot.matchState!.matchUuid, 'match-live');
    });
  });

  group(
    'Reconcile — app scores are authority, firmware clock is authority',
    () {
      test('persisted match matching the running match_uuid pushes an absolute '
          'SetMatchState with app scores and NO clock fields', () async {
        mock.snapshotMatchState = _runningMatch('match-1');
        mock.mockSessionPhase = SessionPhase.recording;
        final container = makeContainer(
          store: _FakeMatchStore(
            const PersistedLiveMatch(
              matchUuid: 'match-1',
              scoreA: 2,
              scoreB: 1,
              phase: PersistedMatchPhase.period,
              currentPeriod: 1,
            ),
          ),
        );

        await container.read(connectControllerProvider).connect(_kDeviceId);

        final push = mock.lastSetMatchState;
        expect(push, isNotNull);
        expect(push!.scoreA, 2);
        expect(push.scoreB, 1);
        // The firmware clock is never overwritten on reconnect.
        expect(push.elapsedSeconds, isNull);
        expect(push.clockRunning, isNull);
      });

      test(
        'unknown running match_uuid adopts the firmware view — no push',
        () async {
          mock.snapshotMatchState = _runningMatch('match-unknown');
          mock.mockSessionPhase = SessionPhase.recording;
          final container = makeContainer(
            store: _FakeMatchStore(
              // Pre-kickoff persisted row for another match — settled by a
              // silent clear, never restored against this session.
              const PersistedLiveMatch(
                matchUuid: 'other-match',
                scoreA: 5,
                scoreB: 5,
              ),
            ),
          );

          CameraConnectionState? current;
          mock.connectionStateStream(_kDeviceId).listen((s) => current = s);

          await container.read(connectControllerProvider).connect(_kDeviceId);

          expect(mock.lastSetMatchState, isNull);
          // The firmware-derived view is exposed for the U2 restore path.
          expect(
            container.read(sessionSnapshotProvider)!.matchState!.matchUuid,
            'match-unknown',
          );
          expect(current, CameraConnectionState.connected);
        },
      );

      test(
        'nothing persisted (U1 no-op store default) adopts silently',
        () async {
          mock.snapshotMatchState = _runningMatch('match-1');
          final container = makeContainer(); // default NoPersistedMatchStore

          await container.read(connectControllerProvider).connect(_kDeviceId);

          expect(mock.lastSetMatchState, isNull);
          expect(container.read(sessionSnapshotProvider), isNotNull);
        },
      );
    },
  );

  group('Handshake order + reconciling lockout', () {
    test('sequence is time push → snapshot → (reconcile) → connected; '
        'nothing else reaches the firmware mid-handshake', () async {
      mock.snapshotMatchState = _runningMatch('match-1');
      mock.mockSessionPhase = SessionPhase.recording;
      final container = makeContainer(
        store: _FakeMatchStore(
          const PersistedLiveMatch(
            matchUuid: 'match-1',
            scoreA: 3,
            scoreB: 2,
            phase: PersistedMatchPhase.period,
            currentPeriod: 1,
          ),
        ),
      );

      final states = <CameraConnectionState>[];
      mock.connectionStateStream(_kDeviceId).listen(states.add);

      await container.read(connectControllerProvider).connect(_kDeviceId);

      // Wire order: SetDeviceTime strictly before GetSessionSnapshot, which
      // is strictly before the reconcile push. (GetDeviceInfo rides the
      // mock's direct getDeviceInfo override, not sendCommand.)
      final types = mock.receivedCommands.map((c) => c.runtimeType).toList();
      expect(types, [
        SetDeviceTimeCommand,
        GetSessionSnapshotCommand,
        SetMatchStateCommand,
      ]);
      // Nothing session-affecting and no poller command was sent early.
      expect(types, isNot(contains(RecordingControlCommand)));
      expect(types, isNot(contains(GetTelemetryCommand)));
      expect(types, isNot(contains(GetMatchStateCommand)));

      // The UI gating state: reconciling strictly before connected, so every
      // surface gating on `connected` stayed locked through the handshake.
      expect(
        states,
        containsAllInOrder([
          CameraConnectionState.connecting,
          CameraConnectionState.reconciling,
          CameraConnectionState.connected,
        ]),
      );

      // The time push carried the phone wall clock.
      final pushed = mock.lastSetDeviceTimeEpochMs;
      expect(pushed, isNotNull);
      expect(
        (DateTime.now().millisecondsSinceEpoch - pushed!).abs(),
        lessThan(60 * 1000),
      );
    });

    test('command issued while reconciling is not usable: state != connected '
        'until reconcile completes', () async {
      final container = makeContainer();

      CameraConnectionState? current;
      mock.connectionStateStream(_kDeviceId).listen((s) => current = s);

      final connecting = container
          .read(connectControllerProvider)
          .connect(_kDeviceId);

      // Let the link come up (mock connect resolves at `reconciling`) but the
      // handshake commands (80 ms each) still be in flight.
      await Future.delayed(const Duration(milliseconds: 40));
      expect(current, CameraConnectionState.reconciling);
      // This is the gate every session-affecting surface keys off — a Record
      // tap here is disabled because the state is not `connected`.
      expect(current, isNot(CameraConnectionState.connected));

      await connecting;
      expect(current, CameraConnectionState.connected);
    });

    test('match-state / telemetry pollers emit only after connected', () async {
      final container = makeContainer();

      CameraConnectionState? current;
      mock.connectionStateStream(_kDeviceId).listen((s) => current = s);

      final statesAtTelemetry = <CameraConnectionState?>[];
      final statesAtMatch = <CameraConnectionState?>[];
      mock
          .telemetryStream(_kDeviceId)
          .listen((_) => statesAtTelemetry.add(current));
      mock
          .matchStateStream(_kDeviceId)
          .listen((_) => statesAtMatch.add(current));

      await container.read(connectControllerProvider).connect(_kDeviceId);
      // One mock telemetry tick (1 s cadence, started by completeHandshake).
      await Future.delayed(const Duration(milliseconds: 1200));

      expect(statesAtTelemetry, isNotEmpty);
      expect(
        statesAtTelemetry,
        everyElement(CameraConnectionState.connected),
        reason:
            'a poll landing mid-handshake would mutate live state before '
            'the snapshot restore reads it',
      );
      // No match-state emission ever happened while not connected.
      expect(statesAtMatch, everyElement(CameraConnectionState.connected));
    });

    test(
      'concurrent connect calls dedup to a single in-flight handshake',
      () async {
        final container = makeContainer();
        final controller = container.read(connectControllerProvider);

        await Future.wait([
          controller.connect(_kDeviceId),
          controller.connect(_kDeviceId),
        ]);

        expect(
          mock.receivedCommands.whereType<SetDeviceTimeCommand>().length,
          1,
          reason: 'a double tap must never run two handshakes at once',
        );
      },
    );
  });

  group('Typed failures — link dropped, no half-hydrated state', () {
    test('snapshot timeout → BleHandshakeException, disconnected, no partial '
        'hydration', () async {
      mock.failNextSessionSnapshot = true;
      // Firmware state that would have been adopted had the snapshot arrived.
      mock.lastActiveCamera = 1;
      mock.lastPreviewLayout = PreviewLayout.sideBySide;

      final container = makeContainer();

      CameraConnectionState? current;
      mock.connectionStateStream(_kDeviceId).listen((s) => current = s);

      await expectLater(
        container.read(connectControllerProvider).connect(_kDeviceId),
        throwsA(isA<BleHandshakeException>()),
      );

      // Link dropped; nothing was hydrated or marked active.
      expect(current, CameraConnectionState.disconnected);
      expect(container.read(sessionSnapshotProvider), isNull);
      expect(container.read(activeOutputCameraProvider), 0);
      expect(
        container.read(previewLayoutProvider(_kDeviceId)),
        PreviewLayout.single,
      );
      expect(container.read(activeCameraIdProvider), isNull);
      expect(
        await container.read(lastConnectedDeviceIdProvider.future),
        isNull,
      );
    });

    test('protocol version mismatch → BleProtocolVersionException BEFORE any '
        'time push or snapshot read', () async {
      mock.mockProtocolVersion = kAppProtocolVersion + 1;
      final container = makeContainer();

      CameraConnectionState? current;
      mock.connectionStateStream(_kDeviceId).listen((s) => current = s);

      await expectLater(
        container.read(connectControllerProvider).connect(_kDeviceId),
        throwsA(isA<BleProtocolVersionException>()),
      );

      expect(mock.lastSetDeviceTimeEpochMs, isNull);
      expect(mock.receivedCommands.whereType<SetDeviceTimeCommand>(), isEmpty);
      expect(
        mock.receivedCommands.whereType<GetSessionSnapshotCommand>(),
        isEmpty,
      );
      expect(current, CameraConnectionState.disconnected);
    });

    test('link failure propagates as BleConnectionException and never runs '
        'the handshake', () async {
      final failing = MockBleService(
        scanDeviceAppearDelays: const [Duration.zero, Duration.zero],
        connectionDelay: Duration.zero,
        failureRate: 1.0, // connect always throws
        randomSeed: 7,
      );
      addTearDown(failing.dispose);
      final container = ProviderContainer(
        overrides: [bleServiceProvider.overrideWithValue(failing)],
      );
      addTearDown(container.dispose);

      await expectLater(
        container.read(connectControllerProvider).connect(_kDeviceId),
        throwsA(isA<BleConnectionException>()),
      );
      expect(failing.receivedCommands, isEmpty);
      expect(container.read(activeCameraIdProvider), isNull);
    });
  });

  group('Both former call sites — one shared implementation', () {
    test(
      'the controller owns every success side effect the pages used to '
      'duplicate (active id, last-connected persistence, selection sync)',
      () async {
        // What discovery_page._attemptConnect and the settings banner each did
        // by hand pre-U1 now happens exactly once inside the controller — both
        // call sites shrink to `connect(deviceId)` and cannot diverge.
        final container = makeContainer();

        CameraConnectionState? current;
        mock.connectionStateStream(_kDeviceId).listen((s) => current = s);

        await container.read(connectControllerProvider).connect(_kDeviceId);

        expect(container.read(activeCameraIdProvider), _kDeviceId);
        expect(
          await container.read(lastConnectedDeviceIdProvider.future),
          _kDeviceId,
        );
        expect(container.read(sessionSnapshotProvider), isNotNull);
        expect(current, CameraConnectionState.connected);
      },
    );
  });
}
