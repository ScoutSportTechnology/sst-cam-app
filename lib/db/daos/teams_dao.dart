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

  /// Watch all teams for a user — emits on every mutation to teams or players.
  Stream<List<TeamsTableData>> watchForUser(String userId) =>
      (select(teamsTable)..where((t) => t.userId.equals(userId))).watch();

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

  /// Insert a new team match row.
  Future<void> insertTeamMatch(TeamMatchesTableCompanion companion) =>
      into(teamMatchesTable).insert(companion);

  /// Delete a team match by id.
  Future<int> deleteTeamMatch(String matchId) =>
      (delete(teamMatchesTable)..where((m) => m.id.equals(matchId))).go();
}
