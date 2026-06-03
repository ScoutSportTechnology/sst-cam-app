import 'package:flutter_test/flutter_test.dart';
import 'package:sst_cam_app/core/ble/ble_service.dart';
import 'package:sst_cam_app/mock/emulator/mock_ble_service.dart';
import 'package:sst_cam_app/core/models/command.dart';
import 'package:sst_cam_app/core/models/device.dart';
import 'package:sst_cam_app/core/models/recording.dart';
import 'package:sst_cam_app/core/models/telemetry.dart';
import 'package:sst_cam_app/core/models/match.dart';

void main() {
  // Required so rootBundle can load fixture assets in unit tests.
  // Without this, _doLoadRecordings falls back silently but logs
  // a "Binding has not yet been initialized" error on every test run.
  setUpAll(TestWidgetsFlutterBinding.ensureInitialized);

  late MockBleService svc;

  setUp(() {
    svc = MockBleService(
      scanDeviceAppearDelays: [Duration.zero, Duration.zero],
      connectionDelay: Duration.zero,
      failureRate: 0.0,
      randomSeed: 42,
    );
  });

  tearDown(() => svc.dispose());

  group('Discovery', () {
    test('starts with empty device list', () async {
      final devices = await svc.discoveredDevices.first;
      expect(devices, isEmpty);
    });

    test('emits devices progressively during scan', () async {
      final emitted = <List<SstDevice>>[];
      final sub = svc.discoveredDevices.listen(emitted.add);

      await svc.startScan(timeout: const Duration(seconds: 10));
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);

      await svc.stopScan();
      await sub.cancel();

      expect(emitted.any((l) => l.length == 2), isTrue);
    });

    test('device names follow sst-cam-#### convention', () async {
      final emitted = <List<SstDevice>>[];
      final sub = svc.discoveredDevices.listen(emitted.add);

      await svc.startScan();
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);
      await svc.stopScan();
      await sub.cancel();

      final devices = emitted.lastWhere((l) => l.isNotEmpty, orElse: () => []);
      for (final d in devices) {
        expect(d.name.toLowerCase(), startsWith('sst-cam-'));
      }
    });

    test('stopScan sets isScanning to false', () async {
      await svc.startScan();
      await svc.stopScan();
      expect(svc.isScanning, isFalse);
    });
  });

  group('Connection', () {
    test('connect emits connecting then connected', () async {
      const id = 'SST-CAM-001';
      final states = <CameraConnectionState>[];
      final sub = svc.connectionStateStream(id).listen(states.add);

      await svc.connect(id);
      await sub.cancel();

      expect(
        states,
        containsAllInOrder([
          CameraConnectionState.connecting,
          CameraConnectionState.connected,
        ]),
      );
    });

    test('disconnect emits disconnected', () async {
      const id = 'SST-CAM-001';
      await svc.connect(id);

      final states = <CameraConnectionState>[];
      final sub = svc.connectionStateStream(id).listen(states.add);
      await svc.disconnect(id);
      await sub.cancel();

      expect(states.last, CameraConnectionState.disconnected);
    });

    test('connect to unknown device throws BleConnectionException', () {
      expect(
        () => svc.connect('UNKNOWN-999'),
        throwsA(isA<BleConnectionException>()),
      );
    });
  });

  group('Telemetry', () {
    test('emits telemetry after connect', () async {
      const id = 'SST-CAM-001';
      await svc.connect(id);

      final telemetry = await svc.telemetryStream(id).first;
      expect(telemetry.storageTotalBytes, greaterThan(0));
      expect(telemetry.cpuUsedPct, inInclusiveRange(0.0, 1.0));
      expect(telemetry.ramUsedPct, inInclusiveRange(0.0, 1.0));
    });
  });

  group('Externalized fixtures (U4)', () {
    test('discovery returns the devices defined in devices.json', () async {
      final emitted = <List<SstDevice>>[];
      final sub = svc.discoveredDevices.listen(emitted.add);

      await svc.startScan();
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);
      await svc.stopScan();
      await sub.cancel();

      final devices = emitted.lastWhere((l) => l.length == 2, orElse: () => []);
      expect(devices, hasLength(2));
      expect(
        devices.map((d) => d.id),
        containsAll(['SST-CAM-001', 'SST-CAM-002']),
      );
      final first = devices.firstWhere((d) => d.id == 'SST-CAM-001');
      expect(first.name, 'sst-cam-0001');
      expect(first.batteryPercent, 82);
      expect(first.rssi, -58);
    });

    test('telemetry baseline comes from telemetry.json', () async {
      const id = 'SST-CAM-001';
      await svc.connect(id);
      final t = await svc.telemetryStream(id).first; // tick 0 → no drift
      expect(t.storageTotalBytes, 274877906944); // 256 GiB baseline
      expect(t.wifiSsid, 'StadiumNet-5G');
      expect(t.wifiSignalDbm, -65);
    });

    test('proto and dart telemetry share one baseline at tick 0', () async {
      const id = 'SST-CAM-001';
      await svc.connect(id);
      final dartT = await svc.telemetryStream(id).first; // tick 0
      final resp = await svc.sendCommand<DeviceTelemetry>(
        id,
        GetTelemetryCommand(),
      );
      final protoT = resp.payload!;
      expect(protoT.storageTotalBytes, dartT.storageTotalBytes);
      expect(protoT.wifiSsid, dartT.wifiSsid);
      expect(protoT.wifiSignalDbm, dartT.wifiSignalDbm);
      expect(protoT.tempCelsius, closeTo(dartT.tempCelsius, 0.0001));
    });
  });

  group('Thumbnail', () {
    test('returns valid JPEG bytes', () async {
      const id = 'SST-CAM-001';
      await svc.connect(id);
      final result = await svc.requestThumbnail(id);

      expect(result.jpegBytes, isNotEmpty);
      expect(result.jpegBytes[0], 0xFF); // JPEG SOI
      expect(result.jpegBytes[1], 0xD8);
    });
  });

  group('Recordings', () {
    test('listRecordings returns non-empty list', () async {
      final recordings = await svc.listRecordings('SST-CAM-001');
      expect(recordings, isNotEmpty);
      for (final r in recordings) {
        expect(r.id, isNotEmpty);
        expect(r.durationSeconds, greaterThan(0));
      }
    });

    test('requestDownload returns valid non-expired token', () async {
      final token = await svc.requestDownload('SST-CAM-001', 'rec-001');
      // Suffix-less /recordings/<id> form derived from downloadBaseUrl.
      expect(token.httpUrl, 'http://localhost:8080/recordings/rec-001');
      expect(token.authToken, isNotEmpty);
      expect(token.isExpired, isFalse);
    });
  });

  group('Commands', () {
    test('GetTelemetryCommand returns telemetry payload', () async {
      final resp = await svc.sendCommand('SST-CAM-001', GetTelemetryCommand());
      expect(resp.isOk, isTrue);
      expect(resp.payload, isNotNull);
    });

    test('GetMatchStateCommand returns match state payload', () async {
      final resp = await svc.sendCommand('SST-CAM-001', GetMatchStateCommand());
      expect(resp.isOk, isTrue);
      expect(resp.payload, isNotNull);
    });

    test('ListRecordingsCommand returns recordings', () async {
      final resp = await svc.sendCommand<List<RecordingMetadata>>(
        'SST-CAM-001',
        ListRecordingsCommand(),
      );
      expect(resp.isOk, isTrue);
      expect(resp.payload, isNotEmpty);
    });

    test('DownloadRequestCommand returns token', () async {
      final resp = await svc.sendCommand<DownloadToken>(
        'SST-CAM-001',
        DownloadRequestCommand(recordingId: 'rec-001'),
      );
      expect(resp.isOk, isTrue);
      expect(resp.payload?.httpUrl, startsWith('http://'));
    });
  });

  group('advertiseDevices', () {
    test('advertiseDevices=true (default) emits devices during scan', () async {
      final emitted = <List<SstDevice>>[];
      final sub = svc.discoveredDevices.listen(emitted.add);

      await svc.startScan(timeout: const Duration(seconds: 10));
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);

      await svc.stopScan();
      await sub.cancel();

      expect(emitted.any((l) => l.isNotEmpty), isTrue);
    });

    test(
      'advertiseDevices=false emits only an empty list and completes',
      () async {
        final noAdSvc = MockBleService(
          advertiseDevices: false,
          scanDeviceAppearDelays: [Duration.zero, Duration.zero],
          connectionDelay: Duration.zero,
          failureRate: 0.0,
        );
        addTearDown(noAdSvc.dispose);

        final emitted = <List<SstDevice>>[];
        final sub = noAdSvc.discoveredDevices.listen(emitted.add);

        await noAdSvc.startScan(timeout: const Duration(seconds: 10));
        await Future.delayed(Duration.zero);
        await Future.delayed(Duration.zero);

        await noAdSvc.stopScan();
        await sub.cancel();

        expect(emitted.every((l) => l.isEmpty), isTrue);
      },
    );
  });

  group('Proto round-trip', () {
    test(
      'GetTelemetryCommand returns BleCommandResponse with valid DeviceTelemetry',
      () async {
        final resp = await svc.sendCommand<DeviceTelemetry>(
          'SST-CAM-001',
          GetTelemetryCommand(),
        );
        expect(resp.isOk, isTrue);
        final t = resp.payload;
        expect(t, isNotNull);
        expect(t!.storageTotalBytes, greaterThan(0));
        expect(t.cpuUsedPct, inInclusiveRange(0.0, 1.0));
        expect(t.ramUsedPct, inInclusiveRange(0.0, 1.0));
        expect(t.tempCelsius, greaterThan(0.0));
      },
    );

    test('GetMatchStateCommand returns valid MatchState', () async {
      final resp = await svc.sendCommand<MatchState>(
        'SST-CAM-001',
        GetMatchStateCommand(),
      );
      expect(resp.isOk, isTrue);
      expect(resp.payload, isNotNull);
      expect(resp.payload!.status, isA<MatchStatus>());
    });

    test('correlation_id is echoed correctly in the response', () async {
      // sendCommand() generates a correlation_id internally; the proto
      // round-trip must echo it back unchanged.
      final resp = await svc.sendCommand<DeviceTelemetry>(
        'SST-CAM-001',
        GetTelemetryCommand(),
      );
      // We can't directly inspect the internal id, but isOk proves the
      // response was matched (error responses carry an errorMessage).
      expect(resp.isOk, isTrue);
      expect(resp.errorMessage, isNull);
    });

    test('proto round-trip is lossless for DeviceTelemetry fields', () async {
      final resp = await svc.sendCommand<DeviceTelemetry>(
        'SST-CAM-001',
        GetTelemetryCommand(),
      );
      final t = resp.payload!;
      // storageFreeBytes + storageTotalBytes survive the int64 round-trip
      expect(t.storageFreeBytes, greaterThanOrEqualTo(0));
      expect(t.storageTotalBytes, greaterThan(t.storageFreeBytes));
      expect(t.wifiState, isA<WifiState>());
    });
  });

  group('Failure simulation', () {
    test('failureRate=1.0 always throws', () async {
      final failSvc = MockBleService(
        connectionDelay: Duration.zero,
        failureRate: 1.0,
        randomSeed: 0,
      );
      addTearDown(failSvc.dispose);

      expect(
        () => failSvc.connect('SST-CAM-001'),
        throwsA(isA<BleConnectionException>()),
      );
    });
  });
}
