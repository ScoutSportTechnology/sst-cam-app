// U5 — auto-stop setting (R5): app-configurable unsupervised-session
// timeout. Default 30 min, persisted via shared_preferences, bounds
// enforced (5..240), and — the interesting part — changed mid-session it
// re-pushes the session config immediately so the firmware picks the new
// timeout up now, not at the next session.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sst_cam_app/core/ble/ble_providers.dart';
import 'package:sst_cam_app/core/models/command.dart';
import 'package:sst_cam_app/core/models/device.dart';
import 'package:sst_cam_app/core/state/auto_stop.dart';
import 'package:sst_cam_app/features/camera/camera_state.dart'
    show activeCameraIdProvider;
import 'package:sst_cam_app/features/settings/settings_page.dart';
import 'package:sst_cam_app/features/video/video_state.dart'
    show liveSessionActiveProvider;
import 'package:sst_cam_app/mock/emulator/mock_ble_service.dart';

import '../../test_helpers.dart';

const _deviceId = 'SST-CAM-001';

MockBleService _newMock() => MockBleService(
  scanDeviceAppearDelays: const [Duration.zero],
  connectionDelay: Duration.zero,
  failureRate: 0.0,
  randomSeed: 1,
);

PushSessionConfig _config({int autoStopMinutes = kDefaultAutoStopMinutes}) =>
    PushSessionConfig(
      matchUuid: '11111111-1111-4111-8111-111111111111',
      userUuid: 'user-1',
      sport: 'soccer',
      numPeriods: 2,
      periodLengthSeconds: 2100,
      videoOutputPath: '/var/lib/sst/cam/videos/user-1/m/',
      thumbnailOutputPath: '/var/lib/sst/cam/thumbnails/user-1/m/',
      autoStopMinutes: autoStopMinutes,
    );

