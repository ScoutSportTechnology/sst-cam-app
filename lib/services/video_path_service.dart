import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Provides canonical, platform-appropriate paths for video files.
///
/// All recordings and clips are stored under the app-private support
/// directory so they are never exposed to the system file picker and
/// are excluded from iCloud / Google Drive backups.
class VideoPathService {
  /// Returns the path for a downloaded full-match recording.
  /// Creates the `videos/` subdirectory if it does not exist.
  Future<String> recordingPath(String recordingId) async {
    final dir = await _videosDir();
    return p.join(dir.path, '$recordingId.mp4');
  }

  /// Returns the path for a highlight clip derived from [recordingId].
  /// [startSeconds] is encoded in the filename to make clips identifiable.
  Future<String> clipPath(String recordingId, int startSeconds) async {
    final dir = await _videosDir();
    return p.join(dir.path, '${recordingId}_clip_$startSeconds.mp4');
  }

  Future<Directory> _videosDir() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.path, 'videos'));
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    return dir;
  }
}
