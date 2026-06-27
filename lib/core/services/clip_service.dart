import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../db/app_database.dart';
import '../db/daos/clips_dao.dart';
import 'video_path_service.dart';

const _uuid = Uuid();

/// Trims a source MP4 to produce a highlight clip.
///
/// Stream-copies the cut natively (Android `MediaExtractor` + `MediaMuxer` via
/// the `com.sst.sstcam/media` channel) — no decode/encode, so it's fast and
/// lossless. Replaced ffmpeg-kit, whose prebuilt `libavfilter.so` failed to
/// load on modern Android (UnsatisfiedLinkError) and crashed the app.
class ClipService {
  const ClipService({required this.clipsDao, required this.videoPathService});

  final ClipsDao clipsDao;
  final VideoPathService videoPathService;

  static const _mediaChannel = MethodChannel('com.sst.sstcam/media');

  /// Trim [sourcePath] from [startSeconds] for [durationSeconds] seconds.
  ///
  /// Returns the path of the output clip file on success.
  /// Throws [ClipTrimException] if the trim fails or the source file is missing.
  Future<String> trim({
    required String matchId,
    required String sourcePath,
    required int startSeconds,
    required int durationSeconds,
    String? label,
  }) async {
    if (!File(sourcePath).existsSync()) {
      throw ClipTrimException('Source file not found: $sourcePath');
    }

    final clipId = _uuid.v4();
    final outputPath = await videoPathService.clipPath(matchId, clipId);

    try {
      await _mediaChannel.invokeMethod<String>('trimVideo', {
        'source': sourcePath,
        'output': outputPath,
        'startMs': startSeconds * 1000,
        'durationMs': durationSeconds * 1000,
      });
    } on PlatformException catch (e) {
      // Clean up any partial output file; ignore cleanup failures.
      try {
        final out = File(outputPath);
        if (out.existsSync()) out.deleteSync();
      } catch (_) {}
      throw ClipTrimException('Trim failed: ${e.message}');
    }

    late final int sizeBytes;
    try {
      sizeBytes = File(outputPath).lengthSync();
    } on FileSystemException catch (e) {
      throw ClipTrimException('Output file unreadable after trim: $e');
    }
    await clipsDao.insertClip(
      ClipsTableCompanion.insert(
        id: clipId,
        matchId: matchId,
        startSeconds: Value(startSeconds),
        durationSeconds: durationSeconds,
        sizeBytes: sizeBytes,
        startedAt: DateTime.now().toIso8601String(),
        label: Value(label),
      ),
    );

    return outputPath;
  }
}

/// Thrown when FFmpeg fails or prerequisites are not met.
class ClipTrimException implements Exception {
  const ClipTrimException(this.message);
  final String message;

  @override
  String toString() => 'ClipTrimException: $message';
}
