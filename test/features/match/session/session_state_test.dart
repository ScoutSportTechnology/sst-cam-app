import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sst_cam_app/core/ble/ble_providers.dart';
import 'package:sst_cam_app/core/models/command.dart';
import 'package:sst_cam_app/core/models/device.dart';
import 'package:sst_cam_app/core/models/overlay_layout.dart';
import 'package:sst_cam_app/core/models/telemetry.dart';
import 'package:sst_cam_app/core/state/connect_controller.dart'
    show sessionSnapshotProvider;
import 'package:sst_cam_app/features/camera/camera_state.dart'
    show activeCameraIdProvider;
import 'package:sst_cam_app/mock/emulator/mock_ble_service.dart';
import 'package:sst_cam_app/core/models/session_snapshot.dart';
import 'package:sst_cam_app/features/match/session/session_state.dart';
import 'package:sst_cam_app/features/match/session/session_actions.dart';

ProviderContainer _makeContainer() => ProviderContainer();

// Match ids are UUIDs (not magic strings); loadFromUpcoming requires one.
const _matchId = '11111111-1111-4111-8111-111111111111';

const _minimalLayout = OverlayLayout(
  canvasWidth: 1920,
  canvasHeight: 1080,
  elements: [],
  templates: [],
);

class _RefusingStopBle extends MockBleService {
  _RefusingStopBle() : super(advertiseDevices: false, failureRate: 0);

  final commands = <BleCommand>[];
  bool rejectStop = true;
  bool throwOnStop = false;

