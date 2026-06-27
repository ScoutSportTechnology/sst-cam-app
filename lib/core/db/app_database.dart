import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../config/app_config.dart';
import 'daos/clips_dao.dart';
import 'daos/raw_recordings_dao.dart';
import 'daos/sport_presets_dao.dart';
import 'daos/streaming_destinations_dao.dart';
import 'daos/teams_dao.dart';
import 'daos/users_dao.dart';
import 'tables/clips_table.dart';
import 'tables/raw_recordings_table.dart';
import 'tables/sport_presets_table.dart';
import 'tables/streaming_destinations_table.dart';
import 'tables/team_matches_table.dart';
import 'tables/teams_table.dart';
import 'tables/thumbnails_table.dart';
import 'tables/users_table.dart';

part 'app_database.g.dart';

/// Stable UUID for the seeded starter user. A fixed sentinel (not a random v4)
/// so the static seed fixtures that reference it stay linked across reseeds.
/// Real users created in Settings get their own generated UUIDs.
const kDefaultUserId = '00000000-0000-0000-0000-000000000001';

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
    RawRecordingsTable,
  ],
  daos: [
    UsersDao,
    TeamsDao,
    SportPresetsDao,
    StreamingDestinationsDao,
    ClipsDao,
    RawRecordingsDao,
  ],
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
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await transaction(() async {
        await m.createAll();
        // Add indexes on FK columns used as primary query filters.
        await customStatement(
          'CREATE INDEX idx_teams_user_id ON teams(user_id)',
        );
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
        await customStatement(
          'CREATE INDEX idx_raw_recordings_capture_group_id '
          'ON raw_recordings(capture_group_id)',
        );
        // Seed minimum viable state: one default user + all built-in sport
        // presets. This runs unconditionally — the app must always have at
        // least one user and the preset list populated for core flows to work.
        await _seedBaseData();
      });
    },
    onUpgrade: (m, from, to) async {
      await transaction(() async {
        if (from < 2) {
          // v1→v2: add start_seconds + label to clips; events_json to team_matches.
          await customStatement(
            'ALTER TABLE clips ADD COLUMN start_seconds INTEGER NOT NULL DEFAULT 0',
          );
          await customStatement('ALTER TABLE clips ADD COLUMN label TEXT');
          await customStatement(
            "ALTER TABLE team_matches ADD COLUMN events_json TEXT NOT NULL DEFAULT '[]'",
          );
          await customStatement(
            "UPDATE users SET name = 'Coach' WHERE id = 'default-user' AND name = 'default'",
          );
        }
        if (from < 3) {
          // v2→v3: add color_hex to teams.
          await customStatement('ALTER TABLE teams ADD COLUMN color_hex TEXT');
        }
        if (from < 4) {
          // v3→v4: add raw_recordings (raw dual-camera capture metadata).
          await m.createTable(rawRecordingsTable);
          await customStatement(
            'CREATE INDEX idx_raw_recordings_capture_group_id '
            'ON raw_recordings(capture_group_id)',
          );
        }
      });
    },
    beforeOpen: (details) async {
      // SQLite disables FK enforcement by default. Enable it for every
      // connection so cascades, restrict constraints, and FK checks work.
      await customStatement('PRAGMA foreign_keys = ON;');
      await customStatement('PRAGMA journal_mode = WAL;');
    },
  );

  /// Seeds the default user and built-in sport presets.
  ///
  /// Safe to call multiple times — uses insertOnConflictUpdate internally.
  Future<void> _seedBaseData() async {
    await usersDao.insertUser(
      UsersTableCompanion.insert(id: kDefaultUserId, name: 'Coach'),
    );
    await sportPresetsDao.seedBuiltInsForUser(kDefaultUserId);
  }

  /// Re-seeds base data after a manual reset (e.g., from the debug screen).
  /// Public so the debug screen can call it after wiping the DB.
  Future<void> seedBaseData() => _seedBaseData();
}

/// Opens (or creates) the application SQLite database file.
///
/// [LazyDatabase] + [NativeDatabase.createInBackground] keeps the heavy
/// file-open work off the main isolate while still allowing the
/// [AppDatabase] constructor to complete synchronously.
LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    // Use getApplicationSupportDirectory so the SQLite file is stored in the
    // app-private support directory (not in Documents, which is user-visible
    // and backed up by iCloud/Google Drive).
    final dir = await getApplicationSupportDirectory();
    // One-time migration: rename the old scout_camera.sqlite to kDbName so
    // existing installs keep their data after the app rename.
    final oldFile = File(p.join(dir.path, 'scout_camera.sqlite'));
    final file = File(p.join(dir.path, kDbName));
    if (oldFile.existsSync() && !file.existsSync()) {
      await oldFile.rename(file.path);
    }
    return NativeDatabase.createInBackground(file);
  });
}
