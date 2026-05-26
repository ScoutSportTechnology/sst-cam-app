import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';

/// Saves media files to the device gallery.
///
/// Android: uses MediaStore.Video on API 29+ (no permission required) and
/// direct file copy + MediaScanner on API < 29 (WRITE_EXTERNAL_STORAGE needed).
/// iOS: no-op for now — Photos framework integration is future work.
class GalleryService {
  static const _channel = MethodChannel('com.sst.sstcam/media');

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
