// Dart-side command types — map 1:1 to proto Command.payload variants.
// RealBleService translates these to/from protobuf bytes on the wire.

import 'network_config.dart';
import 'overlay_layout.dart';
import 'preview_layout.dart';
import 'video_mode.dart';

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
  const DeviceInfoResponse({
    required this.deviceId,
    this.name = '',
    this.firmwareVersion = '',
    this.model = '',
    this.protocolVersion = 0,
    this.supportedModes = const [],
  });
  final String deviceId;
  final String name;
  final String firmwareVersion;
  final String model;

  /// Firmware's reported wire-contract version. The app compares this against
  /// [kAppProtocolVersion]; a mismatch is a version-skew error.
  final int protocolVersion;

  /// The record/stream capture modes the firmware actually supports. The setup
  /// screen offers only these (R16). Empty on firmware that predates the field
  /// (the quality pickers then render disabled).
  final List<VideoMode> supportedModes;
}

/// The wire-contract version this app build implements. Compared against
/// [DeviceInfoResponse.protocolVersion] on connect; a mismatch must surface a
/// clean version-skew signal and refuse the session (see proto contract
/// DeviceInfoResponse.protocol_version comment).
///
/// v3: proto U6 (RebootCommand + record/stream quality + supported_modes).
/// Bumped with the firmware (device.handler kProtocolVersion) as a coordinated
/// release — a connected camera is therefore always exactly this version, so
/// the Reboot action gates on connection alone.
const int kAppProtocolVersion = 3;

// Device
class GetDeviceInfoCommand extends BleCommand {}

// Reboot the camera (U7/U11). Parameterless; gated on protocol_version >= 3.
class RebootCommand extends BleCommand {}

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

// WiFi Direct — app requests firmware to start a WiFi Direct group and return
// the group credentials (SSID, PSK, IPs, ports). No fields — firmware derives
// the group parameters itself.
class StartWifiDirectCommand extends BleCommand {}

// WiFi Direct — app instructs firmware to tear down the active P2P group.
class StopWifiDirectCommand extends BleCommand {}

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
    this.teamAId,
    this.teamBId,
    this.teamAName,
    this.teamBName,
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

  /// Absolute path on the camera where video files will be written, under the
  /// firmware's provisioned storage root, e.g.
  /// `/var/lib/sst/cam/videos/{userUuid}/{matchUuid}/`.
  final String videoOutputPath;

  /// Absolute path on the camera where thumbnail files will be written, e.g.
  /// `/var/lib/sst/cam/thumbnails/{userUuid}/{matchUuid}/`.
  final String thumbnailOutputPath;

  /// Stable id of team A (home), e.g. the local DB team UUID. Optional —
  /// null when no team record is associated.
  final String? teamAId;

  /// Stable id of team B (away/opponent). Optional — opponents are often a
  /// free-text label with no associated team record, in which case this is null.
  final String? teamBId;

  /// Display name of team A (home), used for overlay BINDING_TEAM_A_NAME.
  final String? teamAName;

  /// Display name of team B (away/opponent), used for overlay
  /// BINDING_TEAM_B_NAME.
  final String? teamBName;

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
  RecordingControlCommand({
    required this.action,
    this.quality,
    this.captureGroupId,
  });
  final RecordingControlAction action;

  /// Record resolution/fps, applied by firmware at session start (independent of
  /// the stream quality). Null => firmware default. Only meaningful on a start.
  final VideoMode? quality;

  /// App-minted pairing key sent on START. Couples the always-on dual-camera
  /// training proxy to this match record (firmware starts the per-camera proxy
  /// and stamps the proxy files with this id). Null => record with no proxy.
  /// Must be null on STOP.
  final String? captureGroupId;
}

/// Independent raw dual-camera capture, distinct from [RecordingControlCommand].
/// Only start/stop are honored by firmware. The app MINTS [captureGroupId] and
/// sends it on start (the stop response is status-only, so this is the only way
/// the app can reliably pair the two per-camera files).
class RawCaptureControlCommand extends BleCommand {
  RawCaptureControlCommand({required this.action, this.captureGroupId});
  final RecordingControlAction action;
  final String? captureGroupId;
}

class StreamingControlCommand extends BleCommand {
  StreamingControlCommand({required this.action, this.rtmpUrl, this.quality});
  final StreamingControlAction action;
  final String? rtmpUrl;

  /// Stream resolution/fps, applied by firmware at stream start (independent of
  /// the record quality — e.g. record 1080p while streaming 720p). Null =>
  /// firmware default. Only meaningful on a start.
  final VideoMode? quality;
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

/// Switch the live preview composition between single-camera (overlay baked in)
/// and side-by-side dual-camera (clean). Replies with [PreviewLayoutResult].
class SetPreviewLayoutCommand extends BleCommand {
  SetPreviewLayoutCommand({required this.layout});
  final PreviewLayout layout;
}

/// Request an on-demand overlayed burn of a clean recording (#6 A6c). Replies
/// with an [ExportJob] in the PENDING state; poll it with [PollExportCommand].
class ExportOverlayedCommand extends BleCommand {
  ExportOverlayedCommand({required this.recordingId});
  final String recordingId;
}

/// Poll a running overlayed-export job. Replies with the job's current
/// [ExportJob] state (READY carries the L2 download token).
class PollExportCommand extends BleCommand {
  PollExportCommand({required this.jobId});
  final String jobId;
}

/// Set the camera's internet uplink config (ethernet / wifi STA) — persisted +
/// applied by the firmware. Replies with [NetworkConfigResult] (echoed config +
/// live status).
class SetNetworkConfigCommand extends BleCommand {
  SetNetworkConfigCommand({required this.config});
  final NetworkConfig config;
}

/// Read the camera's current uplink config + live status. Replies with
/// [NetworkConfigResult].
class GetNetworkConfigCommand extends BleCommand {}

// ---------------------------------------------------------------------------

enum BleResponseStatus { ok, error, timeout, unsupported, liveSessionActive }

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

  /// The firmware refused the command because a match is live
  /// (`ResponseStatus.LIVE_SESSION_ACTIVE`). Distinct from a generic error so
  /// callers can surface the "end the match first" guidance off the typed
  /// status rather than substring-matching the firmware's human message.
  bool get isLiveSessionActive => status == BleResponseStatus.liveSessionActive;

  /// The firmware does not implement this command (`ResponseStatus.UNSUPPORTED`)
  /// — typically a camera running firmware older than the one that introduced
  /// the command. Distinct from a generic error so callers can surface
  /// actionable "update the camera firmware" guidance.
  bool get isUnsupported => status == BleResponseStatus.unsupported;

  factory BleCommandResponse.ok([T? payload]) =>
      BleCommandResponse(status: BleResponseStatus.ok, payload: payload);

  factory BleCommandResponse.error(String message) => BleCommandResponse(
    status: BleResponseStatus.error,
    errorMessage: message,
  );

  factory BleCommandResponse.liveSessionActive(String message) =>
      BleCommandResponse(
        status: BleResponseStatus.liveSessionActive,
        errorMessage: message,
      );

  factory BleCommandResponse.timeout() =>
      BleCommandResponse(status: BleResponseStatus.timeout);
}