/// Container wired for the mid-session re-push path: mock BLE, connected
/// camera, live session, and a previously-pushed session config.
ProviderContainer _liveSessionContainer(
  MockBleService mock, {
  bool connected = true,
  bool sessionLive = true,
}) {
  final container = ProviderContainer(
    overrides: [
      bleServiceProvider.overrideWithValue(mock),
      activeCameraIdProvider.overrideWith((_) => _deviceId),
      connectionStateProvider(_deviceId).overrideWith(
        (_) => Stream<CameraConnectionState>.value(
          connected
              ? CameraConnectionState.connected
              : CameraConnectionState.disconnected,
        ),
      ),
      liveSessionActiveProvider.overrideWith((_) => sessionLive),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('AutoStopMinutesNotifier — persistence + bounds', () {
    test('defaults to 30 when the user never touched the setting', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(
        await container.read(autoStopMinutesProvider.future),
        kDefaultAutoStopMinutes,
      );
    });

    test('set(90) persists and survives a restart (fresh container)', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(autoStopMinutesProvider.future);
      await container.read(autoStopMinutesProvider.notifier).set(90);
      expect(container.read(autoStopMinutesProvider).value, 90);

      // "Restart": a brand-new container re-reads the same prefs store.
      final restarted = ProviderContainer();
      addTearDown(restarted.dispose);
      expect(await restarted.read(autoStopMinutesProvider.future), 90);
    });

    test('bounds enforced on write: no 0/negative, capped at 240', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(autoStopMinutesProvider.notifier);
      await container.read(autoStopMinutesProvider.future);

      await notifier.set(0);
      expect(
        container.read(autoStopMinutesProvider).value,
        kAutoStopMinMinutes,
      );
      await notifier.set(-10);
      expect(
        container.read(autoStopMinutesProvider).value,
        kAutoStopMinMinutes,
      );
      await notifier.set(100000);
      expect(
        container.read(autoStopMinutesProvider).value,
        kAutoStopMaxMinutes,
      );
    });

    test('out-of-range persisted value is clamped on read', () async {
      SharedPreferences.setMockInitialValues({'auto_stop_minutes': 1});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(
        await container.read(autoStopMinutesProvider.future),
        kAutoStopMinMinutes,
      );
    });
  });

  group('mid-session change — immediate re-push', () {
    test('connected + live session + pushed config → one extra '
        'PushSessionConfig carrying the new value', () async {
      final mock = _newMock();
      addTearDown(mock.dispose);
      final container = _liveSessionContainer(mock);
      // Let the connection-state stream emit before the notifier reads it.
      await container.read(connectionStateProvider(_deviceId).future);
      container.read(lastPushedSessionConfigProvider.notifier).state =
          _config();
      await container.read(autoStopMinutesProvider.future);

      await container.read(autoStopMinutesProvider.notifier).set(45);

      expect(mock.pushedConfigs, hasLength(1));
      expect(mock.pushedConfigs.single.autoStopMinutes, 45);
      // The rest of the config is untouched — same session, new timeout.
      expect(mock.pushedConfigs.single.matchUuid, _config().matchUuid);
      // The remembered config now carries the new value too, so a second
      // change re-pushes from the latest shape.
      expect(
        container.read(lastPushedSessionConfigProvider)!.autoStopMinutes,
        45,
      );
    });

    test('no live session → setting persists but nothing is pushed', () async {
      final mock = _newMock();
      addTearDown(mock.dispose);
      final container = _liveSessionContainer(mock, sessionLive: false);
      await container.read(connectionStateProvider(_deviceId).future);
      container.read(lastPushedSessionConfigProvider.notifier).state =
          _config();
      await container.read(autoStopMinutesProvider.future);

      await container.read(autoStopMinutesProvider.notifier).set(45);

      expect(mock.pushedConfigs, isEmpty);
      expect(container.read(autoStopMinutesProvider).value, 45);
    });

    test('disconnected → setting persists but nothing is pushed', () async {
      final mock = _newMock();
      addTearDown(mock.dispose);
      final container = _liveSessionContainer(mock, connected: false);
      await container.read(connectionStateProvider(_deviceId).future);
      container.read(lastPushedSessionConfigProvider.notifier).state =
          _config();
      await container.read(autoStopMinutesProvider.future);

      await container.read(autoStopMinutesProvider.notifier).set(45);

      expect(mock.pushedConfigs, isEmpty);
      expect(container.read(autoStopMinutesProvider).value, 45);
    });

    test('no session config ever pushed → nothing to re-push', () async {
      final mock = _newMock();
      addTearDown(mock.dispose);
      final container = _liveSessionContainer(mock);
      await container.read(connectionStateProvider(_deviceId).future);
      await container.read(autoStopMinutesProvider.future);

      await container.read(autoStopMinutesProvider.notifier).set(45);

      expect(mock.pushedConfigs, isEmpty);
    });

    test('re-push failure keeps the persisted setting (best-effort)', () async {
      final mock = _newMock();
      addTearDown(mock.dispose);
      mock.failNextPushSessionConfig = true;
      final container = _liveSessionContainer(mock);
      await container.read(connectionStateProvider(_deviceId).future);
      container.read(lastPushedSessionConfigProvider.notifier).state =
          _config();
      await container.read(autoStopMinutesProvider.future);

      await container.read(autoStopMinutesProvider.notifier).set(45);

      expect(mock.pushedConfigs, isEmpty);
      expect(container.read(autoStopMinutesProvider).value, 45);
      // The remembered config keeps the old timeout — nothing reached the
      // camera, and the next session config carries the setting anyway.
      expect(
        container.read(lastPushedSessionConfigProvider)!.autoStopMinutes,
        kDefaultAutoStopMinutes,
      );
    });
  });

  group('Settings page — Auto-stop row', () {
    final db = useInMemoryDb();

    Widget harness(MockBleService mock) => ProviderScope(
      overrides: [
        ...dbOverrides(db),
        bleServiceProvider.overrideWithValue(mock),
      ],
      child: const MaterialApp(home: SettingsPage()),
    );

    testWidgets('shows the persisted value; picking a new one persists it', (
      tester,
    ) async {
      final mock = _newMock();
      addTearDown(mock.dispose);
      await tester.pumpWidget(harness(mock));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(find.text('Auto-stop'), 200);
      // Untouched setting renders the default.
      expect(find.text('30 min'), findsOneWidget);

      await tester.tap(find.text('30 min'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('90 min').last);
      await tester.pumpAndSettle();

      expect(find.text('90 min'), findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('auto_stop_minutes'), 90);
    });
  });
}
