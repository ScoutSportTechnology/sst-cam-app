import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sst_cam_app/mock/mock_video_fetcher.dart';

void main() {
  group('joinBaseUrl', () {
    test('joins a base and path with a single separator', () {
      expect(
        joinBaseUrl('http://localhost:8080', 'recordings/abc'),
        'http://localhost:8080/recordings/abc',
      );
    });

    test('tolerates a trailing slash on the base', () {
      expect(
        joinBaseUrl('http://localhost:8080/', 'recordings/abc'),
        'http://localhost:8080/recordings/abc',
      );
    });

    test('tolerates a leading slash on the path', () {
      expect(
        joinBaseUrl('rtsp://mws.domain', '/preview'),
        'rtsp://mws.domain/preview',
      );
    });

    test('port-less domain base produces a port-less URL', () {
      expect(
        joinBaseUrl('https://mws.domain', 'recordings/uuid-1'),
        'https://mws.domain/recordings/uuid-1',
      );
    });
  });

  group('fetchVideoOrFallback', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('video_fetcher_test_');
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    test(
      'writes the response bytes and sends the Bearer token on success',
      () async {
        final bytes = List<int>.generate(2048, (i) => i % 256);
        String? receivedAuth;
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        server.listen((req) async {
          receivedAuth = req.headers.value('authorization');
          req.response.add(bytes);
          await req.response.close();
        });
        addTearDown(() => server.close(force: true));

        final savePath = '${tempDir.path}/sub/video.mp4';
        await fetchVideoOrFallback(
          url: 'http://${server.address.host}:${server.port}/recordings/abc',
          authToken: 'tok-123',
          savePath: savePath,
        );

        final file = File(savePath);
        expect(file.existsSync(), isTrue);
        expect(await file.readAsBytes(), bytes);
        expect(receivedAuth, 'Bearer tok-123');
      },
    );

    test('falls back to a sentinel when the server is unreachable', () async {
      // Port 1 is not listening; a short timeout keeps the test fast.
      final savePath = '${tempDir.path}/fallback/video.mp4';
      await fetchVideoOrFallback(
        url: 'http://127.0.0.1:1/recordings/abc',
        authToken: 'tok',
        savePath: savePath,
        httpClient: Dio(
          BaseOptions(connectTimeout: const Duration(milliseconds: 200)),
        ),
      );

      // No asset bundle in unit tests → bundled copy fails → 1-byte sentinel.
      final file = File(savePath);
      expect(file.existsSync(), isTrue);
      expect(file.lengthSync(), 1);
    });

    test('creates parent directories that do not yet exist', () async {
      final savePath = '${tempDir.path}/a/b/c/video.mp4';
      await fetchVideoOrFallback(
        url: 'http://127.0.0.1:1/recordings/abc',
        authToken: 'tok',
        savePath: savePath,
        httpClient: Dio(
          BaseOptions(connectTimeout: const Duration(milliseconds: 200)),
        ),
      );
      expect(File(savePath).existsSync(), isTrue);
    });
  });
}
