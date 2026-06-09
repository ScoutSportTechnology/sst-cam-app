// Teams state — controller, team matches stream, filter providers.
//
// Design note (U5): `AsyncNotifier` is kept (rather than `StreamNotifier`)
// because write methods need to be on the same class as `build()`. The pattern
// mirrors `UsersController`: get initial snapshot, subscribe to watch stream
// for mutations, push subsequent emissions into `state` via a listener. No
// `_refresh()` calls — Drift emits on every mutation automatically.

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/db/app_database.dart';
import '../../core/db/daos/teams_dao.dart';
import '../../core/models/team.dart';
import '../../core/state/db_providers.dart';
import '../settings/users/users_state.dart' show activeUserProvider;

export '../../core/models/team.dart';

const _uuid = Uuid();

/// Convert a raw [TeamsTableData] row and its [PlayersTableData] list into the
/// app-model [TeamRecord].
TeamRecord rowToTeamRecord(TeamsTableData t, List<PlayersTableData> players) =>
    TeamRecord(
      id: t.id,
      name: t.name,
      shortName: t.shortName,
      sport: t.sport,
      hidden: t.hidden,
      colorHex: t.colorHex,
      roster: players.map(rowToPlayer).toList(),
    );

Player rowToPlayer(PlayersTableData p) => Player(
  number: p.number,
  name: p.name,
  position: p.position,
  captain: p.captain,
);

/// Convert a raw [TeamMatchesTableData] row into the app-model [TeamMatch].
TeamMatch rowToTeamMatch(TeamMatchesTableData m) => TeamMatch(
  id: m.id,
  opponent: m.opponent,
  date: m.date,
  result: m.result,
  kind: m.kind == 'upcoming' ? MatchKind.upcoming : MatchKind.past,
  numPeriods: m.numPeriods,
  periodLengthSeconds: m.periodLengthSeconds,
  clips: m.clips,
  sizeMb: m.sizeMb,
);

class TeamsController extends AsyncNotifier<List<TeamRecord>> {
  String _requireActiveUser() {
    final userId = ref.read(activeUserProvider);
    if (userId == null) throw StateError('No active user');
    return userId;
  }

  @override
  Future<List<TeamRecord>> build() async {
    final userId = ref.watch(activeUserProvider);
    if (userId == null) return const [];

    final dao = ref.watch(teamsDaoProvider);

    // Fix 7: Subscribe to both teamsTable and playersTable so roster mutations
    // also invalidate the stream. Skip the very first emission from each stream
    // to avoid double-building on startup (the initial snapshot is returned
    // below).
    bool firstTeam = true;
    final teamSub = dao
        .watchForUser(userId)
        .listen(
          (rows) async {
            if (firstTeam) {
              firstTeam = false;
              return;
            }
            final records = await _buildRecords(dao, rows);
            state = AsyncValue.data(records);
          },
          onError: (Object e, StackTrace st) {
            state = AsyncValue.error(e, st);
          },
        );
    ref.onDispose(teamSub.cancel);

    bool firstPlayer = true;
    final playerSub = dao.watchAllPlayers().listen(
      (_) async {
        if (firstPlayer) {
          firstPlayer = false;
          return;
        }
        try {
          final rows = await dao.getForUser(userId);
          state = AsyncValue.data(await _buildRecords(dao, rows));
        } catch (e, st) {
          state = AsyncValue.error(e, st);
        }
      },
      onError: (Object e, StackTrace st) {
        state = AsyncValue.error(e, st);
      },
    );
    ref.onDispose(playerSub.cancel);

    // Initial snapshot.
    final rows = await dao.getForUser(userId);
    return _buildRecords(dao, rows);
  }

  /// Bulk-fetch players for all teams and assemble [TeamRecord] list.
  ///
  /// Uses a single bulk query instead of one-per-team to avoid N+1 queries
  /// (Fix 6).
  Future<List<TeamRecord>> _buildRecords(
    TeamsDao dao,
    List<TeamsTableData> rows,
  ) async {
    if (rows.isEmpty) return const [];
    final teamIds = rows.map((r) => r.id).toList();
    final allPlayers = await dao.getPlayersForTeams(teamIds);
    final playersByTeam = <String, List<PlayersTableData>>{};
    for (final p in allPlayers) {
      playersByTeam.putIfAbsent(p.teamId, () => []).add(p);
    }
    return rows
        .map((r) => rowToTeamRecord(r, playersByTeam[r.id] ?? const []))
        .toList();
  }

  Future<TeamRecord> create(TeamDraft draft) async {
    final userId = _requireActiveUser();
    final dao = ref.read(teamsDaoProvider);
    final id = _uuid.v4();
    await dao.insertTeam(
      TeamsTableCompanion.insert(
        id: id,
        userId: userId,
        name: draft.name.trim(),
        shortName: draft.shortName.trim(),
        sport: draft.sport,
        colorHex: Value(draft.colorHex),
      ),
    );
    return TeamRecord(
      id: id,
      name: draft.name.trim(),
      shortName: draft.shortName.trim(),
      sport: draft.sport,
      colorHex: draft.colorHex,
      roster: const [],
    );
  }

