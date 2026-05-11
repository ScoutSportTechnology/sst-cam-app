import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:ffmpeg_kit_flutter_min/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_min/return_code.dart';
import 'package:uuid/uuid.dart';

import '../db/app_database.dart';
import '../db/daos/clips_dao.dart';
import 'video_path_service.dart';

const _uuid = Uuid();

/// Trims a source MP4 to produce a highlight clip.
///
/// Uses FFmpeg `-c copy` (cut-only, no re-encode) for fast, lossless output.
/// The result is an MP4 file in the app-private videos/ directory.
class ClipService {
  const ClipService({required this.clipsDao});

  final ClipsDao clipsDao;

  /// Trim [sourcePath] from [startSeconds] for [durationSeconds] seconds.
  ///
  /// Returns the path of the output clip file on success.
  /// Throws [ClipTrimException] if FFmpeg fails or the source file is missing.
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
    final outputPath = await VideoPathService().clipPath(matchId, clipId);

    // -ss before -i for fast seek; -c copy for no re-encode.
    final cmd = '-y -ss $startSeconds -t $durationSeconds '
        '-i "$sourcePath" -c copy "$outputPath"';

    final session = await FFmpegKit.execute(cmd);
    final returnCode = await session.getReturnCode();

    if (!ReturnCode.isSuccess(returnCode)) {
      final log = await session.getOutput();
      // Clean up any partial output file; ignore cleanup failures.
      try {
        final out = File(outputPath);
        if (out.existsSync()) out.deleteSync();
      } catch (_) {}
      throw ClipTrimException('FFmpeg failed (rc=$returnCode): $log');
    }

    final sizeBytes = File(outputPath).lengthSync();
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
