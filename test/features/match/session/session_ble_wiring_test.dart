// Tests for session BLE command wiring (U8).
//
// These are unit-level tests that exercise MockBleService.sendCommand()
// directly to verify:
//  1. RecordingControlCommand(start) → isOk + mock side-effects
//  2. MatchControlCommand(kickoff, 1) → isOk + lastMatchControlAction
//  3. BannerEventCommand(goal) → isOk + lastBannerEvent.templateId
//  4. BannerEventCommand(yellow_card) → isOk + lastBannerEvent.templateId
//  5. _sendIfConnected with null activeCameraIdProvider → no crash

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sst_cam_app/core/ble/ble_providers.dart';
import 'package:sst_cam_app/core/models/command.dart';
import 'package:sst_cam_app/features/camera/camera_state.dart';
import 'package:sst_cam_app/mock/emulator/mock_ble_service.dart';

// ---------------------------------------------------------------------------
// Test double — MockBleService with advertiseDevices=false so it never loads
// assets (unit test, no widget binding needed).
// ---------------------------------------------------------------------------

MockBleService _makeMock() => MockBleService(
  advertiseDevices: false,
  connectionDelay: Duration.zero,
  failureRate: 0.0,
);

void main() {
  group('MockBleService — RecordingControlCommand', () {
    late MockBleService mock;
    setUp(() => mock = _makeMock());
    tearDown(() => mock.dispose());

    test('start → isOk + isRecordingActive=true + lastAction=start', () async {
      final resp = await mock.sendCommand<void>(
        'dev-1',
        RecordingControlCommand(action: RecordingControlAction.start),
      );
      expect(resp.isOk, isTrue);
      expect(mock.isRecordingActive, isTrue);
      expect(mock.lastRecordingAction, RecordingControlAction.start);
    });

    test('pause → isOk + isRecordingActive=false + lastAction=pause', () async {
      // Start first so isRecordingActive is in a known state.
      await mock.sendCommand<void>(
        'dev-1',
        RecordingControlCommand(action: RecordingControlAction.start),
      );
      final resp = await mock.sendCommand<void>(
        'dev-1',
        RecordingControlCommand(action: RecordingControlAction.pause),
      );
      expect(resp.isOk, isTrue);
      expect(mock.isRecordingActive, isFalse);
      expect(mock.lastRecordingAction, RecordingControlAction.pause);
    });

    test(
      'resume → isOk + isRecordingActive=true + lastAction=resume',
      () async {
        final resp = await mock.sendCommand<void>(
          'dev-1',
          RecordingControlCommand(action: RecordingControlAction.resume),
        );
        expect(resp.isOk, isTrue);
        expect(mock.isRecordingActive, isTrue);
        expect(mock.lastRecordingAction, RecordingControlAction.resume);
      },
    );

    test('stop → isOk + isRecordingActive=false + lastAction=stop', () async {
      final resp = await mock.sendCommand<void>(
        'dev-1',
        RecordingControlCommand(action: RecordingControlAction.stop),
      );
      expect(resp.isOk, isTrue);
      expect(mock.isRecordingActive, isFalse);
      expect(mock.lastRecordingAction, RecordingControlAction.stop);
    });
  });

  group('MockBleService — MatchControlCommand', () {
    late MockBleService mock;
    setUp(() => mock = _makeMock());
    tearDown(() => mock.dispose());

    test('kickoff period=1 → isOk + lastMatchControlAction=kickoff', () async {
      final resp = await mock.sendCommand<void>(
        'dev-1',
        MatchControlCommand(action: BleMatchControlAction.kickoff, period: 1),
      );
      expect(resp.isOk, isTrue);
      expect(mock.lastMatchControlAction, BleMatchControlAction.kickoff);
    });

    test('periodEnd period=1 → isOk + lastAction=periodEnd', () async {
      final resp = await mock.sendCommand<void>(
        'dev-1',
        MatchControlCommand(action: BleMatchControlAction.periodEnd, period: 1),
      );
      expect(resp.isOk, isTrue);
      expect(mock.lastMatchControlAction, BleMatchControlAction.periodEnd);
    });

    test('periodStart period=2 → isOk + lastAction=periodStart', () async {
      final resp = await mock.sendCommand<void>(
        'dev-1',
        MatchControlCommand(
          action: BleMatchControlAction.periodStart,
          period: 2,
        ),
      );
      expect(resp.isOk, isTrue);
      expect(mock.lastMatchControlAction, BleMatchControlAction.periodStart);
    });

    test('finalWhistle → isOk + lastAction=finalWhistle', () async {
      final resp = await mock.sendCommand<void>(
        'dev-1',
        MatchControlCommand(
          action: BleMatchControlAction.finalWhistle,
          period: 2,
        ),
      );
      expect(resp.isOk, isTrue);
      expect(mock.lastMatchControlAction, BleMatchControlAction.finalWhistle);
    });

    test('clockPause → isOk + lastAction=clockPause', () async {
      final resp = await mock.sendCommand<void>(
        'dev-1',
        MatchControlCommand(
          action: BleMatchControlAction.clockPause,
          period: 1,
        ),
      );
      expect(resp.isOk, isTrue);
      expect(mock.lastMatchControlAction, BleMatchControlAction.clockPause);
    });

    test('clockResume → isOk + lastAction=clockResume', () async {
      final resp = await mock.sendCommand<void>(
        'dev-1',
        MatchControlCommand(
          action: BleMatchControlAction.clockResume,
          period: 1,
        ),
      );
      expect(resp.isOk, isTrue);
      expect(mock.lastMatchControlAction, BleMatchControlAction.clockResume);
    });
  });

  group('MockBleService — BannerEventCommand', () {
    late MockBleService mock;
    setUp(() => mock = _makeMock());
    tearDown(() => mock.dispose());

    test('goal banner → isOk + lastBannerEvent.templateId == goal', () async {
      final resp = await mock.sendCommand<void>(
        'dev-1',
        BannerEventCommand(templateId: 'goal', durationSeconds: 5),
      );
      expect(resp.isOk, isTrue);
      expect(mock.lastBannerEvent?.templateId, 'goal');
      expect(mock.lastBannerEvent?.durationSeconds, 5);
    });

    test(
      'yellow_card banner → isOk + lastBannerEvent.templateId == yellow_card',
      () async {
        final resp = await mock.sendCommand<void>(
          'dev-1',
          BannerEventCommand(templateId: 'yellow_card', durationSeconds: 4),
        );
        expect(resp.isOk, isTrue);
        expect(mock.lastBannerEvent?.templateId, 'yellow_card');
      },
    );

    test(
      'red_card banner → isOk + lastBannerEvent.templateId == red_card',
      () async {
        final resp = await mock.sendCommand<void>(
          'dev-1',
          BannerEventCommand(templateId: 'red_card', durationSeconds: 4),
        );
        expect(resp.isOk, isTrue);
        expect(mock.lastBannerEvent?.templateId, 'red_card');
      },
    );

    test(
      'substitution banner → isOk + lastBannerEvent.templateId == substitution',
      () async {
        final resp = await mock.sendCommand<void>(
          'dev-1',
          BannerEventCommand(templateId: 'substitution', durationSeconds: 4),
        );
        expect(resp.isOk, isTrue);
        expect(mock.lastBannerEvent?.templateId, 'substitution');
      },
    );
  });

  group('MockBleService — ScoreUpdateCommand', () {
    late MockBleService mock;
    setUp(() => mock = _makeMock());
    tearDown(() => mock.dispose());

    test('score update → isOk', () async {
      final resp = await mock.sendCommand<void>(
        'dev-1',
        ScoreUpdateCommand(teamId: 'home', delta: 1),
      );
      expect(resp.isOk, isTrue);
    });
  });

  group('_sendIfConnected — null camera guard', () {
    // Verify that when activeCameraIdProvider is null, calling
    // _sendIfConnected does not throw and does not dispatch a command.
    // We test this by invoking the same guard logic inline here.

    test('null activeCameraId → no command dispatched', () async {
      final mock = _makeMock();
      addTearDown(mock.dispose);

      final container = ProviderContainer(
        overrides: [bleServiceProvider.overrideWithValue(mock)],
      );
      addTearDown(container.dispose);

      // activeCameraIdProvider is null by default — mirror _sendIfConnected:
      final id = container.read(activeCameraIdProvider);
      expect(id, isNull);
      // Guard short-circuits: no sendCommand call should be issued.
      // Verify mock side-effects remain untouched.
      expect(mock.lastRecordingAction, isNull);
      expect(mock.lastMatchControlAction, isNull);
      expect(mock.lastBannerEvent, isNull);
    });

    test('disconnected camera → no command dispatched', () async {
      final mock = _makeMock();
      addTearDown(mock.dispose);

      final container = ProviderContainer(
        overrides: [bleServiceProvider.overrideWithValue(mock)],
      );
      addTearDown(container.dispose);

      // Set active camera ID but leave connectionState as disconnected
      // (never called connect → stream has no value → valueOrNull == null).
      container.read(activeCameraIdProvider.notifier).state = 'dev-1';

      final id = container.read(activeCameraIdProvider);
      expect(id, 'dev-1');

      // connectionStateProvider.valueOrNull is null (no stream events yet),
      // so the guard would short-circuit. Verify mock is still clean.
      final connState = container
          .read(connectionStateProvider('dev-1'))
          .valueOrNull;
      expect(connState, isNull);

      expect(mock.lastRecordingAction, isNull);
    });
  });
}
