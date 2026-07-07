// Dart-side command types — map 1:1 to proto Command.payload variants.
// RealBleService translates these to/from protobuf bytes on the wire.

import 'match.dart' show MatchStatus;
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
/// v4: state-health cycle (GetSessionSnapshot / SetMatchState / SetDeviceTime,
/// MatchState 9-11, per-camera health, auto_stop_minutes, DEVICE_INOPERABLE).
/// Bumped with the firmware (device.handler kProtocolVersion) as a coordinated
/// release — a connected camera is therefore always exactly this version, so
/// the Reboot action gates on connection alone.
const int kAppProtocolVersion = 4;

// Device
class GetDeviceInfoCommand extends BleCommand {}

// Reboot the camera (U7/U11). Parameterless; gated on protocol_version >= 3.
class RebootCommand extends BleCommand {}

// Telemetry — app polls at ~1 Hz
class GetTelemetryCommand extends BleCommand {}

// Match state — app polls ~0.5 Hz
class GetMatchStateCommand extends BleCommand {}

// ---------------------------------------------------------------------------
// Connect handshake (state-health cycle, §9b) — sent by the connect
// controller between the protocol gate and the `connected` transition.
// ---------------------------------------------------------------------------

/// Read the firmware's ACTUAL session state (pure read, no side effects).
/// Replies with a [SessionSnapshot] the app rehydrates its providers from —
/// adoption replaces the old reset-to-defaults-on-connect behavior.
class GetSessionSnapshotCommand extends BleCommand {}

/// Absolute match-state overwrite — the reconciliation verb. Every field is
/// optional: null fields are left UNTOUCHED on the firmware (partial set is
/// legal). NOT a replacement for [ScoreUpdateCommand] (live incremental path)
/// — it exists because replaying deltas after a connection gap double-applies.
class SetMatchStateCommand extends BleCommand {
  SetMatchStateCommand({
    this.scoreA,
    this.scoreB,
    this.currentPeriod,
    this.elapsedSeconds,
    this.clockRunning,
    this.status,
  });
  final int? scoreA;
  final int? scoreB;
  final int? currentPeriod;

  /// Monotonic seconds since period start (MatchState.elapsed_seconds
  /// semantics). Normally left null on reconcile — the firmware clock is the
  /// only clock that ran through a disconnect, so it wins.
  final int? elapsedSeconds;
  final bool? clockRunning;
  final MatchStatus? status;
}

/// Phone wall-clock push, sent right after the protocol gate on every connect.
/// Fixes device-LOCAL timestamps only (file mtimes, summary fields, logs);
/// session/match clocks on the wire stay monotonic. Status-only reply; the
/// firmware rejects implausible values (pre-2020 epoch) with ERROR.
class SetDeviceTimeCommand extends BleCommand {
  SetDeviceTimeCommand({required this.epochMs});

  /// Unix epoch milliseconds (phone wall clock).
  final int epochMs;
}

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
    this.autoStopMinutes = kDefaultAutoStopMinutes,
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

  /// Unsupervised-session timeout (R5): the firmware auto-stops the session
  /// after this many minutes with no app connection (wire field
  /// `auto_stop_minutes = 16`). App-configurable (Settings → Auto-stop);
  /// [kDefaultAutoStopMinutes] when the operator never touched the setting.
  final int autoStopMinutes;

  /// The same config with a different [autoStopMinutes] — the mid-session
  /// re-push path (the firmware maps auto_stop_minutes on every
  /// PushSessionConfig, so a changed setting takes effect immediately).
  PushSessionConfig withAutoStopMinutes(int minutes) => PushSessionConfig(
    matchUuid: matchUuid,
    userUuid: userUuid,
    sport: sport,
    numPeriods: numPeriods,
    periodLengthSeconds: periodLengthSeconds,
    rtmpUrl: rtmpUrl,
    streamKey: streamKey,
    videoOutputPath: videoOutputPath,
    thumbnailOutputPath: thumbnailOutputPath,
    teamAId: teamAId,
    teamBId: teamBId,
    teamAName: teamAName,
    teamBName: teamBName,
    teamAColorHex: teamAColorHex,
    teamBColorHex: teamBColorHex,
    autoStopMinutes: minutes,
  );
}

