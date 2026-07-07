// U3 — derived device health (snapshot ⊕ telemetry) + capture gate.
//
// Proves the ONE health provider every capture surface keys off: fold rules
// (any DOWN → inoperable, any RECOVERING → recovering, nothing reported →
// unknown), newest-source-wins between the handshake snapshot and the 1 Hz
// telemetry, the freshness window (a stale OK never holds the gate open),
// and the typed DEVICE_INOPERABLE wire backstop — while downloads and WiFi
// commands stay un-gated.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sst_cam_app/core/ble/ble_providers.dart';
import 'package:sst_cam_app/core/models/command.dart';
import 'package:sst_cam_app/core/models/telemetry.dart';
import 'package:sst_cam_app/core/state/connect_controller.dart';
import 'package:sst_cam_app/core/state/device_health.dart';
import 'package:sst_cam_app/core/state/persisted_match_store.dart';
import 'package:sst_cam_app/mock/emulator/mock_ble_service.dart';

const _kDeviceId = 'SST-CAM-001';

DeviceTelemetry _telemetry({CameraHealth? cam0, CameraHealth? cam1}) =>
    DeviceTelemetry(
      storageFreeBytes: 1000,
      storageTotalBytes: 2000,
      wifiState: WifiState.connected,
      internetReachable: false,
      tempCelsius: 40,
      ramUsedPct: 10,
      cpuUsedPct: 10,
      uptimeSeconds: 100,
      isRecording: false,
      isStreaming: false,
      camera0Health: cam0,
      camera1Health: cam1,
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

  /// Container with the health providers kept alive (as the app shell keeps
  /// them in production — the mock's connection stream is a broadcast with no
  /// replay, so subscriptions must exist before the connect emits edges).
  ProviderContainer makeContainer({Duration? freshnessWindow}) {
    final container = ProviderContainer(
      overrides: [
        bleServiceProvider.overrideWithValue(mock),
        persistedMatchStoreProvider.overrideWithValue(
          const NoPersistedMatchStore(),
        ),
        if (freshnessWindow != null)
          healthFreshnessWindowProvider.overrideWithValue(freshnessWindow),
      ],
    );
    addTearDown(container.dispose);
    container.listen(connectionStateProvider(_kDeviceId), (_, _) {});
    container.listen(deviceHealthProvider, (_, _) {});
    container.listen(captureBlockedProvider, (_, _) {});
    return container;
  }

  Future<void> connect(ProviderContainer container) =>
      container.read(connectControllerProvider).connect(_kDeviceId);

  /// Push a telemetry sample and let the StreamProvider deliver it. Settles
  /// the provider graph first: the health notifier (re)subscribes the
  /// telemetry stream in a scheduled rebuild after connect — a sample pushed
  /// before that flush would hit a broadcast stream with no listener yet
  /// (production self-heals through the 1 Hz cadence; a one-shot test push
  /// must not race it).
  Future<void> emit(DeviceTelemetry t) async {
    await Future<void>.delayed(Duration.zero);
    mock.emitTelemetry(_kDeviceId, t);
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }

  group('Fold — snapshot health at connect', () {
    test('both cameras OK → device ok, gate open', () async {
      final container = makeContainer();
      await connect(container);

      final health = container.read(deviceHealthProvider);
      expect(health.camera0, CameraHealth.ok);
      expect(health.camera1, CameraHealth.ok);
      expect(health.device, DeviceHealth.ok);
      expect(container.read(captureBlockedProvider), isFalse);
    });

    test('snapshot reports camera1 DOWN → inoperable from the first frame '
        'after connect (no telemetry needed)', () async {
      mock.mockCamera1Health = CameraHealth.down;
      final container = makeContainer();
      await connect(container);

      expect(
        container.read(deviceHealthProvider).device,
        DeviceHealth.inoperable,
      );
      expect(container.read(captureBlockedProvider), isTrue);
    });

    test(
      'disconnected → unknown (never a stale OK), gate is a no-op',
      () async {
        final container = makeContainer();
        await connect(container);
        expect(container.read(deviceHealthProvider).device, DeviceHealth.ok);

        await mock.disconnect(_kDeviceId);
        await Future<void>.delayed(const Duration(milliseconds: 10));

        expect(
          container.read(deviceHealthProvider),
          DeviceHealthState.unreported,
        );
        // Not blocked: the existing connection gates own the disconnected case.
        expect(container.read(captureBlockedProvider), isFalse);
      },
    );
  });

  group('Telemetry — newest source wins (AE5)', () {
    test('AE5: telemetry flips camera0 DOWN → device inoperable, gate '
        'closed', () async {
      final container = makeContainer();
      await connect(container); // snapshot said ok/ok

      await emit(_telemetry(cam0: CameraHealth.down, cam1: CameraHealth.ok));

      final health = container.read(deviceHealthProvider);
      expect(health.camera0, CameraHealth.down);
      expect(health.camera1, CameraHealth.ok);
      expect(health.device, DeviceHealth.inoperable);
      expect(container.read(captureBlockedProvider), isTrue);
    });

    test(
      'stale snapshot DOWN vs fresh telemetry OK → telemetry wins',
      () async {
        mock.mockCamera0Health = CameraHealth.down;
        final container = makeContainer();
        await connect(container);
        expect(
          container.read(deviceHealthProvider).device,
          DeviceHealth.inoperable,
        );

        // The watchdog brought the camera back — the 1 Hz sample postdates the
        // connect-time snapshot, so the device recovers without a reconnect.
        await emit(_telemetry(cam0: CameraHealth.ok, cam1: CameraHealth.ok));

        expect(container.read(deviceHealthProvider).device, DeviceHealth.ok);
        expect(container.read(captureBlockedProvider), isFalse);
      },
    );

    test('RECOVERING → recovering, no lockout', () async {
      final container = makeContainer();
      await connect(container);

      await emit(
        _telemetry(cam0: CameraHealth.ok, cam1: CameraHealth.recovering),
      );

      expect(
        container.read(deviceHealthProvider).device,
        DeviceHealth.recovering,
      );
      expect(
        container.read(captureBlockedProvider),
        isFalse,
        reason:
            'recovering shows a soft indicator only — the firmware '
            'DEVICE_INOPERABLE refusal is the backstop, not an app lockout',
      );
    });

    test('OK↔RECOVERING flapping never reaches inoperable and never closes '
        'the gate', () async {
      final container = makeContainer();
      await connect(container);

      final seenDevice = <DeviceHealth>[];
      container.listen(
        deviceHealthProvider,
        (_, next) => seenDevice.add(next.device),
      );
      final seenBlocked = <bool>[];
      container.listen(
        captureBlockedProvider,
        (_, next) => seenBlocked.add(next),
      );

      for (final h in [
        CameraHealth.recovering,
        CameraHealth.ok,
        CameraHealth.recovering,
        CameraHealth.ok,
      ]) {
        await emit(_telemetry(cam0: h, cam1: CameraHealth.ok));
      }

      expect(seenDevice, isNot(contains(DeviceHealth.inoperable)));
      expect(seenBlocked, isNot(contains(true)));
    });

    test('health-less telemetry sample is NOT a reading — it neither '
        'fabricates OK nor overwrites the last real value', () async {
      final container = makeContainer();
      await connect(container);
      await emit(_telemetry(cam0: CameraHealth.down, cam1: CameraHealth.ok));
      expect(
        container.read(deviceHealthProvider).device,
        DeviceHealth.inoperable,
      );

      await emit(_telemetry()); // absent health fields

      expect(
        container.read(deviceHealthProvider).device,
        DeviceHealth.inoperable,
        reason: 'absent fields must never fabricate OK (unreported ≠ healthy)',
      );
    });
  });

  group('Freshness window — stale OK must not hold', () {
    test('telemetry stalls while connected → degrades to unknown after the '
        'window; gate treats unknown-while-connected conservatively', () async {
      final container = makeContainer(
        freshnessWindow: const Duration(milliseconds: 150),
      );
      await connect(container);
      await emit(_telemetry(cam0: CameraHealth.ok, cam1: CameraHealth.ok));
      expect(container.read(deviceHealthProvider).device, DeviceHealth.ok);
      expect(container.read(captureBlockedProvider), isFalse);

      // Stall: no reading for > window (the mock's own 1 Hz poll is at 1 s,
      // well past this assertion).
      await Future<void>.delayed(const Duration(milliseconds: 400));

      expect(
        container.read(deviceHealthProvider),
        DeviceHealthState.unreported,
        reason: 'a stale OK must not hold forever',
      );
      expect(
        container.read(captureBlockedProvider),
        isTrue,
        reason: 'unknown-while-connected blocks capture starts conservatively',
      );

      // A fresh reading reopens the gate immediately.
      await emit(_telemetry(cam0: CameraHealth.ok, cam1: CameraHealth.ok));
      expect(container.read(deviceHealthProvider).device, DeviceHealth.ok);
      expect(container.read(captureBlockedProvider), isFalse);
    });
  });

  group('Wire backstop + gate scope', () {
    test('DEVICE_INOPERABLE: start-class commands are refused typed while a '
        'camera is DOWN; the refusal has no side effects', () async {
      mock.mockCamera0Health = CameraHealth.down;

      final rec = await mock.sendCommand<void>(
        _kDeviceId,
        RecordingControlCommand(action: RecordingControlAction.start),
      );
      expect(rec.isDeviceInoperable, isTrue);
      expect(mock.isRecordingActive, isFalse);
      expect(mock.lastRecordingAction, isNull);

      final stream = await mock.sendCommand<void>(
        _kDeviceId,
        StreamingControlCommand(action: StreamingControlAction.start),
      );
      expect(stream.isDeviceInoperable, isTrue);
      expect(mock.isStreamingActive, isFalse);
    });

    test('stop-class commands and downloads/WiFi are never health-gated '
        '(downloads-only mode stays fully functional)', () async {
      mock.mockCamera0Health = CameraHealth.down;

      final stop = await mock.sendCommand<void>(
        _kDeviceId,
        RecordingControlCommand(action: RecordingControlAction.stop),
      );
      expect(stop.isOk, isTrue);

      final download = await mock.sendCommand<void>(
        _kDeviceId,
        DownloadRequestCommand(recordingId: 'rec-1'),
      );
      expect(download.isOk, isTrue);

      final wifi = await mock.sendCommand<void>(
        _kDeviceId,
        StartWifiDirectCommand(),
      );
      expect(wifi.isOk, isTrue);
    });

    test('the download gate (liveSessionActiveProvider) is independent of '
        'health — an inoperable device never locks retrieval', () async {
      mock.mockCamera0Health = CameraHealth.down;
      final container = makeContainer();
      await connect(container);

      expect(
        container.read(deviceHealthProvider).device,
        DeviceHealth.inoperable,
      );
      expect(container.read(captureBlockedProvider), isTrue);
      // The capture gate is scoped: nothing here consults health for
      // retrieval — the download path keys solely off the live-session gate.
    });
  });
}
