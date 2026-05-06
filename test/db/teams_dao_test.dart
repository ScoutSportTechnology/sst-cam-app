import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scout_camera/db/app_database.dart';
import 'package:uuid/uuid.dart';

void main() {
  late AppDatabase db;
  late String userId;

  setUp(() async {
    db = AppDatabase.forTesting(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    userId = const Uuid().v4();
    await db.usersDao.insertUser(
      UsersTableCompanion.insert(id: userId, name: 'Coach Diego'),
    );
  });

  tearDown(() => db.close());

  // ---------------------------------------------------------------------------
  // Teams
  // ---------------------------------------------------------------------------

  test('watchForUser with no teams emits empty list', () async {
    final result = await db.teamsDao.watchForUser(userId).first;
    expect(result, isEmpty);
  });

  test('insert team → watchForUser emits it', () async {
    final teamId = const Uuid().v4();
    await db.teamsDao.insertTeam(
      TeamsTableCompanion.insert(
        id: teamId,
        userId: userId,
        name: 'Northside Rovers U14',
        shortName: 'NRA',
        sport: 'Soccer',
      ),
    );

    final teams = await db.teamsDao.watchForUser(userId).first;
    expect(teams, hasLength(1));
    expect(teams.first.id, teamId);
    expect(teams.first.name, 'Northside Rovers U14');
    expect(teams.first.hidden, isFalse);
  });

  test('updateTeam changes fields', () async {
    final teamId = const Uuid().v4();
    await db.teamsDao.insertTeam(
      TeamsTableCompanion.insert(
        id: teamId,
        userId: userId,
        name: 'Old Name',
        shortName: 'OLD',
        sport: 'Soccer',
      ),
    );

    await db.teamsDao.updateTeam(
      TeamsTableCompanion(
        id: Value(teamId),
        userId: Value(userId),
        name: const Value('New Name'),
        shortName: const Value('NEW'),
        sport: const Value('Basketball'),
      ),
    );

    final teams = await db.teamsDao.getForUser(userId);
    expect(teams.first.name, 'New Name');
    expect(teams.first.sport, 'Basketball');
  });

  test('watchForUser only returns teams for that user', () async {
    final otherUserId = const Uuid().v4();
    await db.usersDao.insertUser(
      UsersTableCompanion.insert(id: otherUserId, name: 'Coach Maria'),
    );
    await db.teamsDao.insertTeam(
      TeamsTableCompanion.insert(
        id: const Uuid().v4(),
        userId: userId,
        name: 'Team A',
        shortName: 'TA',
        sport: 'Soccer',
      ),
    );
    await db.teamsDao.insertTeam(
      TeamsTableCompanion.insert(
        id: const Uuid().v4(),
        userId: otherUserId,
        name: 'Team B',
        shortName: 'TB',
        sport: 'Soccer',
      ),
    );

    final teamsForUser = await db.teamsDao.getForUser(userId);
    expect(teamsForUser, hasLength(1));
    expect(teamsForUser.first.name, 'Team A');
  });

  // ---------------------------------------------------------------------------
  // Players
  // ---------------------------------------------------------------------------

  test('insert player → appears in players table for team', () async {
    final teamId = const Uuid().v4();
    await db.teamsDao.insertTeam(
      TeamsTableCompanion.insert(
        id: teamId,
        userId: userId,
        name: 'Test FC',
        shortName: 'TFC',
        sport: 'Soccer',
      ),
    );

    await db.teamsDao.insertPlayer(
      PlayersTableCompanion.insert(
        teamId: teamId,
        number: 7,
        name: 'A. Patel',
        position: 'Forward',
        captain: const Value(true),
      ),
    );

    final players = await db.teamsDao.getPlayersForTeam(teamId);
    expect(players, hasLength(1));
    expect(players.first.number, 7);
    expect(players.first.name, 'A. Patel');
    expect(players.first.captain, isTrue);
  });

  test('deletePlayer removes the player', () async {
    final teamId = const Uuid().v4();
    await db.teamsDao.insertTeam(
      TeamsTableCompanion.insert(
        id: teamId,
        userId: userId,
        name: 'Test FC',
        shortName: 'TFC',
        sport: 'Soccer',
      ),
    );
    await db.teamsDao.insertPlayer(
      PlayersTableCompanion.insert(
        teamId: teamId,
        number: 10,
        name: 'B. Okafor',
        position: 'Mid',
      ),
    );

    await db.teamsDao.deletePlayer(teamId, 10);

    final players = await db.teamsDao.getPlayersForTeam(teamId);
    expect(players, isEmpty);
  });

  // ---------------------------------------------------------------------------
  // deleteTeamById + FK cascade
  // ---------------------------------------------------------------------------

  test('deleteTeamById cascades to players', () async {
    final teamId = const Uuid().v4();
    await db.teamsDao.insertTeam(
      TeamsTableCompanion.insert(
        id: teamId,
        userId: userId,
        name: 'Test FC',
        shortName: 'TFC',
        sport: 'Soccer',
      ),
    );
    await db.teamsDao.insertPlayer(
      PlayersTableCompanion.insert(
        teamId: teamId,
        number: 1,
        name: 'D. Reyes',
        position: 'Keeper',
      ),
    );

    await db.teamsDao.deleteTeamById(teamId);

    final players = await db.teamsDao.getPlayersForTeam(teamId);
    expect(players, isEmpty);
  });

  test('deleteTeamById cascades to team_matches', () async {
    final teamId = const Uuid().v4();
    final matchId = const Uuid().v4();

    await db.teamsDao.insertTeam(
      TeamsTableCompanion.insert(
        id: teamId,
        userId: userId,
        name: 'Test FC',
        shortName: 'TFC',
        sport: 'Soccer',
      ),
    );
    await db.teamsDao.insertTeamMatch(
      TeamMatchesTableCompanion.insert(
        id: matchId,
        teamId: teamId,
        opponent: 'Rival FC',
        date: 'May 11',
        result: '',
        kind: 'upcoming',
        numPeriods: 2,
        periodLengthSeconds: 45 * 60,
      ),
    );

    await db.teamsDao.deleteTeamById(teamId);

    final matches = await db.teamsDao.getTeamMatches(teamId);
    expect(matches, isEmpty);
  });

  // ---------------------------------------------------------------------------
  // Team Matches
  // ---------------------------------------------------------------------------

  test('watchTeamMatches with no matches emits empty list', () async {
    final teamId = const Uuid().v4();
    await db.teamsDao.insertTeam(
      TeamsTableCompanion.insert(
        id: teamId,
        userId: userId,
        name: 'Test FC',
        shortName: 'TFC',
        sport: 'Soccer',
      ),
    );

    final matches = await db.teamsDao.watchTeamMatches(teamId).first;
    expect(matches, isEmpty);
  });

  test('insertTeamMatch → watchTeamMatches emits it', () async {
    final teamId = const Uuid().v4();
    final matchId = const Uuid().v4();

    await db.teamsDao.insertTeam(
      TeamsTableCompanion.insert(
        id: teamId,
        userId: userId,
        name: 'Test FC',
        shortName: 'TFC',
        sport: 'Soccer',
      ),
    );
    await db.teamsDao.insertTeamMatch(
      TeamMatchesTableCompanion.insert(
        id: matchId,
        teamId: teamId,
        opponent: 'vs Eastfield FC',
        date: 'May 11',
        result: '',
        kind: 'upcoming',
        numPeriods: 2,
        periodLengthSeconds: 35 * 60,
      ),
    );

    final matches = await db.teamsDao.watchTeamMatches(teamId).first;
    expect(matches, hasLength(1));
    expect(matches.first.opponent, 'vs Eastfield FC');
    expect(matches.first.kind, 'upcoming');
  });

  test('deleteTeamMatch removes only that match', () async {
    final teamId = const Uuid().v4();
    final matchId1 = const Uuid().v4();
    final matchId2 = const Uuid().v4();

    await db.teamsDao.insertTeam(
      TeamsTableCompanion.insert(
        id: teamId,
        userId: userId,
        name: 'Test FC',
        shortName: 'TFC',
        sport: 'Soccer',
      ),
    );
    await db.teamsDao.insertTeamMatch(
      TeamMatchesTableCompanion.insert(
        id: matchId1,
        teamId: teamId,
        opponent: 'Match 1',
        date: 'May 1',
        result: 'W 2-0',
        kind: 'past',
        numPeriods: 2,
        periodLengthSeconds: 45 * 60,
      ),
    );
    await db.teamsDao.insertTeamMatch(
      TeamMatchesTableCompanion.insert(
        id: matchId2,
        teamId: teamId,
        opponent: 'Match 2',
        date: 'May 8',
        result: '',
        kind: 'upcoming',
        numPeriods: 2,
        periodLengthSeconds: 45 * 60,
      ),
    );

    await db.teamsDao.deleteTeamMatch(matchId1);

    final matches = await db.teamsDao.getTeamMatches(teamId);
    expect(matches, hasLength(1));
    expect(matches.first.id, matchId2);
  });
}
