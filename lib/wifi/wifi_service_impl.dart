import 'dart:async';

import '../models/recording.dart';
import '../models/wifi.dart';
import 'wifi_service.dart';

/// Real WiFi Direct implementation.
///
/// Pending firmware wiring:
///   * platform channels for WiFi Direct group negotiation
///     (Android: WifiP2pManager; iOS: NEHotspotConfiguration + Multipeer).
///     Group credentials are received over BLE in `WifiDirectGroupResponse`
///     (see proto/wifi.proto) — the handshake is not duplicated here.
///   * RTSP H.264 playback via `flutter_vlc_player` driven by
///     [previewDescriptor]; the heartbeat stream is generated locally on
///     keyframe arrival so the UI's liveness badge has a tick source.
///   * a chunked HTTP download client for `startDownload`, with byte-range
///     resume support against the Jetson's recording HTTP server.
class WifiServiceImpl implements WifiService {
  @override
  Future<WifiDirectGroup> connectGroup(String deviceId) {
    throw UnimplementedError(
      'TODO: wire to firmware — WiFi Direct group negotiation not yet implemented',
    );
  }

  @override
  Future<void> disconnectGroup(String deviceId) async {
    throw UnimplementedError(
      'TODO: wire to firmware — disconnectGroup not yet implemented',
    );
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
      'TODO: wire to firmware — HTTP recording download not yet implemented',
    );
  }

  @override
  List<VideoDownloadProgress> activeDownloads() => const [];

  @override
  Stream<VideoDownloadProgress> allDownloadProgress() => const Stream.empty();

  @override
  Future<void> dispose() async {}
}
