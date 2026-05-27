import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:sst_cam_app/core/models/overlay.dart';
import 'package:sst_cam_app/core/models/recording.dart';
import 'package:sst_cam_app/core/models/wifi.dart';
import 'package:sst_cam_app/core/services/video_path_service.dart';
import 'package:sst_cam_app/mock/emulator/mock_wifi_service.dart';

// ---------------------------------------------------------------------------
// Fake path_provider that uses a temp directory for tests.
// ---------------------------------------------------------------------------
class _FakePathProvider
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  final String tempPath;
  _FakePathProvider(this.tempPath);

  @override
  Future<String?> getApplicationSupportPath() async => tempPath;

  @override
  Future<String?> getTemporaryPath() async => tempPath;

  @override
  Future<String?> getApplicationDocumentsPath() async => tempPath;

  @override
  Future<String?> getApplicationCachePath() async => tempPath;

  @override
  Future<String?> getExternalStoragePath() async => null;

  @override
  Future<List<String>?> getExternalCachePaths() async => null;

  @override
  Future<List<String>?> getExternalStoragePaths({
    StorageDirectory? type,
  }) async =>
      null;

  @override
  Future<String?> getDownloadsPath() async => null;

  @override
  Future<String?> getLibraryPath() async => tempPath;
}

void main() {
  setUpAll(TestWidgetsFlutterBinding.ensureInitialized);

  late Directory tempDir;
  late VideoPathService videoPathService;
  late MockWifiService svc;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('mock_wifi_test_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    videoPathService = VideoPathService();
    svc = MockWifiService(
      pairingDelay: Duration.zero,
      downloadDuration: const Duration(milliseconds: 200),
      downloadFailureRate: 0.0,
      randomSeed: 42,
      videoPathService: videoPathService,
    );
  });

  tearDown(() async {
    await svc.dispose();
    await tempDir.delete(recursive: true);
  });

  // ---------------------------------------------------------------------------
  // Group lifecycle
  // ---------------------------------------------------------------------------

  group('Group lifecycle', () {
    test('connectGroup returns a WifiDirectGroup', () async {
      final group = await svc.connectGroup('device-1');
      expect(group.ssid, isNotEmpty);
      expect(group.groupOwnerIp, isNotEmpty);
      expect(group.previewPort, greaterThan(0));
    });

    test('disconnectGroup completes without error', () async {
      await svc.connectGroup('device-1');
      await expectLater(svc.disconnectGroup('device-1'), completes);
    });
  });

  // ---------------------------------------------------------------------------
  // serverAddress — configurable IP (U6)
  // ---------------------------------------------------------------------------

  group('serverAddress', () {
    test('default groupOwnerIp is localhost', () async {
      final group = await svc.connectGroup('device-1');
      expect(group.groupOwnerIp, 'localhost');
    });

    test('custom serverAddress propagates to groupOwnerIp', () async {
      final customSvc = MockWifiService(
        serverAddress: '192.168.1.100',
        pairingDelay: Duration.zero,
        videoPathService: videoPathService,
      );
      addTearDown(customSvc.dispose);
      final group = await customSvc.connectGroup('device-1');
      expect(group.groupOwnerIp, '192.168.1.100');
    });

    test('empty serverAddress falls back to localhost', () async {
      final emptySvc = MockWifiService(
        serverAddress: '',
        pairingDelay: Duration.zero,
        videoPathService: videoPathService,
      );
      addTearDown(emptySvc.dispose);
      final group = await emptySvc.connectGroup('device-1');
      expect(group.groupOwnerIp, 'localhost');
    });

    test('previewDescriptor url contains serverAddress', () async {
      final customSvc = MockWifiService(
        serverAddress: '10.0.0.5',
        pairingDelay: Duration.zero,
        videoPathService: videoPathService,
      );
      addTearDown(customSvc.dispose);
      await customSvc.connectGroup('device-1');
      final desc = customSvc.previewDescriptor('device-1');
      expect(desc, isNotNull);
      expect(desc!.url, 'rtsp://10.0.0.5:8554/preview');
    });

    test('download falls back to bundled file when HTTP server unreachable',
        () async {
      // localhost:8080 not running in unit tests → HTTP GET fails → fallback
      const uuid = 'rec-fallback-test';
      final handle = await svc.downloadRecording('device-1', uuid);
      await handle.progress.toList();

      final path = await videoPathService.recordingPath(uuid);
      expect(File(path).existsSync(), isTrue,
          reason: 'Fallback write must produce a file even without HTTP server');
    });
  });

  // ---------------------------------------------------------------------------
  // checkCameraHasRecording
  // ---------------------------------------------------------------------------

  group('checkCameraHasRecording', () {
    test('returns true for any UUID', () async {
      expect(await svc.checkCameraHasRecording('any-uuid'), isTrue);
      expect(await svc.checkCameraHasRecording('another-uuid-123'), isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // downloadRecording
  // ---------------------------------------------------------------------------

  group('downloadRecording', () {
    test('progress emits increasing bytesReceived', () async {
      final handle = await svc.downloadRecording('device-1', 'rec-uuid-001');
      final events = await handle.progress.toList();

      final received = events.map((e) => e.bytesReceived).toList();
      // Verify the sequence is non-decreasing
      for (var i = 1; i < received.length; i++) {
        expect(received[i], greaterThanOrEqualTo(received[i - 1]));
      }
      expect(received.last, greaterThan(0));
    });

    test('last progress event has completed status', () async {
      final handle = await svc.downloadRecording('device-1', 'rec-uuid-002');
      final events = await handle.progress.toList();

      expect(events.last.status, DownloadStatus.completed);
    });

    test('placeholder file exists after download completes', () async {
      const uuid = 'rec-uuid-003';
      final handle = await svc.downloadRecording('device-1', uuid);
      await handle.progress.toList(); // drain to completion

      final path = await videoPathService.recordingPath(uuid);
      expect(File(path).existsSync(), isTrue);
    });

    test('emits failed with errorMessage on simulated failure', () async {
      final failSvc = MockWifiService(
        downloadDuration: const Duration(milliseconds: 200),
        downloadFailureRate: 1.0,
        randomSeed: 0,
        videoPathService: videoPathService,
      );
      addTearDown(failSvc.dispose);

      final handle = await failSvc.downloadRecording('device-1', 'uuid-fail');
      final events = await handle.progress.toList();

      expect(
        events.any((e) => e.status == DownloadStatus.failed),
        isTrue,
        reason: 'Expected at least one failed event',
      );
      expect(events.last.errorMessage, 'Simulated network drop');
    });

    test('cancel stops stream before completion; placeholder not written',
        () async {
      const uuid = 'rec-uuid-cancel';
      final handle = await svc.downloadRecording('device-1', uuid);

      final events = <VideoDownloadProgress>[];
      late StreamSubscription<VideoDownloadProgress> sub;
      sub = handle.progress.listen(
        events.add,
        onDone: () {},
      );

      // Let a couple of ticks fire, then cancel.
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await handle.cancel();
      await sub.cancel();

      expect(
        events.any((e) => e.status == DownloadStatus.cancelled),
        isTrue,
        reason: 'Expected at least one cancelled event',
      );

      final path = await videoPathService.recordingPath(uuid);
      expect(
        File(path).existsSync(),
        isFalse,
        reason: 'Placeholder must not be written when download is cancelled',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // downloadRecordingWithOverlays
  // ---------------------------------------------------------------------------

  group('downloadRecordingWithOverlays', () {
    test('behaves same as downloadRecording (overlays ignored)', () async {
      const uuid = 'rec-uuid-overlay';
      const overlays = <OverlayState>[];
      const config = OverlayConfig(showScore: true, showEvents: false);

      final handle = await svc.downloadRecordingWithOverlays(
        'device-1',
        uuid,
        overlays,
        config,
      );
      final events = await handle.progress.toList();

      expect(events.last.status, DownloadStatus.completed);

      final path = await videoPathService.recordingPath(uuid);
      expect(File(path).existsSync(), isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // overlayStateStream
  // ---------------------------------------------------------------------------

  group('overlayStateStream', () {
    test('emits an OverlayState within 1.5 seconds', () async {
      final state = await svc
          .overlayStateStream('device-1')
          .first
          .timeout(const Duration(milliseconds: 1500));

      expect(state.homeScore, 0);
      expect(state.awayScore, 0);
      expect(state.period, 1);
    });
  });

  // ---------------------------------------------------------------------------
  // startDownload (existing method — regression)
  // ---------------------------------------------------------------------------

  group('startDownload', () {
    test('throws WifiDirectException when group is not connected', () async {
      await expectLater(
        svc.startDownload(
          'device-1',
          DownloadToken(
            recordingId: 'rec-001',
            httpUrl: 'http://192.168.49.1:8080/rec-001',
            authToken: 'token',
            expiresAt: DateTime.now().add(const Duration(hours: 1)),
          ),
        ),
        throwsA(isA<WifiDirectException>()),
      );
    });

    test('returns handle with progress stream when group connected', () async {
      await svc.connectGroup('device-1');
      final token = DownloadToken(
        recordingId: 'rec-001',
        httpUrl: 'http://192.168.49.1:8080/rec-001',
        authToken: 'token',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      );
      final handle = await svc.startDownload('device-1', token);
      final events = await handle.progress.toList();
      expect(events.last.status, DownloadStatus.completed);
    });
  });
}
