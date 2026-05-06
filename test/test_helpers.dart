// Shared test harness. Every BLE / state / page / integration test that
// touches DevDataStore directly or transitively imports this and calls
// `useDevDataStoreReset()` at the top of its `main()` so the
// process-global store can't leak across tests when `flutter test` runs
// them in the same isolate.
//
// `useInMemoryDb()` provides a Drift in-memory [AppDatabase] seeded with
// the same data as [DevDataStore._seed()] for DAO-level and controller
// tests that talk to the database directly. It registers setUp/tearDown
// automatically and returns the live instance for use in tests.

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scout_camera/ble/dev_data_store.dart';
import 'package:scout_camera/db/app_database.dart';
import 'package:scout_camera/state/db_providers.dart';

export 'package:scout_camera/db/app_database.dart';

/// Registers a `setUp` that resets the process-global [DevDataStore]
/// before every test in the enclosing group / file.
void useDevDataStoreReset() {
  setUp(() {
    DevDataStore.instance.reset();
  });
}

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
/// Returns the late-initialised [AppDatabase] so tests can call DAOs
/// directly. To wire the db into Riverpod, include
/// `appDatabaseProvider.overrideWithValue(db)` in your [ProviderScope]
/// overrides.
AppDatabase useInMemoryDb() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    await _seedInMemoryDb(db);
  });

  tearDown(() => db.close());

  // ignore: invalid_use_of_visible_for_testing_member
  return db;
}

/// Provides an override list for [ProviderScope] that wires [db] into
/// [appDatabaseProvider] (and therefore all DAO providers).
List<Override> dbOverrides(AppDatabase db) => [
  appDatabaseProvider.overrideWithValue(db),
];

// ---------------------------------------------------------------------------
// Seed helpers — mirrors DevDataStore._seed() exactly.
// ---------------------------------------------------------------------------

Future<void> _seedInMemoryDb(AppDatabase db) async {
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

  // Sport presets — 7 built-ins per user
  await db.sportPresetsDao.seedBuiltInsForUser('user-1');
  await db.sportPresetsDao.seedBuiltInsForUser('user-2');
}
