// Persisted live-match scoreboard, keyed by device (U2, state-health cycle).
//
// The connect handshake's reconcile step needs the app's persisted match
// (keyed `(device_id, match_uuid)`) to decide between "push app scores via
// SetMatchState + restore the scoreboard" and "adopt the firmware-derived
// view"; the live-match controller persists [LiveMatchState] here on every
// mutation so the scoreboard survives an app kill. The Drift-backed store is
// the provider default; [NoPersistedMatchStore] remains for tests that want
// the nothing-persisted behavior without a database.

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/app_database.dart';
import 'db_providers.dart' show appDatabaseProvider;

/// Mirror of the match feature's `MatchPhase`, kept as its own enum so this
/// core-level store does not import feature code. `session_state.dart` owns
/// the mapping between the two.
enum PersistedMatchPhase { idle, period, periodBreak, ended }

/// The app-owned match facts persisted on every live-match mutation.
///
/// Scores/events are the app's authority — deltas made while disconnected
/// never reached the firmware. The clock is persisted as a WALL-CLOCK anchor
/// ([elapsedSeconds] measured at [anchorEpochMs]) rather than a tick count,
/// so it survives an app kill and is immune to UI-timer drift — but on a
/// rejoin the firmware clock still wins outright (it is the only clock that
/// ran through the disconnect); the anchor is the offline/no-firmware
/// fallback.
class PersistedLiveMatch {
  const PersistedLiveMatch({
    required this.matchUuid,
    required this.scoreA,
    required this.scoreB,
    this.libraryMatchId,
    this.homeName = '',
    this.awayName = '',
    this.phase = PersistedMatchPhase.idle,
    this.timerRunning = false,
    this.recPaused = false,
    this.currentPeriod = 0,
    this.numPeriods = 2,
    this.periodLengthSeconds = 0,
    this.elapsedSeconds = 0,
    this.anchorEpochMs,
    this.eventsJson = '[]',
    this.homeColorHex,
    this.awayColorHex,
    this.updatedAtEpochMs = 0,
  });

  /// The PushSessionConfig `match_uuid` this scoreboard belongs to. Reconcile
  /// only restores/pushes when it equals the running session's uuid — one
  /// match's data must never hydrate against another's session.
  final String matchUuid;

  /// Home (team A) / away (team B) — same A/B orientation as the wire.
  final int scoreA;
  final int scoreB;

  /// The team_matches row this match finalizes into (null: no library row).
  final String? libraryMatchId;

  final String homeName;
  final String awayName;
  final PersistedMatchPhase phase;
  final bool timerRunning;

  /// Recording was PAUSED at save time (see LiveMatchesTable.recPaused).
  final bool recPaused;

  final int currentPeriod;
  final int numPeriods;
  final int periodLengthSeconds;

  /// Elapsed seconds in the current period at [anchorEpochMs] (running) or
  /// frozen (paused).
  final int elapsedSeconds;

  /// Wall-clock epoch ms at which [elapsedSeconds] was measured; null when
  /// the clock was not running.
  final int? anchorEpochMs;

  /// JSON-encoded LiveEvent list (opaque here; session_state owns the codec).
  final String eventsJson;

  final String? homeColorHex;
  final String? awayColorHex;
  final int updatedAtEpochMs;

  /// A match past kickoff and not yet finalized — the only shape the
  /// away-ended notice/finalize path applies to.
  bool get isMidMatch =>
      phase == PersistedMatchPhase.period ||
      phase == PersistedMatchPhase.periodBreak;

  /// Wall-clock-derived elapsed seconds at [nowEpochMs] — counts the time the
  /// app was dead when the clock was running.
  int effectiveElapsedSeconds(int nowEpochMs) {
    final anchor = anchorEpochMs;
    if (!timerRunning || anchor == null) return elapsedSeconds;
    final delta = ((nowEpochMs - anchor) / 1000).floor();
    return delta > 0 ? elapsedSeconds + delta : elapsedSeconds;
  }
}

