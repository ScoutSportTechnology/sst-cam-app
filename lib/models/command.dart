// Dart-side command types — map 1:1 to proto Command.payload variants.
// RealBleService translates these to/from protobuf bytes on the wire.

sealed class BleCommand {}

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

// Match control
class MatchConfigCommand extends BleCommand {
  MatchConfigCommand(this.config);
  final dynamic config; // models/match.dart MatchConfig
}

class MatchControlCommand extends BleCommand {
  MatchControlCommand(this.action);
  final dynamic action; // models/match.dart MatchControlAction
}

class ScoreUpdateCommand extends BleCommand {
  ScoreUpdateCommand({required this.teamId, required this.delta});
  final String teamId;
  final int delta;
}

class BannerEventCommand extends BleCommand {
  BannerEventCommand(this.event);
  final dynamic event; // models/match.dart BannerEvent
}

// Recording / streaming
class StartRecordingCommand extends BleCommand {}

class StopRecordingCommand extends BleCommand {}

class StartStreamingCommand extends BleCommand {
  StartStreamingCommand({required this.rtmpUrl});
  final String rtmpUrl;
}

class StopStreamingCommand extends BleCommand {}

class ListRecordingsCommand extends BleCommand {}

class DownloadRequestCommand extends BleCommand {
  DownloadRequestCommand({required this.recordingId});
  final String recordingId;
}

// Configuration
class SetWifiConfigCommand extends BleCommand {
  SetWifiConfigCommand({required this.ssid, required this.password});
  final String ssid;
  final String password;
}

class SetStreamingConfigCommand extends BleCommand {
  SetStreamingConfigCommand({
    this.youtubeStreamKey,
    this.instagramStreamKey,
    this.customRtmpUrl,
  });
  final String? youtubeStreamKey;
  final String? instagramStreamKey;
  final String? customRtmpUrl;
}

class FactoryResetCommand extends BleCommand {}

class FirmwareUpdateCommand extends BleCommand {}

// Session config — sent once before recording starts (U9)
class PushSessionConfigCommand extends BleCommand {
  PushSessionConfigCommand(this.config);
  final PushSessionConfig config;
}

// ---------------------------------------------------------------------------
// Session configuration payload pushed to the camera before a match starts.
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