  Future<void> edit(TeamDraft draft) async {
    final userId = _requireActiveUser();
    final dao = ref.read(teamsDaoProvider);
    await dao.updateTeam(
      TeamsTableCompanion.insert(
        id: draft.id,
        userId: userId,
        name: draft.name.trim(),
        shortName: draft.shortName.trim(),
        sport: draft.sport,
        colorHex: Value(draft.colorHex),
      ),
    );
  }

  Future<void> delete(String teamId) async {
    await ref.read(teamsDaoProvider).deleteTeamById(teamId);
    // FK cascade removes players and team_matches automatically.
    // upcomingMatchesProvider rebuilds automatically via its Drift stream.
  }

  Future<void> setHidden(String teamId, {required bool hidden}) async {
    final dao = ref.read(teamsDaoProvider);
    await dao.setTeamHidden(teamId, hidden);
  }

  Future<void> addPlayer(String teamId, PlayerDraft draft) async {
    await ref
        .read(teamsDaoProvider)
        .insertPlayer(
          PlayersTableCompanion.insert(
            teamId: teamId,
            number: draft.number,
            name: draft.name,
            position: draft.position,
            captain: Value(draft.captain),
          ),
        );
  }

  Future<void> updatePlayer(
    String teamId,
    int currentNumber,
    PlayerDraft draft,
  ) async {
    final dao = ref.read(teamsDaoProvider);
    // Fix 8: Wrap delete + re-insert in a transaction so the operation is
    // atomic — no window where the player row is absent.
    await ref.read(appDatabaseProvider).transaction(() async {
      await dao.deletePlayer(teamId, currentNumber);
      await dao.insertPlayer(
        PlayersTableCompanion.insert(
          teamId: teamId,
          number: draft.number,
          name: draft.name,
          position: draft.position,
          captain: Value(draft.captain),
        ),
      );
    });
  }

  Future<void> removePlayer(String teamId, int number) async {
    await ref.read(teamsDaoProvider).deletePlayer(teamId, number);
  }

  Future<TeamMatch> addMatch(String teamId, TeamMatchDraft draft) async {
    final dao = ref.read(teamsDaoProvider);
    final id = draft.id.isEmpty ? _uuid.v4() : draft.id;
    await dao.insertTeamMatch(
      TeamMatchesTableCompanion.insert(
        id: id,
        teamId: teamId,
        opponent: draft.opponent,
        date: draft.date,
        result: draft.result,
        kind: draft.kind == MatchKind.upcoming ? 'upcoming' : 'past',
        numPeriods: draft.numPeriods,
        periodLengthSeconds: draft.periodLengthSeconds,
      ),
    );
    // teamMatchesProvider and upcomingMatchesProvider rebuild automatically
    // via their Drift watch streams.
    return TeamMatch(
      id: id,
      opponent: draft.opponent,
      date: draft.date,
      result: draft.result,
      kind: draft.kind,
      numPeriods: draft.numPeriods,
      periodLengthSeconds: draft.periodLengthSeconds,
      clips: 0,
      sizeMb: 0,
    );
  }

  Future<void> removeMatch(String teamId, String matchId) async {
    await ref.read(teamsDaoProvider).deleteTeamMatch(matchId);
    // teamMatchesProvider and upcomingMatchesProvider rebuild automatically.
  }
}

final teamsControllerProvider =
    AsyncNotifierProvider<TeamsController, List<TeamRecord>>(
      TeamsController.new,
    );

/// Per-team match list — live stream backed by Drift. Emits on every mutation
/// to the team_matches table for the given team. No camera connection required.
final teamMatchesProvider = StreamProvider.family<List<TeamMatch>, String>((
  ref,
  teamId,
) {
  return ref
      .watch(teamsDaoProvider)
      .watchTeamMatches(teamId)
      .map((rows) => rows.map(rowToTeamMatch).toList());
});

// ---------------------------------------------------------------------------
// Filter / search state for the Teams page.
// ---------------------------------------------------------------------------

final teamsSearchQueryProvider = StateProvider<String>((_) => '');
final teamsSportFilterProvider = StateProvider<String?>(
  (_) => null,
); // null = All
final teamsShowHiddenProvider = StateProvider<bool>((_) => false);

final sportPresetsFilterProvider = StateProvider<String?>(
  (_) => null,
); // null = All

/// Sports actually present in the current team set, in `kSports` order.
/// Used to drive the filter chip row so we never show a chip with zero teams.
final availableSportsProvider = Provider<List<String>>((ref) {
  final teams = ref.watch(teamsControllerProvider).valueOrNull ?? const [];
  final present = teams.map((t) => t.sport).toSet();
  return kSports.where(present.contains).toList();
});

/// Teams after applying search + sport filter + hidden toggle.
final filteredTeamsProvider = Provider<List<TeamRecord>>((ref) {
  final teams = ref.watch(teamsControllerProvider).valueOrNull ?? const [];
  final query = ref.watch(teamsSearchQueryProvider).trim().toLowerCase();
  final sport = ref.watch(teamsSportFilterProvider);
  final showHidden = ref.watch(teamsShowHiddenProvider);

  return teams.where((t) {
    if (!showHidden && t.hidden) return false;
    if (sport != null && t.sport != sport) return false;
    if (query.isEmpty) return true;
    return t.name.toLowerCase().contains(query) ||
        t.shortName.toLowerCase().contains(query);
  }).toList();
});
