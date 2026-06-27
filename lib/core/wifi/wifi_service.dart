import '../models/overlay.dart';
import '../models/recording.dart';
import '../models/wifi.dart';

/// Abstract WiFi Direct interface — the only WiFi surface the UI touches.
/// The real and mock implementations are fully swappable via Riverpod, in
/// the same pattern as `BleService`.
///
/// Channel split:
///   * BLE     — control / commands / telemetry / match state (see BleService)
///   * WiFi    — bulk data: low-res live preview, recording downloads.
///
/// Pairing always starts on BLE: the app sends `StartWifiDirectCommand`,
/// the firmware replies with a `WifiDirectGroupResponse`, and the app then
/// joins that group on the WiFi side. From the UI's perspective, that whole
/// dance is hidden behind [connectGroup].
abstract class WifiService {
  // ---------------------------------------------------------------------------
  // Group lifecycle
  // ---------------------------------------------------------------------------

  /// Negotiate and join a WiFi Direct group with [deviceId]. Throws
  /// [WifiDirectException] on failure. Subscribe to [connectionStateStream]
  /// to track subsequent state changes.
  Future<WifiDirectGroup> connectGroup(String deviceId);

  /// Tear down the WiFi Direct group. Safe to call when not connected.
  Future<void> disconnectGroup(String deviceId);

  /// The active group descriptor for [deviceId], if any.
  WifiDirectGroup? currentGroup(String deviceId);

  /// Broadcast stream of WiFi Direct state for [deviceId].
  Stream<WifiDirectState> connectionStateStream(String deviceId);

  // ---------------------------------------------------------------------------
  // Live preview
  // ---------------------------------------------------------------------------

  /// Returns the descriptor for the preview stream the camera is currently
  /// publishing. Available once the group is connected.
  PreviewStreamDescriptor? previewDescriptor(String deviceId);

  /// Frames decoded from the MJPEG preview stream. Hot-broadcast — listeners
  /// joining mid-stream get the next frame, not historical ones.
  Stream<PreviewFrame> previewFrames(String deviceId);

  /// Rolling stats for the preview stream (fps, kbps, latency).
  Stream<PreviewStats> previewStats(String deviceId);

  // ---------------------------------------------------------------------------
  // Downloads
  // ---------------------------------------------------------------------------

  /// Start downloading a recording over the WiFi link, using the
  /// [DownloadToken] previously obtained from the BLE side. The returned
  /// [VideoDownloadHandle] exposes progress and a cancel hook.
  Future<VideoDownloadHandle> startDownload(
    String deviceId,
    DownloadToken token, {
    String? saveAs,
  });

  /// Snapshot of all in-flight or recently completed downloads, keyed by
  /// download id. Useful for a "downloads" page or status tray.
  List<VideoDownloadProgress> activeDownloads();

  /// Broadcast stream of progress events across all downloads. Use this when
  /// a UI surface needs to react to any download progressing (e.g. a global
  /// progress bar).
  Stream<VideoDownloadProgress> allDownloadProgress();

  // ---------------------------------------------------------------------------
  // Recordings
  // ---------------------------------------------------------------------------

  /// Returns true if the camera has a raw recording identified by [uuid].
  /// [uuid] is the match record's ID — the only identifier used for recordings.
  Future<bool> checkCameraHasRecording(String uuid);

  /// Fetches the camera-rendered thumbnail (`<uuid>.jpg`) for a recording over
  /// the WiFi link and caches it locally. Returns the local file path, or null
  /// when no group is connected or the camera has no such thumbnail. Small,
  /// untokened GET — the recording id is the thumbnail id.
  Future<String?> fetchThumbnail(String deviceId, String uuid);

  /// Downloads the full raw recording for [uuid] from [deviceId].
  /// Returns a [VideoDownloadHandle] with a progress stream and cancel hook,
  /// identical to [startDownload] but addressed by recording UUID rather than
  /// a [DownloadToken].
  Future<VideoDownloadHandle> downloadRecording(String deviceId, String uuid);

  /// Downloads the full recording for [uuid], instructing the camera to burn
  /// the provided [overlays] and [config] onto the output video.
  /// In mock mode the camera ignores overlays and returns the raw recording.
  /// The interface is defined here for firmware to implement later.
  Future<VideoDownloadHandle> downloadRecordingWithOverlays(
    String deviceId,
    String uuid,
    List<OverlayState> overlays,
    OverlayConfig config,
  );

  /// Broadcast stream of the current overlay state at ~1 Hz.
  /// Used by live-match surfaces (Match tab / Live tab).
  /// The video review page does NOT consume this — it derives overlay from DB events.
  Stream<OverlayState> overlayStateStream(String deviceId);

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  Future<void> dispose();
}
