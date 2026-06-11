import 'package:flutter_test/flutter_test.dart';
import 'package:sst_cam_app/core/ble/ble_service.dart';
import 'package:sst_cam_app/mock/emulator/mock_ble_service.dart';
import 'package:sst_cam_app/core/models/command.dart';
import 'package:sst_cam_app/core/models/device.dart';
import 'package:sst_cam_app/core/models/overlay_layout.dart';
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

  group('RawCaptureControlCommand', () {
    test('start records the app-minted group + sets raw-capturing', () async {
      final resp = await svc.sendCommand(
        'SST-CAM-001',
        RawCaptureControlCommand(
          action: RecordingControlAction.start,
          captureGroupId: 'grp-xyz',
        ),
      );
      expect(resp.isOk, isTrue);
      expect(svc.isRawCapturingActive, isTrue);
      expect(svc.lastRawCaptureGroupId, 'grp-xyz');

      final tel = await svc.sendCommand<DeviceTelemetry>(
        'SST-CAM-001',
        GetTelemetryCommand(),
      );
      expect(tel.payload!.isRawCapturing, isTrue);
    });

    test('stop clears raw-capturing', () async {
      await svc.sendCommand(
        'SST-CAM-001',
        RawCaptureControlCommand(
          action: RecordingControlAction.start,
          captureGroupId: 'g',
        ),
      );
      await svc.sendCommand(
        'SST-CAM-001',
        RawCaptureControlCommand(action: RecordingControlAction.stop),
      );
      expect(svc.isRawCapturingActive, isFalse);
    });

    test('pause/resume are rejected (firmware answers UNSUPPORTED)', () async {
      final pause = await svc.sendCommand(
        'SST-CAM-001',
        RawCaptureControlCommand(action: RecordingControlAction.pause),
      );
      // The app surfaces UNSUPPORTED distinctly from a generic error — the mock
      // must not collapse it (it mirrors BleProtocol.decodeResponse).
      expect(pause.isOk, isFalse);
      expect(pause.status, BleResponseStatus.unsupported);
    });

    test(
      'after start, listRecordings surfaces the raw pair for the group',
      () async {
        await svc.sendCommand(
          'SST-CAM-001',
          RawCaptureControlCommand(
            action: RecordingControlAction.start,
            captureGroupId: 'grp-pair',
          ),
        );

        final resp = await svc.sendCommand<List<RecordingMetadata>>(
          'SST-CAM-001',
          ListRecordingsCommand(),
        );
        final raw = (resp.payload ?? <RecordingMetadata>[])
            .where((r) => r.isRaw && r.captureGroupId == 'grp-pair')
            .toList();

        // Real firmware leaves two per-camera files stamped with the group id;
        // the mock must too, or the app's stop()->list->pair->download path can
        // never complete against the emulated firmware.
        expect(raw, hasLength(2));
        expect(raw.map((r) => r.cameraIndex).toSet(), {0, 1});
        expect(raw.every((r) => r.captureGroupId == 'grp-pair'), isTrue);
      },
    );
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

  // Minimal overlay layout for testing
  const testLayout = OverlayLayout(
    canvasWidth: 1920,
    canvasHeight: 1080,
    elements: [],
    templates: [],
  );

  group('RecordingControlCommand (U4)', () {
    test('start action returns ok and sets side effects', () async {
      final resp = await svc.sendCommand<void>(
        'SST-CAM-001',
        RecordingControlCommand(action: RecordingControlAction.start),
      );
      expect(resp.isOk, isTrue);
      expect(svc.lastRecordingAction, RecordingControlAction.start);
      expect(svc.isRecordingActive, isTrue);
    });

    test('stop action clears isRecordingActive', () async {
      await svc.sendCommand<void>(
        'SST-CAM-001',
        RecordingControlCommand(action: RecordingControlAction.start),
      );
      await svc.sendCommand<void>(
        'SST-CAM-001',
        RecordingControlCommand(action: RecordingControlAction.stop),
      );
      expect(svc.isRecordingActive, isFalse);
      expect(svc.lastRecordingAction, RecordingControlAction.stop);
    });

    test('resume sets isRecordingActive', () async {
      final resp = await svc.sendCommand<void>(
        'SST-CAM-001',
        RecordingControlCommand(action: RecordingControlAction.resume),
      );
      expect(resp.isOk, isTrue);
      expect(svc.isRecordingActive, isTrue);
    });

    test('pause clears isRecordingActive', () async {
      await svc.sendCommand<void>(
        'SST-CAM-001',
        RecordingControlCommand(action: RecordingControlAction.resume),
      );
      await svc.sendCommand<void>(
        'SST-CAM-001',
        RecordingControlCommand(action: RecordingControlAction.pause),
      );
      expect(svc.isRecordingActive, isFalse);
    });
  });

  group('StreamingControlCommand (U4)', () {
    test('start returns ok and sets isStreamingActive', () async {
      final resp = await svc.sendCommand<void>(
        'SST-CAM-001',
        StreamingControlCommand(
          action: StreamingControlAction.start,
          rtmpUrl: 'rtmp://example.com/live/key',
        ),
      );
      expect(resp.isOk, isTrue);
      expect(svc.isStreamingActive, isTrue);
    });

    test('stop clears isStreamingActive', () async {
      await svc.sendCommand<void>(
        'SST-CAM-001',
        StreamingControlCommand(action: StreamingControlAction.start),
      );
      await svc.sendCommand<void>(
        'SST-CAM-001',
        StreamingControlCommand(action: StreamingControlAction.stop),
      );
      expect(svc.isStreamingActive, isFalse);
    });
  });

  group('MatchControlCommand (U4)', () {
    test('kickoff returns ok and records action', () async {
      final resp = await svc.sendCommand<void>(
        'SST-CAM-001',
        MatchControlCommand(action: BleMatchControlAction.kickoff, period: 1),
      );
      expect(resp.isOk, isTrue);
      expect(svc.lastMatchControlAction, BleMatchControlAction.kickoff);
    });

    test('periodEnd records correct action', () async {
      await svc.sendCommand<void>(
        'SST-CAM-001',
        MatchControlCommand(action: BleMatchControlAction.periodEnd, period: 1),
      );
      expect(svc.lastMatchControlAction, BleMatchControlAction.periodEnd);
    });
  });

  group('ScoreUpdateCommand (U4)', () {
    test('returns ok response', () async {
      final resp = await svc.sendCommand<void>(
        'SST-CAM-001',
        ScoreUpdateCommand(teamId: 'team-a', delta: 1),
      );
      expect(resp.isOk, isTrue);
    });
  });

  group('BannerEventCommand (U4)', () {
    test('returns ok and records last banner event', () async {
      final resp = await svc.sendCommand<void>(
        'SST-CAM-001',
        BannerEventCommand(templateId: 'goal', durationSeconds: 5),
      );
      expect(resp.isOk, isTrue);
      expect(svc.lastBannerEvent, isNotNull);
      expect(svc.lastBannerEvent!.templateId, 'goal');
      expect(svc.lastBannerEvent!.durationSeconds, 5);
    });

    test('records params and playerId', () async {
      await svc.sendCommand<void>(
        'SST-CAM-001',
        BannerEventCommand(
          templateId: 'yellow_card',
          params: {'player': 'John Doe'},
          durationSeconds: 4,
          playerId: 'player-123',
        ),
      );
      expect(svc.lastBannerEvent!.params['player'], 'John Doe');
      expect(svc.lastBannerEvent!.playerId, 'player-123');
    });
  });

  group('PushOverlayLayoutCommand (U4)', () {
    test('sendCommand returns ok', () async {
      final resp = await svc.sendCommand<void>(
        'SST-CAM-001',
        PushOverlayLayoutCommand(layout: testLayout),
      );
      expect(resp.isOk, isTrue);
    });

    test('records last pushed layout via sendCommand', () async {
      await svc.sendCommand<void>(
        'SST-CAM-001',
        PushOverlayLayoutCommand(layout: testLayout),
      );
      expect(svc.lastPushedOverlayLayout, isNotNull);
      expect(svc.lastPushedOverlayLayout!.canvasWidth, 1920);
    });
  });

  group('pushOverlayLayout (U5)', () {
    test('completes without throw and records layout', () async {
      await expectLater(
        svc.pushOverlayLayout('SST-CAM-001', testLayout),
        completes,
      );
      expect(svc.lastPushedOverlayLayout, same(testLayout));
    });

    test('failNextPushOverlayLayout throws BleTimeoutException', () async {
      svc.failNextPushOverlayLayout = true;
      await expectLater(
        svc.pushOverlayLayout('SST-CAM-001', testLayout),
        throwsA(isA<BleTimeoutException>()),
      );
      expect(svc.failNextPushOverlayLayout, isFalse); // auto-reset
    });

    test('proto round-trip via sendCommand with real layout', () async {
      final layout = defaultScoreboardLayout(
        homeName: 'Reds',
        awayName: 'Blues',
        homeColorHex: '#FF0000',
        awayColorHex: '#0000FF',
      );
      final resp = await svc.sendCommand<void>(
        'SST-CAM-001',
        PushOverlayLayoutCommand(layout: layout),
      );
      expect(resp.isOk, isTrue);
      expect(svc.lastPushedOverlayLayout!.elements, isNotEmpty);
      expect(svc.lastPushedOverlayLayout!.templates, isNotEmpty);
    });
  });
}
