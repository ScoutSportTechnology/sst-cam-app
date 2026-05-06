import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'daos/sport_presets_dao.dart';
import 'daos/streaming_destinations_dao.dart';
import 'daos/teams_dao.dart';
import 'daos/users_dao.dart';
import 'tables/clips_table.dart';
import 'tables/sport_presets_table.dart';
import 'tables/streaming_destinations_table.dart';
import 'tables/team_matches_table.dart';
import 'tables/teams_table.dart';
import 'tables/thumbnails_table.dart';
import 'tables/users_table.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [
    UsersTable,
    TeamsTable,
    PlayersTable,
    TeamMatchesTable,
    SportPresetsTable,
    StreamingDestinationsTable,
    ClipsTable,
    ThumbnailsTable,
  ],
  daos: [UsersDao, TeamsDao, SportPresetsDao, StreamingDestinationsDao],
)
class AppDatabase extends _$AppDatabase {
  /// Production constructor: opens or creates the SQLite file on disk.
  /// [LazyDatabase] defers the actual file open to the first query so the
  /// constructor itself is synchronous — safe to use in a Riverpod
  /// `Provider<AppDatabase>`.
  AppDatabase() : super(_openConnection());

  /// Testing constructor: accepts any [QueryExecutor] so tests can pass
  /// `NativeDatabase.memory()` wrapped in a [DatabaseConnection] for a
  /// fast, fully isolated in-memory database.
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      // Fix 16: Add indexes on FK columns used as primary query filters.
      await customStatement('CREATE INDEX idx_teams_user_id ON teams(user_id)');
      await customStatement(
        'CREATE INDEX idx_sport_presets_user_id ON sport_presets(user_id)',
      );
      await customStatement(
        'CREATE INDEX idx_streaming_destinations_user_id '
        'ON streaming_destinations(user_id)',
      );
      await customStatement(
        'CREATE INDEX idx_team_matches_team_id ON team_matches(team_id)',
      );
      await customStatement(
        'CREATE INDEX idx_players_team_id ON players(team_id)',
      );
      await customStatement(
        'CREATE INDEX idx_clips_match_id ON clips(match_id)',
      );
      // Built-in presets are seeded per-user at user creation time
      // (SportPresetsDao.seedBuiltInsForUser), not globally here.
    },
    beforeOpen: (details) async {
      // SQLite disables FK enforcement by default. Enable it for every
      // connection so cascades, restrict constraints, and FK checks work.
      await customStatement('PRAGMA foreign_keys = ON;');
      await customStatement('PRAGMA journal_mode = WAL;');
    },
  );
}

/// Opens (or creates) the application SQLite database file.
///
/// [LazyDatabase] + [NativeDatabase.createInBackground] keeps the heavy
/// file-open work off the main isolate while still allowing the
/// [AppDatabase] constructor to complete synchronously.
LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    // Fix 10: Use getApplicationSupportDirectory so the SQLite file is stored
    // in the app-private support directory (not in Documents, which is
    // user-visible and backed up by iCloud/Google Drive).
    final dir = await getApplicationSupportDirectory();
    final file = File(p.join(dir.path, 'scout_camera.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
