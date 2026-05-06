import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/app_database.dart';
import '../db/daos/users_dao.dart';
import '../db/daos/teams_dao.dart';
import '../db/daos/sport_presets_dao.dart';
import '../db/daos/streaming_destinations_dao.dart';

// ---------------------------------------------------------------------------
// Database — single instance, lazy-opened via LazyDatabase.
// Tests override via appDatabaseProvider.overrideWithValue(AppDatabase.forTesting(...))
// ---------------------------------------------------------------------------

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

// ---------------------------------------------------------------------------
// Per-DAO providers — thin wrappers so controllers never reference AppDatabase
// directly.
// ---------------------------------------------------------------------------

final usersDaoProvider = Provider<UsersDao>((ref) {
  return ref.watch(appDatabaseProvider).usersDao;
});

final teamsDaoProvider = Provider<TeamsDao>((ref) {
  return ref.watch(appDatabaseProvider).teamsDao;
});

final sportPresetsDaoProvider = Provider<SportPresetsDao>((ref) {
  return ref.watch(appDatabaseProvider).sportPresetsDao;
});

final streamingDestinationsDaoProvider =
    Provider<StreamingDestinationsDao>((ref) {
      return ref.watch(appDatabaseProvider).streamingDestinationsDao;
    });
