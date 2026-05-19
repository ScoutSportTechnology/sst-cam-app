// Shared test harness. Provides `useInMemoryDb()` with a Drift in-memory
// [AppDatabase] seeded with the canonical dev data for DAO-level and
// controller tests. Registers setUp/tearDown automatically and returns
// the live instance for use in tests.

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sst_cam_app/db/app_database.dart';
import 'package:sst_cam_app/state/db_providers.dart';

export 'package:sst_cam_app/db/app_database.dart';

/// Registers setUp/tearDown that create and close a fresh Drift in-memory
/// [AppDatabase] for every test, seeded with the canonical dev data that
/// mirrors [DevDataStore._seed()]:
///
/// - user-1 "Coach Diego" (active), user-2 "Coach Maria"
/// - 4 teams + 7 players on nr-u14 under user-1
/// - 5 team_matches under nr-u14 (2 upcoming, 3 past)
/// - 7 built-in sport presets per user
/// - empty streaming destinations
///
/// Returns a [DbRef] whose `.value` is the live [AppDatabase] for the
/// current test. To wire the db into Riverpod, include
/// `appDatabaseProvider.overrideWithValue(db.value)` in your
/// [ProviderScope] overrides, or use the [dbOverrides] helper.
///
/// Use [db.value] inside test/setUp callbacks (after setUp has run).
DbRef useInMemoryDb() {
  final ref = DbRef();

  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    ref._db = AppDatabase.forTesting(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    await _seedInMemoryDb(ref._db);
  });

  tearDown(() => ref._db.close());

  return ref;
}

/// Mutable wrapper returned by [useInMemoryDb]. Access [value] inside a
/// test callback (after setUp has populated it).
class DbRef {
  late AppDatabase _db;

  /// The database for the current test. Must not be accessed before setUp.
  AppDatabase get value => _db;
}

/// Provides an override list for [ProviderScope] that wires [db] into
/// [appDatabaseProvider] (and therefore all DAO providers).
///
/// Accepts either an [AppDatabase] directly or a [DbRef] returned by
/// [useInMemoryDb]. In the latter case the [DbRef.value] is read lazily
/// inside each test callback, so it is always the instance created by setUp.
List<Override> dbOverrides(Object db) {
  final database = switch (db) {
    AppDatabase d => d,
    DbRef r => r.value,
    _ => throw ArgumentError('dbOverrides: expected AppDatabase or DbRef'),
  };
  return [appDatabaseProvider.overrideWithValue(database)];
}

// ---------------------------------------------------------------------------
// Seed helpers — mirrors DevDataStore._seed() exactly.
// ---------------------------------------------------------------------------

Future<void> _seedInMemoryDb(AppDatabase db) async {
  // Remove the default-user inserted by AppDatabase._seedBaseData() so tests
  // operate with only their own explicitly-seeded users. FK cascade removes
  // the associated sport presets automatically.
  await db.usersDao.deleteById('default-user');

  // Users
  await db.usersDao.insertUser(
    UsersTableCompanion.insert(id: 'user-1', name: 'Coach Diego'),
  );
  await db.usersDao.insertUser(
    UsersTableCompanion.insert(id: 'user-2', name: 'Coach Maria'),
  );

  // Teams under user-1
  await db.teamsDao.insertTeam(
    TeamsTableCompanion.insert(
      id: 'nr-u14',
      userId: 'user-1',
      name: 'Northside Rovers U14',
      shortName: 'NRA',
      sport: 'Soccer',
    ),
  );
  await db.teamsDao.insertTeam(
    TeamsTableCompanion.insert(
      id: 'nr-u12',
      userId: 'user-1',
      name: 'Northside Rovers U12',
      shortName: 'NRB',
      sport: 'Soccer',
    ),
  );
  await db.teamsDao.insertTeam(
    TeamsTableCompanion.insert(
      id: 'efc-r',
      userId: 'user-1',
      name: 'Eastfield FC Reserves',
      shortName: 'EFC',
      sport: 'Soccer',
    ),
  );
  await db.teamsDao.insertTeam(
    TeamsTableCompanion.insert(
      id: 'rd-utd',
      userId: 'user-1',
      name: 'Riverdale United',
      shortName: 'RDU',
      sport: 'Soccer',
    ),
  );

  // Roster for nr-u14
  const nrU14Players = [
    (number: 7, name: 'A. Patel', position: 'Forward', captain: true),
    (number: 10, name: 'B. Okafor', position: 'Mid', captain: false),
    (number: 4, name: 'C. Nguyen', position: 'Defender', captain: false),
    (number: 1, name: 'D. Reyes', position: 'Keeper', captain: false),
    (number: 11, name: 'E. Mahmoud', position: 'Forward', captain: false),
    (number: 8, name: 'F. Lopez', position: 'Mid', captain: false),
    (number: 5, name: 'G. Singh', position: 'Defender', captain: false),
  ];
  for (final p in nrU14Players) {
    await db.teamsDao.insertPlayer(
      PlayersTableCompanion.insert(
        teamId: 'nr-u14',
        number: p.number,
        name: p.name,
        position: p.position,
        captain: Value(p.captain),
      ),
    );
  }

  // Team matches under nr-u14
  await db.teamsDao.insertTeamMatch(
    TeamMatchesTableCompanion.insert(
      id: 'nr-u14-up1',
      teamId: 'nr-u14',
      opponent: 'vs Eastfield FC',
      date: 'May 11',
      result: '',
      kind: 'upcoming',
      numPeriods: 2,
      periodLengthSeconds: 35 * 60,
    ),
  );
  await db.teamsDao.insertTeamMatch(
    TeamMatchesTableCompanion.insert(
      id: 'nr-u14-up2',
      teamId: 'nr-u14',
      opponent: 'vs Lakeside',
      date: 'May 18',
      result: '',
      kind: 'upcoming',
      numPeriods: 2,
      periodLengthSeconds: 35 * 60,
    ),
  );
  await db.teamsDao.insertTeamMatch(
    TeamMatchesTableCompanion.insert(
      id: 'nr-u14-m1',
      teamId: 'nr-u14',
      opponent: 'vs Eastfield FC',
      date: 'Mar 12',
      result: 'W 3–1',
      kind: 'past',
      numPeriods: 2,
      periodLengthSeconds: 35 * 60,
      clips: const Value(2),
      sizeMb: const Value(380),
    ),
  );
  await db.teamsDao.insertTeamMatch(
    TeamMatchesTableCompanion.insert(
      id: 'nr-u14-m2',
      teamId: 'nr-u14',
      opponent: 'vs Riverdale Utd',
      date: 'Mar 05',
      result: 'L 0–2',
      kind: 'past',
      numPeriods: 2,
      periodLengthSeconds: 35 * 60,
      clips: const Value(2),
      sizeMb: const Value(180),
    ),
  );
  await db.teamsDao.insertTeamMatch(
    TeamMatchesTableCompanion.insert(
      id: 'nr-u14-m3',
      teamId: 'nr-u14',
      opponent: 'vs Lakeside',
      date: 'Feb 26',
      result: 'D 1–1',
      kind: 'past',
      numPeriods: 2,
      periodLengthSeconds: 35 * 60,
      clips: const Value(2),
      sizeMb: const Value(540),
    ),
  );

  // Sport presets — 7 built-ins per user. IDs are user-scoped so seeding
  // multiple users is safe (no collision between user-1 and user-2 rows).
  await db.sportPresetsDao.seedBuiltInsForUser('user-1');
  await db.sportPresetsDao.seedBuiltInsForUser('user-2');
}
