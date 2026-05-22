// Unit tests for video_state.dart — LibraryMatch new fields, new providers.
//
// Seed data recap (from test_helpers.dart):
//   - user-1: 4 Soccer teams; 3 past matches under nr-u14 (sizeMb > 0),
//     no past matches under nr-u12 / efc-r / rd-utd by default.
//   - nr-u14 name: 'Northside Rovers U14', shortName: 'NRA', sport: 'Soccer'

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sst_cam_app/mock/mock_ble_service.dart';
import 'package:sst_cam_app/core/ble/ble_providers.dart';
import 'package:sst_cam_app/core/services/video_path_service.dart';
import 'package:sst_cam_app/core/state/db_providers.dart';
import 'package:sst_cam_app/features/settings/users/users_state.dart'
    show activeUserProvider;
import 'package:sst_cam_app/features/video/video_state.dart';

import '../../test_helpers.dart';

MockBleService _newMock() => MockBleService(
      scanDeviceAppearDelays: const [Duration.zero],
      connectionDelay: Duration.zero,
      failureRate: 0.0,
      randomSeed: 42,
    );

ProviderContainer _makeContainer(AppDatabase db, {List<Override> extra = const []}) {
  final c = ProviderContainer(
    overrides: [
      ...dbOverrides(db),
      bleServiceProvider.overrideWithValue(_newMock()),
      activeUserProvider.overrideWith((_) => 'user-1'),
      ...extra,
    ],
  );
  addTearDown(c.dispose);
  return c;
}

// ---------------------------------------------------------------------------
// Helper: wait until libraryProvider has at least [count] entries.
// ---------------------------------------------------------------------------
Future<void> _awaitLibrary(
  ProviderContainer c,
  AppDatabase db, {
  int count = 1,
}) async {
  for (var i = 0; i < 30; i++) {
    await Future<void>.delayed(Duration.zero);
    final lib = c.read(libraryProvider).valueOrNull ?? const [];
    if (lib.length >= count) break;
  }
}

