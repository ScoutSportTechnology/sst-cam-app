import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/teams_table.dart';
import '../tables/team_matches_table.dart';

part 'teams_dao.g.dart';

@DriftAccessor(tables: [TeamsTable, PlayersTable, TeamMatchesTable])
class TeamsDao extends DatabaseAccessor<AppDatabase> with _$TeamsDaoMixin {
  TeamsDao(super.db);

  // ---------------------------------------------------------------------------
  // Teams
  // ---------------------------------------------------------------------------

  /// Watch all teams for a user — emits on every mutation to teamsTable.
  Stream<List<TeamsTableData>> watchForUser(String userId) =>
      (select(teamsTable)..where((t) => t.userId.equals(userId))).watch();

  /// Watch the entire playersTable. Emits whenever any player row changes.
  ///
  /// Used by [TeamsController] to invalidate the team list when roster
  /// mutations happen, since those don't touch the teamsTable rows directly
  /// (Fix 7).
  Stream<List<PlayersTableData>> watchAllPlayers() =>
      select(playersTable).watch();

  /// One-shot fetch of all teams for a user.
  Future<List<TeamsTableData>> getForUser(String userId) =>
      (select(teamsTable)..where((t) => t.userId.equals(userId))).get();

  /// Insert a new team row.
  Future<void> insertTeam(TeamsTableCompanion companion) =>
      into(teamsTable).insert(companion);

  /// Update an existing team row.
  Future<bool> updateTeam(TeamsTableCompanion companion) =>
      update(teamsTable).replace(companion);

  /// Delete a team by id. FK cascade removes players and team_matches.
  Future<int> deleteTeamById(String id) =>
      (delete(teamsTable)..where((t) => t.id.equals(id))).go();

  /// Targeted update of a team's hidden flag — no full-row load required.
  Future<void> setTeamHidden(String teamId, bool hidden) =>
      (update(teamsTable)..where((t) => t.id.equals(teamId))).write(
        TeamsTableCompanion(hidden: Value(hidden)),
      );

  // ---------------------------------------------------------------------------
  // Players
  // ---------------------------------------------------------------------------

  /// Watch all players for a team.
  Stream<List<PlayersTableData>> watchPlayersForTeam(String teamId) =>
      (select(playersTable)..where((p) => p.teamId.equals(teamId))).watch();

  /// One-shot fetch of all players for a team.
  Future<List<PlayersTableData>> getPlayersForTeam(String teamId) =>
      (select(playersTable)..where((p) => p.teamId.equals(teamId))).get();

  /// Insert a new player row.
  Future<void> insertPlayer(PlayersTableCompanion companion) =>
      into(playersTable).insert(companion);

  /// Update an existing player row.
  Future<bool> updatePlayer(PlayersTableCompanion companion) =>
      update(playersTable).replace(companion);

  /// Delete a player by team id and jersey number.
  Future<int> deletePlayer(String teamId, int number) => (delete(
    playersTable,
  )..where((p) => p.teamId.equals(teamId) & p.number.equals(number))).go();

  // ---------------------------------------------------------------------------
  // Team Matches
  // ---------------------------------------------------------------------------

  /// Watch all matches for a team — emits on every mutation.
  Stream<List<TeamMatchesTableData>> watchTeamMatches(String teamId) =>
      (select(teamMatchesTable)..where((m) => m.teamId.equals(teamId))).watch();

  /// One-shot fetch of all matches for a team.
  Future<List<TeamMatchesTableData>> getTeamMatches(String teamId) =>
      (select(teamMatchesTable)..where((m) => m.teamId.equals(teamId))).get();

  /// Bulk fetch of all team_matches for a list of team IDs.
  ///
  /// Returns an empty list when [teamIds] is empty (skips the query).
  Future<List<TeamMatchesTableData>> getTeamMatchesForTeams(
    List<String> teamIds,
  ) {
    if (teamIds.isEmpty) return Future.value(const []);
    return (select(
      teamMatchesTable,
    )..where((t) => t.teamId.isIn(teamIds))).get();
  }

  /// Bulk fetch of all players for a list of team IDs.
  ///
  /// Returns an empty list when [teamIds] is empty (skips the query).
  Future<List<PlayersTableData>> getPlayersForTeams(List<String> teamIds) {
    if (teamIds.isEmpty) return Future.value(const []);
    return (select(playersTable)..where((t) => t.teamId.isIn(teamIds))).get();
  }

  /// Insert a new team match row.
  Future<void> insertTeamMatch(TeamMatchesTableCompanion companion) =>
      into(teamMatchesTable).insert(companion);

  /// Delete a team match by id.
  Future<int> deleteTeamMatch(String matchId) =>
      (delete(teamMatchesTable)..where((m) => m.id.equals(matchId))).go();

  /// Finalize a played match into the library: flip it to 'past' and record the
  /// result + events. [sizeMb] stays 0 until the recording is downloaded (the
  /// library then shows it as remote/needs-download). The scheduled date is kept.
  /// Returns true if a row was updated.
  Future<bool> finalizeMatch(
    String matchId, {
    required String result,
    required String eventsJson,
    int sizeMb = 0,
  }) async {
    final updated =
        await (update(
          teamMatchesTable,
        )..where((m) => m.id.equals(matchId))).write(
          TeamMatchesTableCompanion(
            kind: const Value('past'),
            result: Value(result),
            eventsJson: Value(eventsJson),
            sizeMb: Value(sizeMb),
          ),
        );
    return updated > 0;
  }

  /// Watch all past matches joined with their team, for the library screen.
  /// Emits on any mutation to teamMatchesTable or teamsTable.
  Stream<List<LibraryMatchRow>> watchPastMatchesForLibrary() {
    final query =
        select(teamMatchesTable).join([
            innerJoin(
              teamsTable,
              teamsTable.id.equalsExp(teamMatchesTable.teamId),
            ),
          ])
          ..where(teamMatchesTable.kind.equals('past'))
          ..orderBy([OrderingTerm.desc(teamMatchesTable.date)]);

    return query.watch().map(
      (rows) => rows
          .map(
            (r) => LibraryMatchRow(
              match: r.readTable(teamMatchesTable),
              team: r.readTable(teamsTable),
            ),
          )
          .toList(),
    );
  }

  /// Watch all upcoming matches for a user across all visible teams.
  ///
  /// Emits on every mutation to either [teamMatchesTable] or [teamsTable].
  /// Results are ordered ascending by [TeamMatchesTable.date].
  Stream<List<UpcomingMatchRow>> watchUpcomingMatchesForUser(String userId) {
    final query = select(teamMatchesTable).join([
      innerJoin(teamsTable, teamsTable.id.equalsExp(teamMatchesTable.teamId)),
    ]);
    query
      ..where(teamMatchesTable.kind.equals('upcoming'))
      ..where(teamsTable.hidden.equals(false))
      ..where(teamsTable.userId.equals(userId))
      ..orderBy([OrderingTerm.asc(teamMatchesTable.date)]);
    return query.watch().map(
      (rows) => rows
          .map(
            (r) => UpcomingMatchRow(
              match: r.readTable(teamMatchesTable),
              team: r.readTable(teamsTable),
            ),
          )
          .toList(),
    );
  }
}

/// Lightweight join result for the library screen.
class LibraryMatchRow {
  const LibraryMatchRow({required this.match, required this.team});
  final TeamMatchesTableData match;
  final TeamsTableData team;
}

class UpcomingMatchRow {
  const UpcomingMatchRow({required this.match, required this.team});
  final TeamMatchesTableData match;
  final TeamsTableData team;
}