/// Port for the persisted live-match store. [DriftPersistedMatchStore] is the
/// default; tests override with [NoPersistedMatchStore] or a fake.
abstract class PersistedMatchStore {
  /// The persisted scoreboard for [deviceId], or null when nothing was
  /// persisted (first run, cleared store, or the match already finalized).
  Future<PersistedLiveMatch?> load(String deviceId);

  /// Insert-or-replace the persisted scoreboard for [deviceId]
  /// (persist-on-change).
  Future<void> save(String deviceId, PersistedLiveMatch match);

  /// Idempotent keyed clear: removes [deviceId]'s row only when it still
  /// belongs to [matchUuid]. The single finalize path calls this LAST, so a
  /// crash between the team_matches finalize and this clear re-runs the
  /// (idempotent) finalize on the next connect instead of losing data.
  Future<void> clear(String deviceId, String matchUuid);
}

/// Nothing is ever persisted — reconcile always adopts the firmware-derived
/// view. Kept for tests that don't want a database in the loop.
class NoPersistedMatchStore implements PersistedMatchStore {
  const NoPersistedMatchStore();

  @override
  Future<PersistedLiveMatch?> load(String deviceId) async => null;

  @override
  Future<void> save(String deviceId, PersistedLiveMatch match) async {}

  @override
  Future<void> clear(String deviceId, String matchUuid) async {}
}

/// Drift-backed store over [LiveMatchesDao] — the production default.
class DriftPersistedMatchStore implements PersistedMatchStore {
  DriftPersistedMatchStore(this._db);

  final AppDatabase _db;

  @override
  Future<PersistedLiveMatch?> load(String deviceId) async {
    final row = await _db.liveMatchesDao.getForDevice(deviceId);
    if (row == null) return null;
    return PersistedLiveMatch(
      matchUuid: row.matchUuid,
      scoreA: row.scoreHome,
      scoreB: row.scoreAway,
      libraryMatchId: row.libraryMatchId,
      homeName: row.homeName,
      awayName: row.awayName,
      phase:
          PersistedMatchPhase.values.asNameMap()[row.phase] ??
          PersistedMatchPhase.idle,
      timerRunning: row.timerRunning,
      recPaused: row.recPaused,
      currentPeriod: row.currentPeriod,
      numPeriods: row.numPeriods,
      periodLengthSeconds: row.periodLengthSeconds,
      elapsedSeconds: row.elapsedSeconds,
      anchorEpochMs: row.anchorEpochMs,
      eventsJson: row.eventsJson,
      homeColorHex: row.homeColorHex,
      awayColorHex: row.awayColorHex,
      updatedAtEpochMs: row.updatedAtEpochMs,
    );
  }

  @override
  Future<void> save(String deviceId, PersistedLiveMatch match) {
    return _db.liveMatchesDao.upsert(
      LiveMatchesTableCompanion.insert(
        deviceId: deviceId,
        matchUuid: match.matchUuid,
        libraryMatchId: Value(match.libraryMatchId),
        scoreHome: Value(match.scoreA),
        scoreAway: Value(match.scoreB),
        homeName: Value(match.homeName),
        awayName: Value(match.awayName),
        phase: match.phase.name,
        timerRunning: Value(match.timerRunning),
        recPaused: Value(match.recPaused),
        currentPeriod: Value(match.currentPeriod),
        numPeriods: Value(match.numPeriods),
        periodLengthSeconds: Value(match.periodLengthSeconds),
        elapsedSeconds: Value(match.elapsedSeconds),
        anchorEpochMs: Value(match.anchorEpochMs),
        eventsJson: Value(match.eventsJson),
        homeColorHex: Value(match.homeColorHex),
        awayColorHex: Value(match.awayColorHex),
        updatedAtEpochMs: Value(match.updatedAtEpochMs),
      ),
    );
  }

  @override
  Future<void> clear(String deviceId, String matchUuid) =>
      _db.liveMatchesDao.clearForMatch(deviceId, matchUuid);
}

final persistedMatchStoreProvider = Provider<PersistedMatchStore>(
  (ref) => DriftPersistedMatchStore(ref.watch(appDatabaseProvider)),
);
