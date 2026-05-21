import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sst_cam_app/core/db/app_database.dart';
import 'package:sst_cam_app/core/db/daos/teams_dao.dart';
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

  // ---------------------------------------------------------------------------
  // watchUpcomingMatchesForUser
  // ---------------------------------------------------------------------------

  group('watchUpcomingMatchesForUser', () {
    Future<String> makeTeam({
      String? teamId,
      String? name,
      String? ownerId,
      bool hidden = false,
    }) async {
      final id = teamId ?? const Uuid().v4();
      final owner = ownerId ?? userId;
      await db.teamsDao.insertTeam(
        TeamsTableCompanion.insert(
          id: id,
          userId: owner,
          name: name ?? 'Test FC',
          shortName: 'TFC',
          sport: 'Soccer',
          hidden: Value(hidden),
        ),
      );
      return id;
    }

    Future<String> makeMatch({
      required String teamId,
      required String opponent,
      required String date,
      String kind = 'upcoming',
    }) async {
      final id = const Uuid().v4();
      await db.teamsDao.insertTeamMatch(
        TeamMatchesTableCompanion.insert(
          id: id,
          teamId: teamId,
          opponent: opponent,
          date: date,
          result: '',
          kind: kind,
          numPeriods: 2,
          periodLengthSeconds: 45 * 60,
        ),
      );
      return id;
    }

    test('happy path: visible team with one upcoming match emits list of 1',
        () async {
      final teamId = await makeTeam(name: 'Northside FC');
      await makeMatch(teamId: teamId, opponent: 'Rival FC', date: '2026-06-01');

      final rows =
          await db.teamsDao.watchUpcomingMatchesForUser(userId).first;
      expect(rows, hasLength(1));
      expect(rows.first.match.opponent, 'Rival FC');
      expect(rows.first.team.name, 'Northside FC');
    });

    test('reactivity on match insert: second upcoming match triggers re-emit',
        () async {
      final teamId = await makeTeam(name: 'Northside FC');
      await makeMatch(teamId: teamId, opponent: 'Alpha FC', date: '2026-06-01');

      final stream = db.teamsDao.watchUpcomingMatchesForUser(userId);

      // Collect two emissions.
      final emissions = <List<UpcomingMatchRow>>[];
      final subscription = stream.listen(emissions.add);

      // Give the first emission time to arrive.
      await Future<void>.delayed(Duration.zero);
      expect(emissions, hasLength(1));
      expect(emissions.first, hasLength(1));

      // Insert a second match — should trigger a second emission.
      await makeMatch(
        teamId: teamId,
        opponent: 'Beta FC',
        date: '2026-06-08',
      );
      await Future<void>.delayed(Duration.zero);

      await subscription.cancel();

      expect(emissions, hasLength(2));
      expect(emissions.last, hasLength(2));
    });

    test(
        'reactivity on match delete: deleting only match triggers empty emission',
        () async {
      final teamId = await makeTeam();
      final matchId =
          await makeMatch(teamId: teamId, opponent: 'Rival FC', date: '2026-06-01');

      final stream = db.teamsDao.watchUpcomingMatchesForUser(userId);

      final emissions = <List<UpcomingMatchRow>>[];
      final subscription = stream.listen(emissions.add);

      await Future<void>.delayed(Duration.zero);
      expect(emissions.last, hasLength(1));

      await db.teamsDao.deleteTeamMatch(matchId);
      await Future<void>.delayed(Duration.zero);

      await subscription.cancel();

      expect(emissions.last, isEmpty);
    });

    test('scoping: only returns rows for the specified userId', () async {
      final otherUserId = const Uuid().v4();
      await db.usersDao.insertUser(
        UsersTableCompanion.insert(id: otherUserId, name: 'Coach Other'),
      );

      final myTeamId = await makeTeam(name: 'My Team');
      final otherTeamId = await makeTeam(
        name: 'Other Team',
        ownerId: otherUserId,
      );

      await makeMatch(teamId: myTeamId, opponent: 'A', date: '2026-06-01');
      await makeMatch(teamId: otherTeamId, opponent: 'B', date: '2026-06-01');

      final rows =
          await db.teamsDao.watchUpcomingMatchesForUser(userId).first;
      expect(rows, hasLength(1));
      expect(rows.first.match.opponent, 'A');
    });

    test('hidden teams excluded', () async {
      final hiddenTeamId = await makeTeam(hidden: true);
      await makeMatch(
        teamId: hiddenTeamId,
        opponent: 'Hidden Rival',
        date: '2026-06-01',
      );

      final rows =
          await db.teamsDao.watchUpcomingMatchesForUser(userId).first;
      expect(rows, isEmpty);
    });

    test('kind=past excluded', () async {
      final teamId = await makeTeam();
      await makeMatch(
        teamId: teamId,
        opponent: 'Past Rival',
        date: '2026-05-01',
        kind: 'past',
      );

      final rows =
          await db.teamsDao.watchUpcomingMatchesForUser(userId).first;
      expect(rows, isEmpty);
    });

    test('ordering: two upcoming matches emit in ascending date order',
        () async {
      final teamId = await makeTeam();
      await makeMatch(teamId: teamId, opponent: 'Later', date: '2026-07-01');
      await makeMatch(teamId: teamId, opponent: 'Earlier', date: '2026-06-01');

      final rows =
          await db.teamsDao.watchUpcomingMatchesForUser(userId).first;
      expect(rows, hasLength(2));
      expect(rows[0].match.opponent, 'Earlier');
      expect(rows[1].match.opponent, 'Later');
    });
  });

  // ---------------------------------------------------------------------------
  // watchPastMatchesForLibrary
  // ---------------------------------------------------------------------------

  group('watchPastMatchesForLibrary', () {
    Future<String> makeTeam({String? name}) async {
      final id = const Uuid().v4();
      await db.teamsDao.insertTeam(
        TeamsTableCompanion.insert(
          id: id,
          userId: userId,
          name: name ?? 'Test FC',
          shortName: 'TFC',
          sport: 'Soccer',
        ),
      );
      return id;
    }

    Future<String> makeMatch({
      required String teamId,
      required String opponent,
      required String date,
      String kind = 'past',
    }) async {
      final id = const Uuid().v4();
      await db.teamsDao.insertTeamMatch(
        TeamMatchesTableCompanion.insert(
          id: id,
          teamId: teamId,
          opponent: opponent,
          date: date,
          result: 'W 2-0',
          kind: kind,
          numPeriods: 2,
          periodLengthSeconds: 45 * 60,
        ),
      );
      return id;
    }

    test('past match appears in result', () async {
      final teamId = await makeTeam(name: 'Northside FC');
      await makeMatch(
        teamId: teamId,
        opponent: 'Rival FC',
        date: '2026-05-01',
      );

      final rows = await db.teamsDao.watchPastMatchesForLibrary().first;
      expect(rows, hasLength(1));
      expect(rows.first.match.opponent, 'Rival FC');
      expect(rows.first.team.name, 'Northside FC');
    });

    test('upcoming match is excluded', () async {
      final teamId = await makeTeam();
      await makeMatch(
        teamId: teamId,
        opponent: 'Future FC',
        date: '2026-07-01',
        kind: 'upcoming',
      );

      final rows = await db.teamsDao.watchPastMatchesForLibrary().first;
      expect(rows, isEmpty);
    });

    test('DESC ordering by date is correct (newer match first)', () async {
      final teamId = await makeTeam();
      await makeMatch(teamId: teamId, opponent: 'Older', date: '2026-04-01');
      await makeMatch(teamId: teamId, opponent: 'Newer', date: '2026-05-01');

      final rows = await db.teamsDao.watchPastMatchesForLibrary().first;
      expect(rows, hasLength(2));
      expect(rows[0].match.opponent, 'Newer');
      expect(rows[1].match.opponent, 'Older');
    });

    test('mix of past and upcoming: only past returned', () async {
      final teamId = await makeTeam();
      await makeMatch(
        teamId: teamId,
        opponent: 'Past',
        date: '2026-04-01',
      );
      await makeMatch(
        teamId: teamId,
        opponent: 'Upcoming',
        date: '2026-07-01',
        kind: 'upcoming',
      );

      final rows = await db.teamsDao.watchPastMatchesForLibrary().first;
      expect(rows, hasLength(1));
      expect(rows.first.match.opponent, 'Past');
    });
  });
}
