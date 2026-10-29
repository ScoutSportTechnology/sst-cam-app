// matchThumbnailProvider — cache-first, fetch-when-connected, never mid-match.
// Mirrors the firmware-serves / app-fetches thumbnail contract on the app side.

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sst_cam_app/core/services/video_path_service.dart';
import 'package:sst_cam_app/core/state/db_providers.dart'
    show videoPathServiceProvider;
import 'package:sst_cam_app/core/wifi/wifi_providers.dart'
    show wifiServiceProvider;
import 'package:sst_cam_app/features/camera/camera_state.dart'
    show activeCameraIdProvider;
import 'package:sst_cam_app/features/video/video_state.dart'
    show liveSessionActiveProvider, matchThumbnailProvider;
import 'package:sst_cam_app/mock/emulator/mock_wifi_service.dart';

const _matchId = '770d9ae2-0751-466a-852f-75b4e91472d9';

// VideoPathService whose thumbnail cache path is a fixed (test-controlled) file.
class _FakePathSvc extends VideoPathService {
  _FakePathSvc(this.path);
  final String path;
  @override
  Future<String> thumbnailPath(String recordingId) async => path;
}

// Records fetchThumbnail calls and returns a configurable result.
class _SpyWifi extends MockWifiService {
  _SpyWifi(this.result);
  final String? result;
  int calls = 0;
  @override
  Future<String?> fetchThumbnail(String deviceId, String uuid) async {
    calls++;
    return result;
  }
}

ProviderContainer _container({
  required String cachePath,
  required _SpyWifi wifi,
  String? cameraId,
  bool live = false,
}) {
  return ProviderContainer(
    overrides: [
      videoPathServiceProvider.overrideWithValue(_FakePathSvc(cachePath)),
      wifiServiceProvider.overrideWithValue(wifi),
      activeCameraIdProvider.overrideWith((_) => cameraId),
      liveSessionActiveProvider.overrideWithValue(live),
    ],
  );
}

void main() {
  late Directory tmp;
  setUp(() async => tmp = await Directory.systemTemp.createTemp('thumb_test_'));
  tearDown(() async => tmp.delete(recursive: true));

  test(
    'returns the cached file without fetching when it already exists',
    () async {
      final cached = File('${tmp.path}/$_matchId.jpg')
        ..writeAsBytesSync([1, 2, 3]);
      final wifi = _SpyWifi('/should/not/be/used.jpg');
      final c = _container(
        cachePath: cached.path,
        wifi: wifi,
        cameraId: 'cam-1',
      );

      final result = await c.read(matchThumbnailProvider(_matchId).future);
      expect(result, cached.path);
      expect(wifi.calls, 0, reason: 'a cache hit must not hit the network');
      c.dispose();
    },
  );

  test('null when no camera is connected (and no cache)', () async {
    final wifi = _SpyWifi('/cam/thumb.jpg');
    final c = _container(
      cachePath: '${tmp.path}/missing.jpg',
      wifi: wifi,
      cameraId: null,
    );
    expect(await c.read(matchThumbnailProvider(_matchId).future), isNull);
    expect(wifi.calls, 0);
    c.dispose();
  });

  test('fetches over WiFi when connected and not mid-match', () async {
    final wifi = _SpyWifi('/cam/thumb.jpg');
    final c = _container(
      cachePath: '${tmp.path}/missing.jpg',
      wifi: wifi,
      cameraId: 'cam-1',
    );
    expect(
      await c.read(matchThumbnailProvider(_matchId).future),
      '/cam/thumb.jpg',
    );
    expect(wifi.calls, 1);
    c.dispose();
  });

  test('never fetches while a live session is active', () async {
    final wifi = _SpyWifi('/cam/thumb.jpg');
    final c = _container(
      cachePath: '${tmp.path}/missing.jpg',
      wifi: wifi,
      cameraId: 'cam-1',
      live: true,
    );
    expect(await c.read(matchThumbnailProvider(_matchId).future), isNull);
    expect(wifi.calls, 0, reason: 'retrieval is blocked mid-match');
    c.dispose();
  });
}
