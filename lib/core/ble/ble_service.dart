import '../models/command.dart';
import '../models/device.dart';
import '../models/match.dart';
import '../models/network_config.dart';
import '../models/export_job.dart';
import '../models/overlay_layout.dart';
import '../models/preview_layout.dart';
import '../models/recording.dart';
import '../models/telemetry.dart';

/// Abstract BLE interface. Injected via Riverpod so the real and mock
/// implementations are fully swappable without touching UI code.
///
/// All streams are broadcast streams — multiple listeners are supported.
/// Streams for a given [deviceId] are created on demand and cleaned up
/// on [dispose].
abstract class BleService {
  // ---------------------------------------------------------------------------
  // Discovery
  // ---------------------------------------------------------------------------

  /// Whether the host Bluetooth adapter is on. Emits the current state
  /// immediately, then updates as the user toggles Bluetooth. Concrete default
  /// emits a single `true` — the mock/fakes have no real adapter to be "off".
  Stream<bool> get bluetoothOn => Stream.value(true);

  /// Ask the OS to enable Bluetooth (Android shows the system enable prompt).
  /// No-op where unsupported, already on, or the user declines. Concrete default
  /// is a no-op so fakes need not implement it.
  Future<void> requestBluetoothOn() async {}

  /// Whether a scan is currently active.
  bool get isScanning;

  /// Emits the accumulated list of discovered devices (grows during a scan).
  Stream<List<SstDevice>> get discoveredDevices;

  /// Starts a BLE scan. Completes when the scan timer fires or [stopScan] is
  /// called. Safe to call when already scanning (no-op).
  Future<void> startScan({Duration timeout = const Duration(seconds: 10)});

  /// Stops an active scan. Safe to call when not scanning.
  Future<void> stopScan();

  // ---------------------------------------------------------------------------
  // Connection
  // ---------------------------------------------------------------------------

  /// Establish the wire link to [deviceId]: BLE connect + MTU + service
  /// discovery + notify subscription. Resolves with the connection state at
  /// [CameraConnectionState.reconciling] — NOT `connected`. The connect
  /// controller (core/state/connect_controller.dart, the port's ONLY caller)
  /// then runs the §9b handshake (protocol gate → time push → snapshot →
  /// rehydrate → reconcile) and calls [completeHandshake] to reach
  /// `connected`. Throws on link failure. Subscribe to
  /// [connectionStateStream] to track subsequent changes.
  Future<void> connect(String deviceId);

  /// Transition [deviceId] from `reconciling` to `connected` and start the
  /// telemetry / match-state pollers. Called by the connect controller once
  /// the handshake has fully completed — pollers must never run mid-handshake
  /// (a match-state poll landing there would mutate live state before the
  /// snapshot restore reads it). No-op unless the device is `reconciling`.
  void completeHandshake(String deviceId) {}

  /// Disconnect from [deviceId]. No-op if not connected.
  Future<void> disconnect(String deviceId);

  /// Live connection state for [deviceId].
  Stream<CameraConnectionState> connectionStateStream(String deviceId);

  /// The connected camera's real DeviceInfo (firmware version, wire
  /// protocol_version, model). Fetched on demand post-connect — the scan-time
  /// [SstDevice] carries empty firmware/0 protocol. Returns null when unreachable.
  /// Concrete default so existing fakes don't need to implement it.
  Future<DeviceInfoResponse?> getDeviceInfo(String deviceId) async => null;

  // ---------------------------------------------------------------------------
  // Telemetry (pushed by firmware ~1 Hz after connect)
  // ---------------------------------------------------------------------------

  Stream<DeviceTelemetry> telemetryStream(String deviceId);

  // ---------------------------------------------------------------------------
  // Camera preview (still polling — not video)
  // ---------------------------------------------------------------------------

  /// Request a JPEG thumbnail from the camera. May take several seconds over
  /// BLE due to chunking. Throws [BleTimeoutException] on timeout.
  Future<ThumbnailResult> requestThumbnail(
    String deviceId, {
    int width = 160,
    int height = 90,
    int quality = 60,
  });

  // ---------------------------------------------------------------------------
  // Generic command channel
  // ---------------------------------------------------------------------------

  /// Send any [BleCommand] and await the [BleCommandResponse].
  /// The implementation handles correlation IDs and chunking internally.
  Future<BleCommandResponse<T>> sendCommand<T>(
    String deviceId,
    BleCommand command,
  );

  // ---------------------------------------------------------------------------
  // Match state (pushed by firmware on state changes)
  // ---------------------------------------------------------------------------

  Stream<MatchState> matchStateStream(String deviceId);

  // ---------------------------------------------------------------------------
  // Recordings
  // ---------------------------------------------------------------------------

  Future<List<RecordingMetadata>> listRecordings(String deviceId);

  Future<DownloadToken> requestDownload(String deviceId, String recordingId);

  // ---------------------------------------------------------------------------
  // Session push (U9)
  // ---------------------------------------------------------------------------

  /// Push session configuration to the camera before a match starts.
  /// Must be called and awaited successfully before calling any recording /
  /// period-control commands. On failure the camera has no session context
  /// and the UI must stay on the setup screen.
  Future<void> pushSessionConfig(String deviceId, PushSessionConfig config);

