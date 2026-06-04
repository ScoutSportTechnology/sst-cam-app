// Dart-side command types — map 1:1 to proto Command.payload variants.
// RealBleService translates these to/from protobuf bytes on the wire.

import 'overlay_layout.dart';

sealed class BleCommand {}

// ---------------------------------------------------------------------------
// Response payloads returned via BleCommandResponse<T>
// ---------------------------------------------------------------------------

/// Response payload for [GetDeviceInfoCommand].
///
/// NOTE: [deviceId] is assumed to be a stable hardware UUID, but this has
/// not been confirmed with firmware. If the firmware returns an advertising
/// ID instead, the restore UUID-check in BackupService.import() will need
/// updating. See U10/U11 plan notes.
class DeviceInfoResponse {
  const DeviceInfoResponse({required this.deviceId});
  final String deviceId;
}

// Device
class GetDeviceInfoCommand extends BleCommand {}

// Telemetry — app polls at ~1 Hz
class GetTelemetryCommand extends BleCommand {}

// Match state — app polls ~0.5 Hz
class GetMatchStateCommand extends BleCommand {}

// Thumbnail
class RequestThumbnailCommand extends BleCommand {
  RequestThumbnailCommand({
    this.width = 160,
    this.height = 90,
    this.quality = 60,
  });
  final int width;
  final int height;
  final int quality;
}

// Recording / file transfer
class ListRecordingsCommand extends BleCommand {}

class DownloadRequestCommand extends BleCommand {
  DownloadRequestCommand({required this.recordingId});
  final String recordingId;
}

// ---------------------------------------------------------------------------
// Session configuration payload pushed to the camera before a match starts.
// Sent via BleService.pushSessionConfig() — not routed through sendCommand().
// Fix 14: PushSessionConfigCommand has been removed from the sealed hierarchy
// because the dedicated pushSessionConfig() method on BleService is the
// correct API.
// ---------------------------------------------------------------------------

class PushSessionConfig {
  const PushSessionConfig({
    required this.matchUuid,
    required this.userUuid,
    required this.sport,
    required this.numPeriods,
    required this.periodLengthSeconds,
    this.rtmpUrl,
    this.streamKey,
    required this.videoOutputPath,
    required this.thumbnailOutputPath,
    this.teamAColorHex,
    this.teamBColorHex,
  });

  final String matchUuid;
  final String userUuid;

  /// Sport as a lowercase string, e.g. 'soccer'.
  final String sport;

  final int numPeriods;
  final int periodLengthSeconds;

  /// Full RTMP URL including stream key (optional — null means no streaming).
  final String? rtmpUrl;

  /// Stream key extracted separately when the RTMP URL does not embed it
  /// (optional). May be null even when [rtmpUrl] is provided.
  final String? streamKey;

  /// Absolute path on the camera where video files will be written, e.g.
  /// `/data/video/{userUuid}/{matchUuid}/`.
  final String videoOutputPath;

  /// Absolute path on the camera where thumbnail files will be written, e.g.
  /// `/data/thumbnail/{userUuid}/{matchUuid}/`.
  final String thumbnailOutputPath;

  /// Hex colour for team A overlay elements, e.g. '#FF5733'.
  final String? teamAColorHex;

  /// Hex colour for team B overlay elements, e.g. '#33A1FF'.
  final String? teamBColorHex;
}

// ---------------------------------------------------------------------------
// Enums
// ---------------------------------------------------------------------------

enum RecordingControlAction { start, stop, pause, resume }

enum StreamingControlAction { start, stop }

enum BleMatchControlAction {
  kickoff,
  periodEnd,
  periodStart,
  finalWhistle,
  clockPause,
  clockResume,
}

// ---------------------------------------------------------------------------
// Control commands
// ---------------------------------------------------------------------------

class RecordingControlCommand extends BleCommand {
  RecordingControlCommand({required this.action});
  final RecordingControlAction action;
}

class StreamingControlCommand extends BleCommand {
  StreamingControlCommand({required this.action, this.rtmpUrl});
  final StreamingControlAction action;
  final String? rtmpUrl;
}

class MatchControlCommand extends BleCommand {
  MatchControlCommand({required this.action, required this.period});
  final BleMatchControlAction action;
  final int period;
}

class ScoreUpdateCommand extends BleCommand {
  ScoreUpdateCommand({required this.teamId, required this.delta});
  final String teamId;
  final int delta;
}

class BannerEventCommand extends BleCommand {
  BannerEventCommand({
    required this.templateId,
    this.params = const {},
    required this.durationSeconds,
    this.playerId,
  });
  final String templateId;
  final Map<String, String> params;
  final int durationSeconds;
  final String? playerId;
}

class PushOverlayLayoutCommand extends BleCommand {
  PushOverlayLayoutCommand({required this.layout});
  final OverlayLayout layout;
}

// ---------------------------------------------------------------------------

enum BleResponseStatus { ok, error, timeout, unsupported }

class BleCommandResponse<T> {
  const BleCommandResponse({
    required this.status,
    this.payload,
    this.errorMessage,
  });

  final BleResponseStatus status;
  final T? payload;
  final String? errorMessage;

  bool get isOk => status == BleResponseStatus.ok;

  factory BleCommandResponse.ok([T? payload]) =>
      BleCommandResponse(status: BleResponseStatus.ok, payload: payload);

  factory BleCommandResponse.error(String message) => BleCommandResponse(
    status: BleResponseStatus.error,
    errorMessage: message,
  );

  factory BleCommandResponse.timeout() =>
      BleCommandResponse(status: BleResponseStatus.timeout);
}
