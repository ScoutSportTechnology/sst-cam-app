import 'dart:async';

import '../models/recording.dart';
import '../models/wifi.dart';
import 'wifi_service.dart';

/// Real WiFi Direct implementation.
///
/// Phase 7 will wire this to:
///   * platform channels for WiFi Direct group negotiation
///     (Android: WifiP2pManager; iOS: NEHotspotConfiguration + Multipeer)
///   * an MJPEG client (`dio` streamed response, multipart parser) for the
///     preview channel
///   * a chunked HTTP download client for `startDownload`, with byte-range
///     resume support against the Jetson's recording HTTP server
class WifiServiceImpl implements WifiService {
  @override
  Future<WifiDirectGroup> connectGroup(String deviceId) {
    throw UnimplementedError(
      'Phase 7: WiFi Direct group negotiation not yet implemented',
    );
  }

  @override
  Future<void> disconnectGroup(String deviceId) async {
    throw UnimplementedError('Phase 7: disconnectGroup not yet implemented');
  }

  @override
  WifiDirectGroup? currentGroup(String deviceId) => null;

  @override
  Stream<WifiDirectState> connectionStateStream(String deviceId) =>
      const Stream.empty();

  @override
  PreviewStreamDescriptor? previewDescriptor(String deviceId) => null;

  @override
  Stream<PreviewFrame> previewFrames(String deviceId) => const Stream.empty();

  @override
  Stream<PreviewStats> previewStats(String deviceId) => const Stream.empty();

  @override
  Future<VideoDownloadHandle> startDownload(
    String deviceId,
    DownloadToken token, {
    String? saveAs,
  }) {
    throw UnimplementedError(
      'Phase 7: HTTP recording download not yet implemented',
    );
  }

  @override
  List<VideoDownloadProgress> activeDownloads() => const [];

  @override
  Stream<VideoDownloadProgress> allDownloadProgress() => const Stream.empty();

  @override
  Future<void> dispose() async {}
}
