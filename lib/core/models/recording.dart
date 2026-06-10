class RecordingMetadata {
  const RecordingMetadata({
    required this.id,
    required this.durationSeconds,
    required this.sizeBytes,
    required this.startedAt,
    required this.sport,
    required this.teams,
    this.isRaw = false,
    this.cameraIndex,
    this.captureGroupId,
  });

  final String id;
  final int durationSeconds;
  final int sizeBytes;
  final DateTime startedAt;
  final String sport;
  final String teams;

  /// Raw dual-camera capture identity (proto joint invariant). For a raw file
  /// [isRaw] is true and [cameraIndex] + [captureGroupId] are both present; for
  /// a final recording [isRaw] is false and the other two are null.
  final bool isRaw;
  final int? cameraIndex;
  final String? captureGroupId;
}

class DownloadToken {
  const DownloadToken({
    required this.recordingId,
    required this.httpUrl,
    required this.authToken,
    required this.expiresAt,
  });

  final String recordingId;
  final String httpUrl;
  final String authToken;
  final DateTime expiresAt;

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}
