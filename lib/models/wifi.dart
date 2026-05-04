/// State of the WiFi Direct group between the phone and the camera.
/// Independent of [CameraConnectionState] — the BLE link can be live while
/// WiFi Direct is still idle, and vice versa during teardown.
enum WifiDirectState { idle, starting, connected, failed, stopping }

/// Credentials and addresses for a WiFi Direct group hosted by the camera.
/// Returned by the firmware in response to `StartWifiDirectCommand`.
class WifiDirectGroup {
  const WifiDirectGroup({
    required this.ssid,
    required this.psk,
    required this.groupOwnerIp,
    required this.previewPort,
    required this.downloadPort,
    required this.role,
  });

  final String ssid;
  final String psk;
  final String groupOwnerIp;
  final int previewPort;
  final int downloadPort;
  final String role;

  /// RTSP H.264 preview URL derived from the group descriptor.
  String previewUrl({String path = '/preview'}) =>
      'rtsp://$groupOwnerIp:$previewPort$path';

  /// Base URL for HTTP recording downloads.
  String downloadBaseUrl() => 'http://$groupOwnerIp:$downloadPort';
}

enum PreviewCodec { unknown, rtspH264 }

class PreviewStreamDescriptor {
  const PreviewStreamDescriptor({
    required this.url,
    required this.codec,
    required this.width,
    required this.height,
    required this.fps,
    required this.bitrateKbps,
  });

  final String url;
  final PreviewCodec codec;
  final int width;
  final int height;
  final int fps;
  final int bitrateKbps;
}

/// Heartbeat tick from the preview pipeline. Pixel data lives inside the
/// VLC player; this just carries a sequence number + timestamp so other UI
/// surfaces (badge, frame counter) have a "frames flowing" signal.
class PreviewFrame {
  const PreviewFrame({required this.sequence, required this.capturedAt});

  final int sequence;
  final DateTime capturedAt;
}

/// Rolling stats for the preview stream — useful in diagnostics and the
/// "live" badge on the preview surface.
class PreviewStats {
  const PreviewStats({
    required this.fps,
    required this.kbps,
    required this.latencyMs,
    required this.framesReceived,
    required this.framesDropped,
  });

  final double fps;
  final double kbps;
  final int latencyMs;
  final int framesReceived;
  final int framesDropped;

  static const zero = PreviewStats(
    fps: 0,
    kbps: 0,
    latencyMs: 0,
    framesReceived: 0,
    framesDropped: 0,
  );
}

/// Lifecycle of an in-flight recording download.
enum DownloadStatus { queued, running, paused, completed, failed, cancelled }

class VideoDownloadProgress {
  const VideoDownloadProgress({
    required this.downloadId,
    required this.recordingId,
    required this.status,
    required this.bytesReceived,
    required this.bytesTotal,
    required this.kbps,
    this.errorMessage,
  });

  final String downloadId;
  final String recordingId;
  final DownloadStatus status;
  final int bytesReceived;
  final int bytesTotal;
  final double kbps;
  final String? errorMessage;

  double get fraction => bytesTotal == 0 ? 0 : bytesReceived / bytesTotal;
  bool get isTerminal =>
      status == DownloadStatus.completed ||
      status == DownloadStatus.failed ||
      status == DownloadStatus.cancelled;
}

/// Handle returned by `WifiService.startDownload`. The progress stream emits
/// updates until the download reaches a terminal state, after which it
/// completes. Call [cancel] to abort early.
class VideoDownloadHandle {
  const VideoDownloadHandle({
    required this.downloadId,
    required this.recordingId,
    required this.savePath,
    required this.progress,
    required this.cancel,
  });

  final String downloadId;
  final String recordingId;
  final String savePath;
  final Stream<VideoDownloadProgress> progress;
  final Future<void> Function() cancel;
}

class WifiDirectException implements Exception {
  const WifiDirectException(this.message);
  final String message;

  @override
  String toString() => 'WifiDirectException: $message';
}