void main() {
  final db = useInMemoryDb();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  // ---------------------------------------------------------------------------
  // LibraryMatch field population
  // ---------------------------------------------------------------------------

  group('LibraryMatch field population', () {
    test('teamName equals team.name', () async {
      final c = _makeContainer(db.value);
      c.listen(libraryProvider, (_, __) {});

      await db.value.teamsDao.insertTeamMatch(
        TeamMatchesTableCompanion.insert(
          id: 'vst-m1',
          teamId: 'nr-u14',
          opponent: 'vs Alpha',
          date: 'Apr 10',
          result: 'W 2-0',
          kind: 'past',
          numPeriods: 2,
          periodLengthSeconds: 35 * 60,
          sizeMb: const Value(200),
        ),
      );

      await _awaitLibrary(c, db.value);

      final lib = c.read(libraryProvider).valueOrNull ?? const [];
      final match = lib.firstWhere((m) => m.id == 'vst-m1');
      expect(match.teamName, equals('Northside Rovers U14'));
    });

    test('teamShortName equals team.shortName', () async {
      final c = _makeContainer(db.value);
      c.listen(libraryProvider, (_, __) {});

      await db.value.teamsDao.insertTeamMatch(
        TeamMatchesTableCompanion.insert(
          id: 'vst-m2',
          teamId: 'nr-u14',
          opponent: 'vs Beta',
          date: 'Apr 11',
          result: 'L 0-1',
          kind: 'past',
          numPeriods: 2,
          periodLengthSeconds: 35 * 60,
          sizeMb: const Value(100),
        ),
      );

      await _awaitLibrary(c, db.value);

      final lib = c.read(libraryProvider).valueOrNull ?? const [];
      final match = lib.firstWhere((m) => m.id == 'vst-m2');
      expect(match.teamShortName, equals('NRA'));
    });

    test('periodLengthSeconds equals match.periodLengthSeconds', () async {
      final c = _makeContainer(db.value);
      c.listen(libraryProvider, (_, __) {});

      await db.value.teamsDao.insertTeamMatch(
        TeamMatchesTableCompanion.insert(
          id: 'vst-m3',
          teamId: 'nr-u14',
          opponent: 'vs Gamma',
          date: 'Apr 12',
          result: 'D 1-1',
          kind: 'past',
          numPeriods: 2,
          periodLengthSeconds: 45 * 60,
          sizeMb: const Value(250),
        ),
      );

      await _awaitLibrary(c, db.value);

      final lib = c.read(libraryProvider).valueOrNull ?? const [];
      final match = lib.firstWhere((m) => m.id == 'vst-m3');
      expect(match.periodLengthSeconds, equals(45 * 60));
    });

    test('sport equals team.sport', () async {
      final c = _makeContainer(db.value);
      c.listen(libraryProvider, (_, __) {});

      await db.value.teamsDao.insertTeamMatch(
        TeamMatchesTableCompanion.insert(
          id: 'vst-m4',
          teamId: 'nr-u14',
          opponent: 'vs Delta',
          date: 'Apr 13',
          result: 'W 3-0',
          kind: 'past',
          numPeriods: 2,
          periodLengthSeconds: 35 * 60,
          sizeMb: const Value(300),
        ),
      );

      await _awaitLibrary(c, db.value);

      final lib = c.read(libraryProvider).valueOrNull ?? const [];
      final match = lib.firstWhere((m) => m.id == 'vst-m4');
      expect(match.sport, equals('Soccer'));
    });

    test('downloadState is unchanged — all-local when sizeMb > 0', () async {
      final c = _makeContainer(db.value);
      c.listen(libraryProvider, (_, __) {});

      await db.value.teamsDao.insertTeamMatch(
        TeamMatchesTableCompanion.insert(
          id: 'vst-dl-local',
          teamId: 'nr-u14',
          opponent: 'vs Local',
          date: 'Apr 14',
          result: 'W 1-0',
          kind: 'past',
          numPeriods: 2,
          periodLengthSeconds: 35 * 60,
          sizeMb: const Value(150),
        ),
      );

      await _awaitLibrary(c, db.value);

      final lib = c.read(libraryProvider).valueOrNull ?? const [];
      final match = lib.firstWhere((m) => m.id == 'vst-dl-local');
      expect(match.downloadState, equals('all-local'));
    });

    test('downloadState is remote when sizeMb == 0', () async {
      final c = _makeContainer(db.value);
      c.listen(libraryProvider, (_, __) {});

      await db.value.teamsDao.insertTeamMatch(
        TeamMatchesTableCompanion.insert(
          id: 'vst-dl-remote',
          teamId: 'nr-u14',
          opponent: 'vs Remote',
          date: 'Apr 15',
          result: 'L 0-2',
          kind: 'past',
          numPeriods: 2,
          periodLengthSeconds: 35 * 60,
          // sizeMb defaults to 0
        ),
      );

      await _awaitLibrary(c, db.value);

      final lib = c.read(libraryProvider).valueOrNull ?? const [];
      final match = lib.firstWhere((m) => m.id == 'vst-dl-remote');
      expect(match.downloadState, equals('remote'));
    });
  });

  // ---------------------------------------------------------------------------
  // libraryTeamFilterProvider
  // ---------------------------------------------------------------------------

  group('libraryTeamFilterProvider', () {
    test('defaults to null', () {
      final c = _makeContainer(db.value);
      expect(c.read(libraryTeamFilterProvider), isNull);
    });

    test('can be set and cleared', () {
      final c = _makeContainer(db.value);
      c.read(libraryTeamFilterProvider.notifier).state = 'NRA';
      expect(c.read(libraryTeamFilterProvider), equals('NRA'));

      c.read(libraryTeamFilterProvider.notifier).state = null;
      expect(c.read(libraryTeamFilterProvider), isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // filteredLibraryMatchesProvider
  // ---------------------------------------------------------------------------

  group('filteredLibraryMatchesProvider', () {
    Future<void> _insertLocalMatch(
      AppDatabase db, {
      required String id,
      required String teamId,
      required String opponent,
      required String date,
      String result = 'W 1-0',
      int sizeMb = 100,
    }) async {
      await db.teamsDao.insertTeamMatch(
        TeamMatchesTableCompanion.insert(
          id: id,
          teamId: teamId,
          opponent: opponent,
          date: date,
          result: result,
          kind: 'past',
          numPeriods: 2,
          periodLengthSeconds: 35 * 60,
          sizeMb: Value(sizeMb),
        ),
      );
    }

    test('returns empty list when no matches', () {
      final c = _makeContainer(db.value);
      // libraryProvider loading → empty list
      expect(c.read(filteredLibraryMatchesProvider), isEmpty);
    });

    test('returns all matches when no filters set', () async {
      final c = _makeContainer(db.value);
      c.listen(libraryProvider, (_, __) {});

      await _insertLocalMatch(
        db.value,
        id: 'fmf-1',
        teamId: 'nr-u14',
        opponent: 'vs Alpha',
        date: 'May 01',
      );
      await _insertLocalMatch(
        db.value,
        id: 'fmf-2',
        teamId: 'nr-u12',
        opponent: 'vs Bravo',
        date: 'May 02',
      );

      await _awaitLibrary(c, db.value, count: 2);

      final filtered = c.read(filteredLibraryMatchesProvider);
      expect(filtered.length, greaterThanOrEqualTo(2));
    });

    test('sport filter removes non-matching matches', () async {
      final c = _makeContainer(db.value);
      c.listen(libraryProvider, (_, __) {});

      await _insertLocalMatch(
        db.value,
        id: 'fmf-sport-1',
        teamId: 'nr-u14',
        opponent: 'vs Soccer Team',
        date: 'May 03',
      );

      await _awaitLibrary(c, db.value);

      // Soccer filter keeps it.
      c.read(librarySportFilterProvider.notifier).state = 'Soccer';
      final soccer = c.read(filteredLibraryMatchesProvider);
      expect(soccer.any((m) => m.id == 'fmf-sport-1'), isTrue);

      // Basketball filter removes it.
      c.read(librarySportFilterProvider.notifier).state = 'Basketball';
      final basketball = c.read(filteredLibraryMatchesProvider);
      expect(basketball.any((m) => m.id == 'fmf-sport-1'), isFalse);
    });

    test('team filter: matches where teamShortName == filter', () async {
      final c = _makeContainer(db.value);
      c.listen(libraryProvider, (_, __) {});

      // nr-u14 shortName is 'NRA'; nr-u12 shortName is 'NRB'.
      await _insertLocalMatch(
        db.value,
        id: 'fmf-tf-nra',
        teamId: 'nr-u14',
        opponent: 'vs Opponent',
        date: 'May 04',
      );
      await _insertLocalMatch(
        db.value,
        id: 'fmf-tf-nrb',
        teamId: 'nr-u12',
        opponent: 'vs Opponent2',
        date: 'May 05',
      );

      await _awaitLibrary(c, db.value, count: 2);

      // Set team filter to 'nra' (case-insensitive).
      c.read(libraryTeamFilterProvider.notifier).state = 'nra';
      final results = c.read(filteredLibraryMatchesProvider);
      expect(results.any((m) => m.id == 'fmf-tf-nra'), isTrue);
      expect(results.any((m) => m.id == 'fmf-tf-nrb'), isFalse);
    });

    test('team filter: matches where opponent contains filter (NR in opponent)', () async {
      final c = _makeContainer(db.value);
      c.listen(libraryProvider, (_, __) {});

      // efc-r shortName is 'EFC'; match has opponent 'vs NR United' (contains 'NR').
      await _insertLocalMatch(
        db.value,
        id: 'fmf-tf-opp',
        teamId: 'efc-r',
        opponent: 'vs NR United',
        date: 'May 06',
      );

      await _awaitLibrary(c, db.value);

      c.read(libraryTeamFilterProvider.notifier).state = 'NR';
      final results = c.read(filteredLibraryMatchesProvider);
      expect(results.any((m) => m.id == 'fmf-tf-opp'), isTrue);
    });

    test('text search: NR matches teamShortName NRA', () async {
      final c = _makeContainer(db.value);
      c.listen(libraryProvider, (_, __) {});

      await _insertLocalMatch(
        db.value,
        id: 'fmf-search-nra',
        teamId: 'nr-u14',
        opponent: 'vs Zeta',
        date: 'May 07',
      );

      await _awaitLibrary(c, db.value);

      c.read(librarySearchQueryProvider.notifier).state = 'NR';
      final results = c.read(filteredLibraryMatchesProvider);
      expect(results.any((m) => m.id == 'fmf-search-nra'), isTrue);
    });

    test('text search: Northridge in opponent returns match', () async {
      final c = _makeContainer(db.value);
      c.listen(libraryProvider, (_, __) {});

      await _insertLocalMatch(
        db.value,
        id: 'fmf-search-opp',
        teamId: 'nr-u12',
        opponent: 'vs Northridge',
        date: 'May 08',
      );

      await _awaitLibrary(c, db.value);

      c.read(librarySearchQueryProvider.notifier).state = 'northridge';
      final results = c.read(filteredLibraryMatchesProvider);
      expect(results.any((m) => m.id == 'fmf-search-opp'), isTrue);
    });

    test('text search: teamName match — Northside returns nr-u14 matches', () async {
      final c = _makeContainer(db.value);
      c.listen(libraryProvider, (_, __) {});

      await _insertLocalMatch(
        db.value,
        id: 'fmf-search-tname',
        teamId: 'nr-u14',
        opponent: 'vs Eta',
        date: 'May 09',
      );

      await _awaitLibrary(c, db.value);

      c.read(librarySearchQueryProvider.notifier).state = 'Northside';
      final results = c.read(filteredLibraryMatchesProvider);
      expect(results.any((m) => m.id == 'fmf-search-tname'), isTrue);
    });

    test('text search: no match on unrelated query', () async {
      final c = _makeContainer(db.value);
      c.listen(libraryProvider, (_, __) {});

      await _insertLocalMatch(
        db.value,
        id: 'fmf-search-none',
        teamId: 'nr-u14',
        opponent: 'vs Theta',
        date: 'May 10',
      );

      await _awaitLibrary(c, db.value);

      c.read(librarySearchQueryProvider.notifier).state = 'ZZZNOMATCH';
      final results = c.read(filteredLibraryMatchesProvider);
      expect(results.any((m) => m.id == 'fmf-search-none'), isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // isOnDeviceProvider
  // ---------------------------------------------------------------------------

  group('isOnDeviceProvider', () {
    test('returns false when file does not exist', () async {
      final tempDir = await Directory.systemTemp.createTemp('isOnDevice_absent_a_');
      addTearDown(() => tempDir.delete(recursive: true));

      final stubSvc = _TempDirVideoPathService(tempDir.path);
      final c = _makeContainer(
        db.value,
        extra: [videoPathServiceProvider.overrideWithValue(stubSvc)],
      );

      final result = await c.read(isOnDeviceProvider('nonexistent-match-id').future);
      expect(result, isFalse);
    });

    test('returns true when file exists at recordingPath', () async {
      // Use a stub VideoPathService backed by a temp directory.
      final tempDir = await Directory.systemTemp.createTemp('isOnDevice_test_');
      addTearDown(() => tempDir.delete(recursive: true));

      const matchId = 'test-match-on-device';
      final filePath = '${tempDir.path}/$matchId.mp4';
      await File(filePath).writeAsBytes([]);

      // Stub VideoPathService that returns paths in the temp dir.
      final stubSvc = _TempDirVideoPathService(tempDir.path);

      final c = _makeContainer(
        db.value,
        extra: [videoPathServiceProvider.overrideWithValue(stubSvc)],
      );

      final result = await c.read(isOnDeviceProvider(matchId).future);
      expect(result, isTrue);
    });

    test('returns false when file does not exist in temp dir', () async {
      final tempDir = await Directory.systemTemp.createTemp('isOnDevice_absent_');
      addTearDown(() => tempDir.delete(recursive: true));

      final stubSvc = _TempDirVideoPathService(tempDir.path);

      final c = _makeContainer(
        db.value,
        extra: [videoPathServiceProvider.overrideWithValue(stubSvc)],
      );

      final result =
          await c.read(isOnDeviceProvider('absent-match-id').future);
      expect(result, isFalse);
    });
  });
}

// ---------------------------------------------------------------------------
// Stub VideoPathService — resolves paths against a temp directory so tests
// don't depend on getApplicationSupportDirectory().
// ---------------------------------------------------------------------------

class _TempDirVideoPathService extends VideoPathService {
  _TempDirVideoPathService(this._dir);
  final String _dir;

  @override
  Future<String> recordingPath(String recordingId) async =>
      '$_dir/$recordingId.mp4';
}