  @override
  Future<BleCommandResponse<T>> sendCommand<T>(
    String deviceId,
    BleCommand command,
  ) {
    commands.add(command);
    if (command is RecordingControlCommand &&
        command.action == RecordingControlAction.stop) {
      if (throwOnStop) return Future.error(StateError('link lost'));
      if (rejectStop) {
        return Future.value(BleCommandResponse.error('stop refused'));
      }
    }
    return super.sendCommand<T>(deviceId, command);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final (connected, throws) in [
    (true, false),
    (true, true),
    (false, false),
  ]) {
    testWidgets(
      'failed recording stop keeps match live (connected: $connected, throws: $throws)',
      (tester) async {
        final ble = _RefusingStopBle()..throwOnStop = throws;
        addTearDown(ble.dispose);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              bleServiceProvider.overrideWithValue(ble),
              activeCameraIdProvider.overrideWith((_) => 'dev-1'),
              connectionStateProvider('dev-1').overrideWith(
                (_) => Stream.value(
                  connected
                      ? CameraConnectionState.connected
                      : CameraConnectionState.disconnected,
                ),
              ),
            ],
            child: MaterialApp(
              theme: ThemeData(splashFactory: NoSplash.splashFactory),
              home: Scaffold(
                body: Consumer(
                  builder: (context, ref, _) {
                    final state = ref.watch(liveMatchProvider);
                    return TextButton(
                      onPressed: () => confirmSessionEnd(
                        context,
                        ref,
                        ref.read(liveMatchProvider.notifier),
                        state,
                      ),
                      child: const Text('End'),
                    );
                  },
                ),
              ),
            ),
          ),
        );
        final container = ProviderScope.containerOf(
          tester.element(find.byType(Consumer)),
        );
        final ctl = container.read(liveMatchProvider.notifier);
        ctl.startPeriod(startRecording: true);
        await tester.pump();
        await tester.tap(find.text('End'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('End match').last);
        await tester.pumpAndSettle();

        expect(container.read(liveMatchProvider).phase, MatchPhase.period);
        expect(container.read(liveMatchProvider).rec, RecState.recording);
        expect(container.read(recordingSavingProvider), isFalse);
        expect(
          ble.commands.whereType<MatchControlCommand>().where(
            (c) => c.action == BleMatchControlAction.finalWhistle,
          ),
          isEmpty,
        );
        expect(find.textContaining('Could not stop recording'), findsOneWidget);
      },
    );
  }

  test(
    'stop saves only after telemetry clears and snapshot confirms file',
    () async {
      final mock = MockBleService(advertiseDevices: false, failureRate: 0);
      mock.finalizeDuration = const Duration(milliseconds: 300);
      final container = ProviderContainer(
        overrides: [
          bleServiceProvider.overrideWithValue(mock),
          activeCameraIdProvider.overrideWith((_) => 'dev-1'),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(mock.dispose);
      final saving = container.listen(recordingSavingProvider, (_, _) {});
      addTearDown(saving.close);
      await mock.pushSessionConfig(
        'dev-1',
        const PushSessionConfig(
          matchUuid: _matchId,
          userUuid: 'u-1',
          sport: 'soccer',
          numPeriods: 2,
          periodLengthSeconds: 2100,
          videoOutputPath: '/videos/',
          thumbnailOutputPath: '/thumbs/',
        ),
      );
      await mock.sendCommand<void>(
        'dev-1',
        RecordingControlCommand(action: RecordingControlAction.start),
      );
      final stop = await mock.sendCommand<void>(
        'dev-1',
        RecordingControlCommand(action: RecordingControlAction.stop),
      );
      expect(stop.isOk, isTrue);
      container.read(recordingSavingProvider.notifier).state = true;
      expect(container.read(recordingSavingProvider), isTrue);
      expect(container.read(sessionNoticeProvider), isNull);
      final during = (await mock.sendCommand<DeviceTelemetry>(
        'dev-1',
        GetTelemetryCommand(),
      )).payload!;
      container.read(recordingFinalizeSyncProvider);
      mock.emitTelemetry('dev-1', during);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(container.read(recordingSavingProvider), isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final after = (await mock.sendCommand<DeviceTelemetry>(
        'dev-1',
        GetTelemetryCommand(),
      )).payload!;
      mock.emitTelemetry('dev-1', after);
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(container.read(recordingSavingProvider), isFalse);
      expect(container.read(sessionNoticeProvider), contains('saved'));
      expect(
        container.read(sessionSnapshotProvider)?.lastSession?.fileValid,
        isTrue,
      );
    },
  );

  test(
    'reconnected finalizing snapshot resumes saving until telemetry clears',
    () async {
      final mock = MockBleService(advertiseDevices: false, failureRate: 0);
      mock.finalizeDuration = const Duration(milliseconds: 250);
      await mock.pushSessionConfig(
        'dev-1',
        const PushSessionConfig(
          matchUuid: _matchId,
          userUuid: 'u-1',
          sport: 'soccer',
          numPeriods: 2,
          periodLengthSeconds: 2100,
          videoOutputPath: '/videos/',
          thumbnailOutputPath: '/thumbs/',
        ),
      );
      await mock.sendCommand<void>(
        'dev-1',
        RecordingControlCommand(action: RecordingControlAction.start),
      );
      await mock.sendCommand<void>(
        'dev-1',
        RecordingControlCommand(action: RecordingControlAction.stop),
      );
      final snapshot = (await mock.sendCommand<SessionSnapshot>(
        'dev-1',
        GetSessionSnapshotCommand(),
      )).payload!;
      final container = ProviderContainer(
        overrides: [
          bleServiceProvider.overrideWithValue(mock),
          activeCameraIdProvider.overrideWith((_) => 'dev-1'),
          sessionSnapshotProvider.overrideWith((_) => snapshot),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(mock.dispose);
      container.read(recordingFinalizeSyncProvider);
      expect(container.read(sessionSnapshotProvider)?.isFinalizing, isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 260));
      final done = (await mock.sendCommand<DeviceTelemetry>(
        'dev-1',
        GetTelemetryCommand(),
      )).payload!;
      mock.emitTelemetry('dev-1', done);
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(container.read(recordingSavingProvider), isFalse);
      expect(container.read(sessionNoticeProvider), contains('saved'));
    },
  );

  test('invalid finalized file is never reported saved', () async {
    final mock = MockBleService(advertiseDevices: false, failureRate: 0);
    final container = ProviderContainer(
      overrides: [
        bleServiceProvider.overrideWithValue(mock),
        activeCameraIdProvider.overrideWith((_) => 'dev-1'),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(mock.dispose);
    container.read(recordingSavingProvider.notifier).state = true;
    container.read(recordingFinalizeSyncProvider);
    mock.mockLastSessionSummary = const LastSessionSummary(
      matchUuid: _matchId,
      endReason: SessionEndReason.reboot,
      fileValid: false,
    );
    mock.emitTelemetry(
      'dev-1',
      const DeviceTelemetry(
        storageFreeBytes: 1,
        storageTotalBytes: 2,
        wifiState: WifiState.connected,
        internetReachable: false,
        tempCelsius: 40,
        ramUsedPct: 10,
        cpuUsedPct: 10,
        uptimeSeconds: 1,
        isRecording: false,
        isStreaming: false,
        isFinalizing: false,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(container.read(recordingSavingProvider), isFalse);
    expect(container.read(sessionNoticeProvider), contains('not saved'));
    expect(container.read(sessionNoticeProvider), contains('reboot'));
  });

  test('clean shutdown notice explains saved recording', () {
    final notice = awayEndedNoticeText(
      const LastSessionSummary(
        matchUuid: 'm-1',
        endReason: SessionEndReason.shutdown,
        fileValid: true,
      ),
    );
    expect(notice, contains('shut down'));
    expect(notice, contains('saved'));
  });

  test('shutdown without a valid file never claims a saved recording', () {
    for (final valid in <bool?>[false, null]) {
      final notice = awayEndedNoticeText(
        LastSessionSummary(
          matchUuid: 'm-1',
          endReason: SessionEndReason.shutdown,
          fileValid: valid,
        ),
      );
      expect(notice, contains('check the recording'));
      expect(notice, isNot(contains('saved')));
    }
  });

  group('LiveMatchState — new fields', () {
    late ProviderContainer container;
    late LiveMatchController ctrl;

    setUp(() {
      container = _makeContainer();
      ctrl = container.read(liveMatchProvider.notifier);
    });

    tearDown(() => container.dispose());

    // ---- loadFromUpcoming with homeColorHex --------------------------------

    test('loadFromUpcoming with homeColorHex sets state.homeColorHex', () {
      ctrl.loadFromUpcoming(
        matchId: _matchId,
        teamShortName: 'NR',
        teamName: 'Norton Rangers',
        opponent: 'vs EFC',
        numPeriods: 2,
        periodLengthSeconds: 2100,
        homeColorHex: '#FF0000',
      );
      expect(container.read(liveMatchProvider).homeColorHex, '#FF0000');
    });

    test(
      'loadFromUpcoming with homeColorHex null leaves state.homeColorHex null',
      () {
        ctrl.loadFromUpcoming(
          matchId: _matchId,
          teamShortName: 'NR',
          teamName: 'Norton Rangers',
          opponent: 'vs EFC',
          numPeriods: 2,
          periodLengthSeconds: 2100,
          homeColorHex: null,
        );
        expect(container.read(liveMatchProvider).homeColorHex, isNull);
      },
    );

    // ---- setOverlayLayout --------------------------------------------------

    test('setOverlayLayout stores the layout in state', () {
      ctrl.setOverlayLayout(_minimalLayout);
      expect(container.read(liveMatchProvider).overlayLayout, _minimalLayout);
    });

    // ---- reset clears new fields ------------------------------------------

    test('reset sets overlayLayout to null', () {
      ctrl.setOverlayLayout(_minimalLayout);
      ctrl.reset();
      expect(container.read(liveMatchProvider).overlayLayout, isNull);
    });

    test('reset sets homeColorHex to null', () {
      ctrl.loadFromUpcoming(
        matchId: _matchId,
        teamShortName: 'NR',
        teamName: 'Norton Rangers',
        opponent: 'vs EFC',
        numPeriods: 2,
        periodLengthSeconds: 2100,
        homeColorHex: '#FF0000',
      );
      ctrl.reset();
      expect(container.read(liveMatchProvider).homeColorHex, isNull);
    });

    // ---- periodLabelForOverlay ---------------------------------------------

    test('periodLabelForOverlay is P1 when phase=period currentPeriod=1', () {
      // Start from idle → start period 1
      ctrl.startPeriod();
      final s = container.read(liveMatchProvider);
      expect(s.phase, MatchPhase.period);
      expect(s.currentPeriod, 1);
      expect(s.periodLabelForOverlay, 'P1');
    });

    test(
      'periodLabelForOverlay is HT when phase=periodBreak and not last period',
      () {
        // 2-period match; advance to end of period 1 → periodBreak (not last)
        ctrl.startPeriod(); // period 1
        ctrl.endPeriod(); // → periodBreak, currentPeriod=1, numPeriods=2
        final s = container.read(liveMatchProvider);
        expect(s.phase, MatchPhase.periodBreak);
        expect(s.isLastPeriod, isFalse);
        expect(s.periodLabelForOverlay, 'HT');
      },
    );

    test('periodLabelForOverlay is FT when phase=ended', () {
      ctrl.startPeriod(); // period 1
      ctrl.endPeriod(); // periodBreak after period 1
      ctrl.startPeriod(); // period 2
      ctrl.endPeriod(); // periodBreak, isLastPeriod=true
      ctrl.endMatch(); // → ended
      final s = container.read(liveMatchProvider);
      expect(s.phase, MatchPhase.ended);
      expect(s.periodLabelForOverlay, 'FT');
    });

    test(
      'periodLabelForOverlay is FT when phase=periodBreak and isLastPeriod',
      () {
        // 2-period match; end of period 2 → periodBreak with isLastPeriod=true
        ctrl.startPeriod(); // period 1
        ctrl.endPeriod();
        ctrl.startPeriod(); // period 2
        ctrl.endPeriod(); // → periodBreak, currentPeriod=2, numPeriods=2
        final s = container.read(liveMatchProvider);
        expect(s.phase, MatchPhase.periodBreak);
        expect(s.isLastPeriod, isTrue);
        expect(s.periodLabelForOverlay, 'FT');
      },
    );

    // ---- copyWith preserves new fields when omitted -----------------------

    test('copyWith with no args preserves all three new fields', () {
      ctrl.setOverlayLayout(_minimalLayout);
      ctrl.setTeamColors('#FF0000', '#0000FF');
      final before = container.read(liveMatchProvider);

      // copyWith with an unrelated field change
      final after = before.copyWith(elapsedSeconds: 42);

      expect(after.overlayLayout, same(before.overlayLayout));
      expect(after.homeColorHex, before.homeColorHex);
      expect(after.awayColorHex, before.awayColorHex);
    });

    // ---- phaseLabel (existing) is unchanged for periodBreak non-last ------

    test('phaseLabel for periodBreak non-last period returns BRK (not HT)', () {
      ctrl.startPeriod(); // period 1
      ctrl.endPeriod(); // periodBreak, not last
      final s = container.read(liveMatchProvider);
      expect(s.phase, MatchPhase.periodBreak);
      expect(s.isLastPeriod, isFalse);
      expect(s.phaseLabel, 'BRK');
    });
  });
}
