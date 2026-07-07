import 'package:drift/drift.dart';

/// Persisted live-match scoreboard (U2, state-health cycle) — the app-side
/// half of "zero scoreboard loss": [LiveMatchState] is snapshotted here on
/// every mutation so a killed app restores the scoreboard on the next connect.
///
/// One row per camera (`device_id` is the primary key); the row's
/// `match_uuid` keys the logical identity — restore happens only when the
/// firmware's running `match_uuid` equals it, so camera A's match can never
/// hydrate against camera B or against a different session.
///
/// This is transient runtime state, NOT business data: it is cleared by the
/// single finalize path (normal end / away-ended / adopted-stale) and is
/// deliberately excluded from [BackupService] exports.
class LiveMatchesTable extends Table {
  @override
  String get tableName => 'live_matches';

  /// BLE device id of the camera the session runs on.
  TextColumn get deviceId => text()();

  /// The PushSessionConfig `match_uuid` this scoreboard belongs to.
  TextColumn get matchUuid => text()();

  /// The team_matches row this live match finalizes into. Null only for
  /// sessions with no library row.
  TextColumn get libraryMatchId => text().nullable()();

  IntColumn get scoreHome => integer().withDefault(const Constant(0))();
  IntColumn get scoreAway => integer().withDefault(const Constant(0))();
  TextColumn get homeName => text().withDefault(const Constant(''))();
  TextColumn get awayName => text().withDefault(const Constant(''))();

  /// MatchPhase name: 'idle' | 'period' | 'periodBreak' | 'ended'.
  TextColumn get phase => text()();

  /// Whether the period clock was running at save time.
  BoolColumn get timerRunning => boolean().withDefault(const Constant(false))();

  /// Whether recording was PAUSED at save time (recording/idle themselves are
  /// runtime facts re-adopted from the firmware snapshot on restore; paused is
  /// app intent the snapshot's isRecording=false cannot distinguish).
  BoolColumn get recPaused => boolean().withDefault(const Constant(false))();

  IntColumn get currentPeriod => integer().withDefault(const Constant(0))();
  IntColumn get numPeriods => integer().withDefault(const Constant(2))();
  IntColumn get periodLengthSeconds =>
      integer().withDefault(const Constant(0))();

  /// Elapsed seconds in the current period, measured at [anchorEpochMs] (when
  /// running) or frozen (when paused).
  IntColumn get elapsedSeconds => integer().withDefault(const Constant(0))();

  /// Wall-clock anchor (epoch ms) at which [elapsedSeconds] was measured;
  /// null when the clock was not running. Effective elapsed after an app kill
  /// = elapsedSeconds + (now - anchor) — immune to UI-timer drift.
  IntColumn get anchorEpochMs => integer().nullable()();

  /// JSON-encoded [LiveEvent] list: [{clock, label, kind, params}].
  TextColumn get eventsJson => text().withDefault(const Constant('[]'))();

  TextColumn get homeColorHex => text().nullable()();
  TextColumn get awayColorHex => text().nullable()();

  /// Last save time (epoch ms) — diagnostics only.
  IntColumn get updatedAtEpochMs => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {deviceId};
}
