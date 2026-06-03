import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show rootBundle;

/// The one canonical mock video bundled into the app. Used as the offline
/// fallback when the mock WiFi container is unreachable.
const kBundledMockVideoAsset = 'lib/mock/emulator/mock-video.mp4';

/// Joins a `scheme://host[:port]` base with a relative [path], tolerating a
/// trailing slash on the base so it never produces `//path`.
String joinBaseUrl(String base, String path) {
  final trimmedBase = base.endsWith('/')
      ? base.substring(0, base.length - 1)
      : base;
  final trimmedPath = path.startsWith('/') ? path.substring(1) : path;
  return '$trimmedBase/$trimmedPath';
}

/// Materializes a recording video at [savePath] using the same mechanics the
/// live app uses, with a graceful fallback chain so callers never hard-fail:
///
/// 1. HTTP GET [url] with a Bearer [authToken] → write the response bytes.
/// 2. On any HTTP failure → copy the bundled [kBundledMockVideoAsset].
/// 3. On bundle failure (e.g. unit tests without an asset bundle) → 1-byte
///    sentinel.
///
/// Shared by the live download path and the seed-time video writes so all
/// three exercise the same container → bundled → sentinel behaviour.
/// [httpClient] is injectable for tests; a default Dio is created otherwise.
Future<void> fetchVideoOrFallback({
  required String url,
  required String authToken,
  required String savePath,
  Dio? httpClient,
}) async {
  final dio =
      httpClient ??
      Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 3),
          receiveTimeout: const Duration(seconds: 30),
        ),
      );
  final file = File(savePath);
  await file.parent.create(recursive: true);
  try {
    final resp = await dio.get<List<int>>(
      url,
      options: Options(
        headers: {'Authorization': 'Bearer $authToken'},
        responseType: ResponseType.bytes,
      ),
    );
    if (resp.statusCode == 200 && resp.data != null) {
      await file.writeAsBytes(resp.data!, flush: true);
      return;
    }
  } on DioException catch (e) {
    debugPrint(
      'fetchVideoOrFallback: HTTP failed ($e), using bundled fallback',
    );
  } catch (e) {
    debugPrint('fetchVideoOrFallback: unexpected error during download: $e');
  }
  await _writeBundledOrSentinel(file);
}

Future<void> _writeBundledOrSentinel(File file) async {
  try {
    final data = await rootBundle.load(kBundledMockVideoAsset);
    await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
  } catch (e) {
    debugPrint(
      'fetchVideoOrFallback: bundled asset copy failed, writing sentinel: $e',
    );
    await file.writeAsBytes([0x00], flush: true);
  }
}
