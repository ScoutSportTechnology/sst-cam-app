import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:sst_cam_app/core/db/app_database.dart';
import 'package:sst_cam_app/core/services/video_path_service.dart';
import 'package:sst_cam_app/mock/internal/mock_data_service.dart';

// ---------------------------------------------------------------------------
// Fake path_provider that uses a temp directory for tests.
// ---------------------------------------------------------------------------
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
  Future<List<String>?> getExternalStoragePaths({
    StorageDirectory? type,
  }) async => null;
  @override
  Future<String?> getDownloadsPath() async => null;
  @override
  Future<String?> getLibraryPath() async => tempPath;
}

// Port 1 has nothing serving recordings → the HTTP fetch fails fast so the
// seeder exercises its bundled/sentinel fallback instead of hitting a real
// mock-camera container that may be running on localhost:8080.
const _unreachableBase = 'http://127.0.0.1:1';

MockDataSeeder _seeder(AppDatabase db, {VideoPathService? videoPathService}) =>
    MockDataSeeder(
      db,
      downloadBaseUrl: _unreachableBase,
      videoPathService: videoPathService,
    );

void main() {
  // rootBundle requires the Flutter binding to be initialised.
  setUpAll(TestWidgetsFlutterBinding.ensureInitialized);

  late AppDatabase db;
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('mock_data_service_test_');
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

  group('applySeedData', () {
    test('seed=true seeds teams and matches', () async {
      await applySeedData(db, seed: true, downloadBaseUrl: _unreachableBase);
      expect(await db.select(db.teamsTable).get(), isNotEmpty);
      expect(await db.select(db.teamMatchesTable).get(), isNotEmpty);
    });

    test('seed=false wipes fixtures but keeps base user', () async {
      // Seed first so there is something to wipe.
      await applySeedData(db, seed: true, downloadBaseUrl: _unreachableBase);
      expect(await db.select(db.teamMatchesTable).get(), isNotEmpty);

      await applySeedData(db, seed: false);
      expect(
        await db.select(db.teamsTable).get(),
        isEmpty,
        reason: 'seed=false must wipe seeded teams',
      );
      expect(
        await db.select(db.teamMatchesTable).get(),
        isEmpty,
        reason: 'seed=false must wipe seeded matches',
      );
      expect(
        await db.select(db.usersTable).get(),
        isNotEmpty,
        reason: 'base data (default user) must remain so the app boots',
      );
    });

    test('seed=false deletes on-device past-match video files (AE3)', () async {
      final videoPathService = VideoPathService();
      await applySeedData(
        db,
        seed: true,
        downloadBaseUrl: _unreachableBase,
        videoPathService: videoPathService,
      );

      final onDeviceMatches =
          await (db.select(db.teamMatchesTable)..where(
                (t) => t.kind.equals('past') & t.sizeMb.isBiggerThanValue(0),
              ))
              .get();
      expect(onDeviceMatches, isNotEmpty);
      final paths = [
        for (final m in onDeviceMatches)
          await videoPathService.recordingPath(m.id),
      ];
      for (final p in paths) {
        expect(File(p).existsSync(), isTrue, reason: 'seed should create $p');
      }

      await applySeedData(db, seed: false, videoPathService: videoPathService);

      for (final p in paths) {
        expect(
          File(p).existsSync(),
          isFalse,
          reason: 'seed=false must delete the on-device video file $p',
        );
      }
    });
  });

  group('MockDataSeeder', () {
    test(
      'seed() inserts expected teams, matches, players, and destinations',
      () async {
        await _seeder(db).seed();

        final teams = await db.select(db.teamsTable).get();
        expect(teams, hasLength(8), reason: 'fixtures/teams.json has 8 teams');

        final matches = await db.select(db.teamMatchesTable).get();
        expect(
          matches,
          hasLength(8),
          reason: 'fixtures/matches.json has 8 matches total',
        );

        final players = await db.select(db.playersTable).get();
        expect(
          players,
          hasLength(25),
          reason: 'fixtures/players.json has 25 players',
        );

        final destinations = await db
            .select(db.streamingDestinationsTable)
            .get();
        expect(
          destinations,
          hasLength(1),
          reason: 'fixtures/streaming_destinations.json has 1 destination',
        );
      },
    );

    test('NR team has 4 past matches and 1 upcoming', () async {
      await _seeder(db).seed();

      final nrMatches = await (db.select(
        db.teamMatchesTable,
      )..where((t) => t.teamId.equals('mock-team-nr-u14'))).get();
      expect(nrMatches, hasLength(5));

      final nrPast = nrMatches.where((m) => m.kind == 'past').toList();
      expect(nrPast, hasLength(4), reason: 'NR has 4 past matches');

      final nrUpcoming = nrMatches.where((m) => m.kind == 'upcoming').toList();
      expect(nrUpcoming, hasLength(1), reason: 'NR has 1 upcoming match');
    });

    test('EFC team has 3 past matches', () async {
      await _seeder(db).seed();

      final efcMatches = await (db.select(
        db.teamMatchesTable,
      )..where((t) => t.teamId.equals('mock-team-efc-u14'))).get();
      expect(efcMatches, hasLength(3), reason: 'EFC has 3 matches');

      final efcPast = efcMatches.where((m) => m.kind == 'past').toList();
      expect(efcPast, hasLength(3), reason: 'All EFC matches are past');
    });

    test(
      'EFC has at least one match against Northridge U14 (cross-team search AE4)',
      () async {
        await _seeder(db).seed();

        final efcVsNR =
            await (db.select(db.teamMatchesTable)..where(
                  (t) =>
                      t.teamId.equals('mock-team-efc-u14') &
                      t.opponent.equals('Northridge U14'),
                ))
                .get();
        expect(
          efcVsNR,
          isNotEmpty,
          reason: 'EFC must have at least one match vs Northridge U14',
        );
      },
    );

    test('opponent fields have no "vs " prefix', () async {
      await _seeder(db).seed();

      final matches = await db.select(db.teamMatchesTable).get();
      for (final match in matches) {
        expect(
          match.opponent.startsWith('vs '),
          isFalse,
          reason: 'opponent "${match.opponent}" must not start with "vs "',
        );
      }
    });

    test(
      'placeholder file exists for every on-device past match (sizeMb > 0)',
      () async {
        final videoPathService = VideoPathService();
        await _seeder(db, videoPathService: videoPathService).seed();

        final onDeviceMatches =
            await (db.select(db.teamMatchesTable)..where(
                  (t) => t.kind.equals('past') & t.sizeMb.isBiggerThanValue(0),
                ))
                .get();

        expect(
          onDeviceMatches,
          isNotEmpty,
          reason: 'at least one on-device match must exist',
        );

        for (final match in onDeviceMatches) {
          final path = await videoPathService.recordingPath(match.id);
          expect(
            File(path).existsSync(),
            isTrue,
            reason: 'placeholder file missing for on-device match ${match.id}',
          );
        }
      },
    );

    test(
      'no placeholder file for camera-only past matches (sizeMb == 0)',
      () async {
        final videoPathService = VideoPathService();
        await _seeder(db, videoPathService: videoPathService).seed();

        final cameraOnlyMatches = await (db.select(
          db.teamMatchesTable,
        )..where((t) => t.kind.equals('past') & t.sizeMb.equals(0))).get();

        expect(
          cameraOnlyMatches,
          isNotEmpty,
          reason: 'at least one camera-only past match must exist',
        );

        for (final match in cameraOnlyMatches) {
          final path = await videoPathService.recordingPath(match.id);
          expect(
            File(path).existsSync(),
            isFalse,
            reason:
                'unexpected placeholder file found for camera-only match ${match.id}',
          );
        }
      },
    );

    test(
      'calling seed() twice is idempotent (no exception, no duplicates)',
      () async {
        final videoPathService = VideoPathService();
        await _seeder(db, videoPathService: videoPathService).seed();
        // Second call should use insertOnConflictUpdate — no exception expected.
        await _seeder(db, videoPathService: videoPathService).seed();

        final teams = await db.select(db.teamsTable).get();
        expect(teams, hasLength(8));

        final matches = await db.select(db.teamMatchesTable).get();
        expect(matches, hasLength(8));

        final players = await db.select(db.playersTable).get();
        expect(players, hasLength(25));

        // Placeholder files should still exist, not be duplicated or corrupted.
        final onDeviceMatches =
            await (db.select(db.teamMatchesTable)..where(
                  (t) => t.kind.equals('past') & t.sizeMb.isBiggerThanValue(0),
                ))
                .get();
        for (final match in onDeviceMatches) {
          final path = await videoPathService.recordingPath(match.id);
          expect(
            File(path).existsSync(),
            isTrue,
            reason:
                'video file missing after double seed for match ${match.id}',
          );
          // The seeder copies the actual mock video (not a 1-byte sentinel).
          // In test environments rootBundle may fall back to 1-byte, but the
          // file must exist and double-seeding must not corrupt it (idempotent).
          expect(
            File(path).lengthSync(),
            greaterThanOrEqualTo(1),
            reason: 'video file for ${match.id} should exist and not be empty',
          );
        }
      },
    );
  });
}