  /// Push overlay layout to the camera at session start.
  Future<void> pushOverlayLayout(String deviceId, OverlayLayout layout);

  /// Switch the live preview composition (#6 A6b) between single-camera
  /// (overlay baked in) and side-by-side dual-camera (clean). Returns the
  /// now-active layout plus the composited frame geometry so the caller can
  /// size its preview box. The RTSP URL/port are unchanged across a switch.
  Future<PreviewLayoutResult> setPreviewLayout(
    String deviceId,
    PreviewLayout layout,
  );

  /// Apply live per-channel white-balance gains to the camera's postprocessor
  /// (diagnostic Calibration → Camera sliders, to neutralize the IMX477 magenta
  /// cast). Fire-and-forget: the correction takes effect on the next preview
  /// frame. Gains multiply the BGR channels (1.0 = identity); [enabled] false
  /// bypasses correction.
  Future<void> setCameraCalibration(
    String deviceId, {
    required double rGain,
    required double gGain,
    required double bGain,
    bool enabled,
    double saturation,
    double contrast,
    double brightness,
  });

  /// One-shot auto white-balance: the firmware measures the current frame (point
  /// the camera at a white/grey surface) and computes the neutralizing gains,
  /// applies them live, and returns them so the UI can seed its sliders. Null if
  /// the firmware couldn't measure (too dark / no frame).
  Future<CameraCalibrationResult?> autoWhiteBalance(String deviceId);

  /// Motorized-focus control (ArduCAM VCM). [mode] auto = continuous autofocus
  /// (firmware pauses it while recording — this cycle's default); manual holds
  /// [position] (0–1000 VCM code). [cameraIndex] null = both cameras.
  /// Returns the firmware's echo: the EFFECTIVE mode/position now applied
  /// (observed — may differ from the request) plus
  /// [CameraFocusResult.autofocusAvailable] (false = fixed lens). Null when the
  /// firmware omitted the payload.
  Future<CameraFocusResult?> setCameraFocus(
    String deviceId, {
    required CameraFocusMode mode,
    int? position,
    int? cameraIndex,
  });

  /// Manual tracking — pick which camera (0/1) feeds the record/stream/preview
  /// output. The human override of the future AI camera decision.
  Future<void> setActiveCamera(String deviceId, int cameraIndex);

  /// Request an on-demand overlayed burn (#6 A6c) of the clean recording
  /// [recordingId]. Returns an [ExportJob] in the PENDING state; poll it with
  /// [pollOverlayExport]. Throws on a `LIVE_SESSION_ACTIVE` rejection (a burn
  /// must never contend with the live broadcast encode).
  Future<ExportJob> requestOverlayExport(String deviceId, String recordingId);

  /// Poll a running overlayed-export job. The READY result carries the L2
  /// [DownloadToken]; FAILED carries an error message. The burned L2 persists
  /// in the match folder on the camera (it also shows up in listRecordings),
  /// so re-exporting an already-burned recording succeeds fast — the firmware
  /// returns the existing file.
  Future<ExportJob> pollOverlayExport(String deviceId, String jobId);

  /// Set the camera's internet uplink config (ethernet / wifi STA) — the
  /// cloud-streaming path, separate from the WiFi-Direct preview link. The
  /// firmware persists + applies it and replies with the echoed config + live
  /// per-interface status.
  Future<NetworkConfigResult> setNetworkConfig(
    String deviceId,
    NetworkConfig config,
  );

  /// Read the camera's current uplink config + live status.
  Future<NetworkConfigResult> getNetworkConfig(String deviceId);

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  Future<void> dispose();
}

class BleTimeoutException implements Exception {
  const BleTimeoutException(this.message);
  final String message;

  @override
  String toString() => 'BleTimeoutException: $message';
}

class BleConnectionException implements Exception {
  const BleConnectionException(this.message);
  final String message;

  @override
  String toString() => 'BleConnectionException: $message';
}

/// Raised when the camera's firmware does not implement a NetworkConfig
/// command (it answered `ResponseStatus.UNSUPPORTED`). The command surface is
/// additive, so an older firmware predating it has no way to honour the request
/// — callers surface "update the camera firmware" rather than a generic error.
class BleNetworkConfigUnsupportedException implements Exception {
  const BleNetworkConfigUnsupportedException([this.message]);
  final String? message;

  @override
  String toString() =>
      'BleNetworkConfigUnsupportedException: ${message ?? 'firmware too old'}';
}

/// Raised when the post-connect handshake (device-info read, time push,
/// session-snapshot read, or reconcile push) fails or times out. The connect
/// controller drops the BLE link before surfacing this, so the app never sits
/// in a half-hydrated state. Distinct from [BleConnectionException] (link
/// establishment) so call sites can word the failure accurately.
class BleHandshakeException implements Exception {
  const BleHandshakeException(this.message);
  final String message;

  @override
  String toString() => 'BleHandshakeException: $message';
}

/// Raised when the firmware's reported `protocol_version` does not match the
/// version this app build was compiled against. The session must be refused —
/// the wire contract may have diverged in incompatible ways.
class BleProtocolVersionException implements Exception {
  const BleProtocolVersionException({
    required this.expected,
    required this.actual,
  });
  final int expected;
  final int actual;

  @override
  String toString() =>
      'BleProtocolVersionException: firmware protocol_version $actual does not '
      'match app version $expected';
}
