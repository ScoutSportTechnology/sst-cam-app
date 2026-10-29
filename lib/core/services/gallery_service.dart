import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:flutter/services.dart';

/// Saves media files to the device gallery.
///
/// Android: uses MediaStore.Video on API 29+ (no permission required) and
/// direct file copy + MediaScanner on API < 29 (WRITE_EXTERNAL_STORAGE needed).
/// iOS: no-op for now — Photos framework integration is future work.
class GalleryService {
  static const _channel = MethodChannel('com.sst.sstcam/media');

  /// Test seam. When set, [saveVideo] delegates here instead of touching the
  /// platform channel — the real path is gated on [Platform.isAndroid], which is
  /// false on the test host, so the success branch is otherwise unreachable in
  /// unit tests. Production leaves this null.
  @visibleForTesting
  static Future<String?> Function({
    required String sourcePath,
    required String displayName,
  })?
  debugSaver;

  /// Copies the file at [sourcePath] into the device gallery under
  /// [displayName]. Returns the gallery URI/path on success, null on failure
  /// or unsupported platform.
  ///
  /// Idempotent: if a file with [displayName] already exists in the gallery,
  /// the host-side implementation skips the copy and returns the existing URI.
  static Future<String?> saveVideo({
    required String sourcePath,
    required String displayName,
  }) async {
    final override = debugSaver;
    if (override != null) {
      return override(sourcePath: sourcePath, displayName: displayName);
    }
    if (!Platform.isAndroid) return null;
    try {
      return await _channel.invokeMethod<String>('saveVideoToGallery', {
        'path': sourcePath,
        'name': displayName,
      });
    } catch (e) {
      debugPrint('GalleryService.saveVideo failed: $e');
      return null;
    }
  }
}
