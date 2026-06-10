import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/app_database.dart';
import '../db/daos/clips_dao.dart';
import '../db/daos/raw_recordings_dao.dart';
import '../db/daos/users_dao.dart';
import '../db/daos/teams_dao.dart';
import '../db/daos/sport_presets_dao.dart';
import '../db/daos/streaming_destinations_dao.dart';
import '../services/backup_service.dart';
import '../services/clip_service.dart';
import '../services/video_path_service.dart';
import '../ble/ble_providers.dart';

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

final streamingDestinationsDaoProvider = Provider<StreamingDestinationsDao>((
  ref,
) {
  return ref.watch(appDatabaseProvider).streamingDestinationsDao;
});

// ---------------------------------------------------------------------------
final rawRecordingsDaoProvider = Provider<RawRecordingsDao>((ref) {
  return ref.watch(appDatabaseProvider).rawRecordingsDao;
});

final clipsDaoProvider = Provider<ClipsDao>((ref) {
  return ref.watch(appDatabaseProvider).clipsDao;
});

// BackupService — wired to appDatabaseProvider and bleServiceProvider so the
// widget just reads this provider. Tests override it to inject a stub.
// ---------------------------------------------------------------------------

final backupServiceProvider = Provider<BackupService>((ref) {
  return BackupService(
    ref.watch(appDatabaseProvider),
    ble: ref.watch(bleServiceProvider),
  );
});

final videoPathServiceProvider = Provider<VideoPathService>((ref) {
  return VideoPathService();
});

final clipServiceProvider = Provider<ClipService>((ref) {
  return ClipService(
    clipsDao: ref.watch(clipsDaoProvider),
    videoPathService: ref.watch(videoPathServiceProvider),
  );
});
