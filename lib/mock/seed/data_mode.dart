import '../../core/config/dev_config.dart';
import '../../core/db/app_database.dart';
import 'mock_data_seeder.dart';

/// Applies [mode] to the local database at dev startup:
///
/// - [DataMode.empty] → wipe all rows back to base scaffolding (default user
///   + sport presets) so the app still boots with a clean slate.
/// - [DataMode.seed] / [DataMode.full] → insert mock fixtures (teams, matches,
///   players, streaming destinations, on-device videos).
///
/// Lives under `lib/mock/` so it and its [MockDataSeeder] dependency are
/// excluded from stage/prod builds — only `main.dart` (dev) imports it.
Future<void> applyDataMode(AppDatabase db, DataMode mode) async {
  switch (mode) {
    case DataMode.empty:
      await _wipeToBaseData(db);
    case DataMode.seed:
    case DataMode.full:
      await MockDataSeeder(db).seed();
  }
}

Future<void> _wipeToBaseData(AppDatabase db) async {
  await db.transaction(() async {
    await db.delete(db.clipsTable).go(); // cascade-deletes thumbnails
    await db.delete(db.teamMatchesTable).go();
    await db.delete(db.playersTable).go();
    await db.delete(db.teamsTable).go();
    await db.delete(db.streamingDestinationsTable).go();
    await db.delete(db.sportPresetsTable).go();
    await db.delete(db.usersTable).go();
  });
  // Re-seed the base scaffolding (default user + built-in presets) so provider
  // scopes that require an active user keep working.
  await db.seedBaseData();
}