/// Firmware default for [PushSessionConfig.autoStopMinutes] (proto: absent ⇒
/// firmware default 30). The app always sends its configured value; this is
/// the starting point before the operator touches the setting.
const int kDefaultAutoStopMinutes = 30;

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

/// Live per-channel white-balance gain calibration for the camera's
/// postprocessor — the diagnostic Calibration → Camera screen drives these with
/// sliders against the live preview to neutralize the IMX477 magenta cast.
/// Gains multiply the BGR channels (1.0 = identity); [enabled] false bypasses
/// correction. Fire-and-forget: applied live, no meaningful payload back.
class SetCameraCalibrationCommand extends BleCommand {
  SetCameraCalibrationCommand({
    required this.rGain,
    required this.gGain,
    required this.bGain,
    this.enabled = true,
    this.saturation = 1.0,
    this.contrast = 1.0,
    this.brightness = 0.0,
  });
  final double rGain;
  final double gGain;
  final double bGain;
  final bool enabled;
  final double saturation;
  final double contrast;
  final double brightness;
}

/// One-shot auto white-balance: the firmware measures the current frame (point
/// the camera at a white/grey surface) and computes the neutralizing gains,
/// applies them live, and returns them as a [CameraCalibrationResult] so the app
/// can seed its sliders.
class AutoWhiteBalanceCommand extends BleCommand {
  AutoWhiteBalanceCommand();
}

enum CameraFocusMode { auto, manual }

/// Motorized-focus control for the ArduCAM VCM lens. [mode] auto hands the camera
/// to continuous autofocus; manual holds [position] (0–1000 VCM code). [cameraIndex]
/// null = both cameras.
class CameraFocusCommand extends BleCommand {
  CameraFocusCommand({required this.mode, this.position, this.cameraIndex});
  final CameraFocusMode mode;
  final int? position;
  final int? cameraIndex;
}

/// Manual camera selection (manual tracking) — picks which camera feeds the
/// record/stream/single-preview output. The human override of the future AI
/// camera decision. [cameraIndex] 0 or 1.
class SetActiveCameraCommand extends BleCommand {
  SetActiveCameraCommand({required this.cameraIndex});
  final int cameraIndex;
}

/// Firmware-applied white-balance gains — returned by [AutoWhiteBalanceCommand]
/// (and echoed by SetCameraCalibration) so the calibration sliders can reflect
/// what the camera is actually applying.
class CameraCalibrationResult {
  const CameraCalibrationResult({
    required this.rGain,
    required this.gGain,
    required this.bGain,
    required this.enabled,
    this.saturation = 1.0,
    this.contrast = 1.0,
    this.brightness = 0.0,
  });
  final double rGain;
  final double gGain;
  final double bGain;
  final bool enabled;
  final double saturation;
  final double contrast;
  final double brightness;
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

enum BleResponseStatus {
  ok,
  error,
  timeout,
  unsupported,
  liveSessionActive,
  deviceInoperable,
}

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

  /// The firmware refused a start-class command because a camera is not
  /// healthy (`ResponseStatus.DEVICE_INOPERABLE`). Typed so the health-gating
  /// UX (U3) keys off the status, never the firmware's free-form message.
  bool get isDeviceInoperable => status == BleResponseStatus.deviceInoperable;

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

  factory BleCommandResponse.deviceInoperable(String message) =>
      BleCommandResponse(
        status: BleResponseStatus.deviceInoperable,
        errorMessage: message,
      );

  factory BleCommandResponse.timeout() =>
      BleCommandResponse(status: BleResponseStatus.timeout);
}
