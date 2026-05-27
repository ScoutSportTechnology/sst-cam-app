import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:sst_cam_app/core/config/dev_config.dart';
import 'package:sst_cam_app/core/db/app_database.dart';
import 'package:sst_cam_app/mock/seed/data_mode.dart';

class _FakePathProvider
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  final String tempPath;
  _FakePathProvider(this.tempPath);

  @override
  Future<String?> getApplicationSupportPath() async => tempPath;
  @override
  Future<String?> getTemporaryPath() async => tempPath;
  @override
  Future<String?> getApplicationDocumentsPath() async => tempPath;
  @override
  Future<String?> getApplicationCachePath() async => tempPath;
  @override
  Future<String?> getExternalStoragePath() async => null;
  @override
  Future<List<String>?> getExternalCachePaths() async => null;
  @override
  Future<List<String>?> getExternalStoragePaths({StorageDirectory? type}) async =>
      null;
  @override
  Future<String?> getDownloadsPath() async => null;
  @override
  Future<String?> getLibraryPath() async => tempPath;
}

void main() {
  setUpAll(TestWidgetsFlutterBinding.ensureInitialized);

  late AppDatabase db;
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('data_mode_test_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    db = AppDatabase.forTesting(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
  });

  tearDown(() async {
    await db.close();
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  group('applyDataMode', () {
    test('full mode seeds teams and matches', () async {
      await applyDataMode(db, DataMode.full);
      expect(await db.select(db.teamsTable).get(), isNotEmpty);
      expect(await db.select(db.teamMatchesTable).get(), isNotEmpty);
    });

    test('seed mode seeds teams and matches', () async {
      await applyDataMode(db, DataMode.seed);
      expect(await db.select(db.teamsTable).get(), isNotEmpty);
      expect(await db.select(db.teamMatchesTable).get(), isNotEmpty);
    });

    test('empty mode wipes fixtures but keeps base user', () async {
      // Seed first so there is something to wipe.
      await applyDataMode(db, DataMode.full);
      expect(await db.select(db.teamMatchesTable).get(), isNotEmpty);

      await applyDataMode(db, DataMode.empty);
      expect(
        await db.select(db.teamsTable).get(),
        isEmpty,
        reason: 'empty mode must wipe seeded teams',
      );
      expect(
        await db.select(db.teamMatchesTable).get(),
        isEmpty,
        reason: 'empty mode must wipe seeded matches',
      );
      expect(
        await db.select(db.usersTable).get(),
        isNotEmpty,
        reason: 'base data (default user) must remain so the app boots',
      );
    });
  });
}
