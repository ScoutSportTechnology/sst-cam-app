import '../models/command.dart';
import '../models/device.dart';
import '../models/match.dart';
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

  /// Whether a scan is currently active.
  bool get isScanning;

  /// Emits the accumulated list of discovered devices (grows during a scan).
  Stream<List<ScoutDevice>> get discoveredDevices;

  /// Starts a BLE scan. Completes when the scan timer fires or [stopScan] is
  /// called. Safe to call when already scanning (no-op).
  Future<void> startScan({Duration timeout = const Duration(seconds: 10)});

  /// Stops an active scan. Safe to call when not scanning.
  Future<void> stopScan();

  // ---------------------------------------------------------------------------
  // Connection
  // ---------------------------------------------------------------------------

  /// Attempt to connect to [deviceId]. Resolves when connected or throws on
  /// failure. Subscribe to [connectionStateStream] to track subsequent changes.
  Future<void> connect(String deviceId);

  /// Disconnect from [deviceId]. No-op if not connected.
  Future<void> disconnect(String deviceId);

  /// Live connection state for [deviceId].
  Stream<CameraConnectionState> connectionStateStream(String deviceId);

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
