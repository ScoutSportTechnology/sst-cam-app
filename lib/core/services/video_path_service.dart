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

  /// Returns the path for the on-demand overlaid render (L2, #6 A6c) of a
  /// recording — kept distinct from the clean L1 [recordingPath] so a burn
  /// never clobbers the clean master.
  Future<String> overlayRecordingPath(String recordingId) async {
    final dir = await _videosDir();
    return p.join(dir.path, '${recordingId}_overlay.mp4');
  }

  /// Returns the path for a highlight clip.
  /// [clipId] is included to guarantee uniqueness when multiple clips share
  /// the same [recordingId] and [startSeconds].
  Future<String> clipPath(String recordingId, String clipId) async {
    final dir = await _videosDir();
    return p.join(dir.path, '${recordingId}_clip_$clipId.mp4');
  }

  /// Returns the local cache path for a recording's thumbnail (the camera's
  /// `<matchId>.jpg`). The file may not exist yet — callers fetch it once over
  /// WiFi and cache it here for offline display.
  Future<String> thumbnailPath(String recordingId) async {
    final dir = await _thumbnailsDir();
    return p.join(dir.path, '$recordingId.jpg');
  }

  Future<Directory> _videosDir() => _subdir('videos');
  Future<Directory> _thumbnailsDir() => _subdir('thumbnails');

  Future<Directory> _subdir(String name) async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.path, name));
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    return dir;
  }
}
