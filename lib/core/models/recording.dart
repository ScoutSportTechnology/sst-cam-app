class RecordingMetadata {
  const RecordingMetadata({
    required this.id,
    required this.durationSeconds,
    required this.sizeBytes,
    required this.startedAt,
    required this.sport,
    required this.teams,
  });

  final String id;
  final int durationSeconds;
  final int sizeBytes;
  final DateTime startedAt;
  final String sport;
  final String teams;
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
