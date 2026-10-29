// Session snapshot — the firmware's ACTUAL state, read at connect by the
// connect handshake (proto §9b, state-health cycle). Pure read, no side
// effects. A session OUTLIVES the BLE connection: the firmware keeps
// recording/streaming through app disconnects (bounded by
// auto_stop_minutes), so on every connect the app rehydrates from this
// snapshot instead of assuming defaults.

import 'match.dart';
import 'preview_layout.dart';
import 'telemetry.dart' show CameraHealth;

/// Firmware session lifecycle, one axis of the snapshot. [finalizing] is a
/// real, observable state: finalize (EOS, stream stop, summary write) is
/// claimed exactly once; a snapshot read during it reports finalizing rather
/// than a torn intermediate.
enum SessionPhase { unknown, idle, configured, ready, recording, finalizing }

/// Why the previous session ended — carried in [LastSessionSummary] so a
/// reconnecting app can explain "ended while away" to the operator.
enum SessionEndReason { unknown, appStop, autoStop, cameraFailure, reboot }

/// How the previous session ended. Populated in [SessionSnapshot] ONLY when
/// `sessionPhase == SessionPhase.idle` and a previous session exists. The app
/// uses it only when [matchUuid] equals its persisted match's uuid (U2).
class LastSessionSummary {
  const LastSessionSummary({
    required this.matchUuid,
    required this.endReason,
    this.endClockSeconds,
    this.fileValid,
  });

  final String matchUuid;
  final SessionEndReason endReason;

  /// Match clock (monotonic seconds) at the moment of finalize.
  final int? endClockSeconds;

  /// Finalized MP4 is present and playable (moov written). False for orphans.
  final bool? fileValid;
}

/// Reply to `GetSessionSnapshotCommand`. Every nullable field maps a proto3
/// `optional` whose absence is meaningful (older firmware / not applicable) —
/// consumers must not fabricate values for absent fields.
class SessionSnapshot {
  const SessionSnapshot({
    required this.sessionPhase,
    this.activeCameraIndex,
    this.previewLayout,
    this.isRecording,
    this.isStreaming,
    this.recordingElapsedSeconds,
    this.matchState,
    this.camera0Health,
    this.camera1Health,
    this.lastSession,
    this.wifiGroupUp,
  });

  final SessionPhase sessionPhase;

  /// Current selections — the app ADOPTS these instead of force-resetting.
  final int? activeCameraIndex;
  final PreviewLayout? previewLayout;

  /// Activity flags — same sources as DeviceTelemetry.
  final bool? isRecording;
  final bool? isStreaming;

  /// Monotonic seconds since RECORDING_START of the running recording; null
  /// when not recording. Drives the recording-duration display after a rejoin.
  final int? recordingElapsedSeconds;

  /// Absolute match state incl. elapsedSeconds / clockRunning / matchUuid.
  /// Null when no session config was ever pushed.
  final MatchState? matchState;

  final CameraHealth? camera0Health;
  final CameraHealth? camera1Health;

  /// Present ONLY when [sessionPhase] is idle and a previous session exists.
  final LastSessionSummary? lastSession;

  /// WiFi-Direct group currently up (rejoin path: StartWifiDirectCommand is
  /// idempotent and returns the existing credentials).
  final bool? wifiGroupUp;
}
