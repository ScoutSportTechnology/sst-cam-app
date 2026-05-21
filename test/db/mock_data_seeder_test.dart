import 'package:drift/native.dart';
import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sst_cam_app/core/db/app_database.dart';
import 'package:sst_cam_app/mock/mock_data_seeder.dart';

void main() {
  // rootBundle requires the Flutter binding to be initialised.
  setUpAll(TestWidgetsFlutterBinding.ensureInitialized);

  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
  });

  tearDown(() => db.close());

  group('MockDataSeeder', () {
    test('seed() inserts expected teams, matches, players, and destinations',
        () async {
      // AppDatabase.forTesting runs onCreate which seeds the default user.
      await MockDataSeeder(db).seed();

      final teams = await db.select(db.teamsTable).get();
      expect(teams, hasLength(2), reason: 'fixtures/teams.json has 2 teams');

      final matches = await db.select(db.teamMatchesTable).get();
      expect(matches, hasLength(4), reason: 'fixtures/matches.json has 4 matches');

      final players = await db.select(db.playersTable).get();
      expect(players, hasLength(25), reason: 'fixtures/players.json has 25 players');

      final destinations =
          await db.select(db.streamingDestinationsTable).get();
      expect(destinations, hasLength(1),
          reason: 'fixtures/streaming_destinations.json has 1 destination');
    });

    test('calling seed() twice is idempotent (no exception, no duplicates)',
        () async {
      await MockDataSeeder(db).seed();
      // Second call should use insertOnConflictUpdate — no exception expected.
      await MockDataSeeder(db).seed();

      final teams = await db.select(db.teamsTable).get();
      expect(teams, hasLength(2));

      final matches = await db.select(db.teamMatchesTable).get();
      expect(matches, hasLength(4));

      final players = await db.select(db.playersTable).get();
      expect(players, hasLength(25));
    });
  });
}
