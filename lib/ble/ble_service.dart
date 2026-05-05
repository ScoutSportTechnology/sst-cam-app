import '../models/command.dart';
import '../models/device.dart';
import '../models/match.dart';
import '../models/recording.dart';
import '../models/sport_preset.dart';
import '../models/streaming.dart';
import '../models/team.dart';
import '../models/telemetry.dart';
import '../models/user.dart';

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
  // Teams / roster — camera-owned. Every mutation returns the updated team
  // (or list) so the app doesn't need to refetch after a write.
  // ---------------------------------------------------------------------------

  Future<List<TeamRecord>> listTeams(String deviceId);

  Future<List<TeamMatch>> listTeamMatches(String deviceId, String teamId);

  Future<TeamRecord> createTeam(String deviceId, TeamDraft draft);

  Future<TeamRecord> updateTeam(String deviceId, TeamDraft draft);

  Future<void> deleteTeam(String deviceId, String teamId);

  Future<TeamRecord> setTeamHidden(
    String deviceId,
    String teamId, {
    required bool hidden,
  });

  Future<Player> addPlayer(String deviceId, String teamId, PlayerDraft draft);

  Future<Player> updatePlayer(
    String deviceId,
    String teamId,
    int currentNumber,
    PlayerDraft draft,
  );

  Future<void> removePlayer(String deviceId, String teamId, int number);

  // ---------------------------------------------------------------------------
  // Per-team matches — past results and scheduled upcoming matches.
  // Both kinds count toward stats; upcoming additionally drive the camera's
  // recording / streaming schedule.
  // ---------------------------------------------------------------------------

  Future<TeamMatch> addTeamMatch(
    String deviceId,
    String teamId,
    TeamMatchDraft draft,
  );

  Future<void> removeTeamMatch(String deviceId, String teamId, String matchId);

  // ---------------------------------------------------------------------------
  // Sport setups (presets) — saved per-camera time configurations grouped by
  // base sport. Picked at match-schedule time to materialize the match's
  // periods + period length.
  // ---------------------------------------------------------------------------

  Future<List<SportPreset>> listSportPresets(String deviceId);

  Future<SportPreset> createSportPreset(
    String deviceId,
    SportPresetDraft draft,
  );

  Future<SportPreset> updateSportPreset(
    String deviceId,
    SportPresetDraft draft,
  );

  Future<void> deleteSportPreset(String deviceId, String presetId);

  // ---------------------------------------------------------------------------
  // Users — camera-side operator profiles. Each user scopes everything the
  // camera owns (teams, match history, sport setups, streaming destinations)
  // so a single camera can be shared across coaches without their data
  // bleeding together.
  // ---------------------------------------------------------------------------

  Future<List<UserRecord>> listUsers(String deviceId);

  Future<UserRecord> createUser(String deviceId, UserDraft draft);

  Future<UserRecord> updateUser(String deviceId, UserDraft draft);

  Future<void> deleteUser(String deviceId, String userId);

  /// Returns the camera's currently-active user id, or `null` if none is set
  /// (no users on the camera, or the previously-active user was deleted).
  Future<String?> getActiveUser(String deviceId);

  Future<void> setActiveUser(String deviceId, String userId);

  // ---------------------------------------------------------------------------
  // Streaming destinations — per-user live-streaming endpoints. Reads and
  // writes are scoped by an explicit [userId] passed by the caller (sourced
  // from the app's `activeUserProvider`); the camera does not implicitly
  // scope by its persisted active user.
  // ---------------------------------------------------------------------------

  Future<List<StreamingDestination>> listStreamingDestinations(
    String deviceId,
    String userId,
  );

  Future<StreamingDestination> createStreamingDestination(
    String deviceId,
    String userId,
    StreamingDestinationDraft draft,
  );

  Future<StreamingDestination> updateStreamingDestination(
    String deviceId,
    String userId,
    StreamingDestinationDraft draft,
  );

  Future<void> deleteStreamingDestination(
    String deviceId,
    String userId,
    String destinationId,
  );

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
