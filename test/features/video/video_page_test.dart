// Widget tests for VideoPage — U6 Video Library Overhaul.
//
// Covers:
//   AE1: badge shows teamShortName, title shows "${teamName} vs ${opponent}"
//   AE2: opponent rendered without double "vs" (no "vs vs")
//   - Sport filter chips render
//   - Team filter chips render (one per tracked team)
//   - Empty state shown when filtered list is empty
//   - Tapping match card navigates to VideoMatchDetailPage
//
// Test isolation: `useInMemoryDb()` provides a fresh Drift in-memory DB
// seeded with user-1 / 4 teams / 5 matches (3 past) under nr-u14.
// We insert fresh test matches with clean opponent names (no "vs " prefix)
// so the title composition "${teamName} vs ${opponent}" works correctly.
//
// NOTE: isOnDeviceProvider is a FutureProvider; we override
// videoPathServiceProvider with a stub that returns a path to a non-existent
// file so the on-device check always resolves quickly to false.
//
// Pattern for ProviderContainer access: pump the widget, then find a
// descendant element (e.g. byType(VideoPage)) and call
// ProviderScope.containerOf on that. ProviderScope itself does not work
// because containerOf looks upward for a ProviderScope ancestor.

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sst_cam_app/core/ble/ble_providers.dart';
import 'package:sst_cam_app/core/services/video_path_service.dart';
import 'package:sst_cam_app/core/state/db_providers.dart';
import 'package:sst_cam_app/features/settings/users/users_state.dart'
    show activeUserProvider;
import 'package:sst_cam_app/features/teams/teams_state.dart'
    show teamsControllerProvider;
import 'package:sst_cam_app/features/video/video_page.dart';
import 'package:sst_cam_app/features/video/video_state.dart';
import 'package:sst_cam_app/mock/mock_ble_service.dart';

import '../../test_helpers.dart';

// ---------------------------------------------------------------------------
// Stub VideoPathService that returns paths to non-existent files so
// isOnDeviceProvider always resolves quickly to false.
// ---------------------------------------------------------------------------

class _AbsentVideoPathService extends VideoPathService {
  @override
  Future<String> recordingPath(String recordingId) async =>
      '/nonexistent/$recordingId.mp4';
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

MockBleService _newMock() => MockBleService(
      scanDeviceAppearDelays: const [Duration.zero],
      connectionDelay: Duration.zero,
      failureRate: 0.0,
      randomSeed: 42,
    );

Widget _buildPage(AppDatabase db) {
  return ProviderScope(
    overrides: [
      ...dbOverrides(db),
      bleServiceProvider.overrideWithValue(_newMock()),
      activeUserProvider.overrideWith((_) => 'user-1'),
      videoPathServiceProvider.overrideWithValue(_AbsentVideoPathService()),
    ],
    child: const MaterialApp(home: VideoPage()),
  );
}

/// Returns a ProviderContainer by looking up the tree from a VideoPage element.
/// containerOf walks UPWARD so we need a descendant of ProviderScope.
ProviderContainer _container(WidgetTester tester) {
  return ProviderScope.containerOf(
    tester.element(find.byType(VideoPage)),
  );
}

/// Insert a past match with a clean opponent name (no "vs " prefix) and a
/// non-zero sizeMb so it shows up in the library.
Future<void> _insertMatch(
  AppDatabase db, {
  required String id,
  required String teamId,
  required String opponent,
  String date = 'Apr 01',
  String result = 'W 2-1',
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

/// Pump until libraryProvider has at least [count] entries (max 30 iterations).
Future<void> _awaitLibrary(
  WidgetTester tester,
  ProviderContainer container, {
  int count = 1,
}) async {
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 10));
    final lib = container.read(libraryProvider).valueOrNull ?? const [];
    if (lib.length >= count) break;
  }
  await tester.pump();
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  final db = useInMemoryDb();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  // AE1 + AE2: badge and title rendering ----------------------------------------

  group('AE1 + AE2: match card badge and title', () {
    testWidgets(
        'badge shows teamShortName (NRA); '
        'title shows "Northside Rovers U14 vs Eastfield FC" (no double vs)',
        (tester) async {
      // Insert a match with a unique opponent that doesn't exist in seed data.
      await _insertMatch(
        db.value,
        id: 'ae-m1',
        teamId: 'nr-u14',
        opponent: 'Eastfield United',
        date: 'Apr 10',
        result: 'W 3-1',
      );

      await tester.pumpWidget(_buildPage(db.value));
      final container = _container(tester);
      await _awaitLibrary(tester, container);

      // Badge: circular container shows the shortName "NRA".
      expect(find.text('NRA'), findsWidgets);

      // Title: "${teamName} vs ${opponent}" — no double "vs".
      expect(
        find.text('Northside Rovers U14 vs Eastfield United'),
        findsOneWidget,
      );

      // Ensure there's no "vs vs" anywhere in the widget tree
      // (seed data has "vs Eastfield FC" which gets stripped to "Eastfield FC"
      // and then the title is "Northside Rovers U14 vs Eastfield FC" — clean).
      expect(find.textContaining('vs vs'), findsNothing);
    });
  });

  // Sport filter chips -----------------------------------------------------------

  group('Sport filter chips', () {
    testWidgets('renders "All" chip and sport chips from available sports',
        (tester) async {
      await _insertMatch(
        db.value,
        id: 'sport-m1',
        teamId: 'nr-u14',
        opponent: 'Generic Opponent',
        date: 'May 01',
      );

      await tester.pumpWidget(_buildPage(db.value));
      final container = _container(tester);
      await _awaitLibrary(tester, container);

      // "All" chips appear (sport + team rows both have "All").
      expect(find.text('All'), findsWidgets);

      // All teams in seed data are Soccer — "Soccer" chip should appear.
      expect(find.text('Soccer'), findsOneWidget);
    });
  });

  // Team filter chips ------------------------------------------------------------

  group('Team filter chips', () {
    testWidgets('renders one chip per team in teamsControllerProvider',
        (tester) async {
      await tester.pumpWidget(_buildPage(db.value));
      final container = _container(tester);

      // Wait for teams to load.
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 10));
        final teams = container.read(teamsControllerProvider).valueOrNull;
        if (teams != null && teams.isNotEmpty) break;
      }
      await tester.pump();

      // Seed data has 4 teams: NRA, NRB, EFC, RDU.
      expect(find.text('NRA'), findsWidgets);
      expect(find.text('NRB'), findsOneWidget);
      expect(find.text('EFC'), findsOneWidget);
      expect(find.text('RDU'), findsOneWidget);
    });
  });

  // Empty filtered state --------------------------------------------------------

  group('Empty filter state', () {
    testWidgets(
        'shows "No matches for this filter" and Clear filters button '
        'when filter returns no results', (tester) async {
      await _insertMatch(
        db.value,
        id: 'ef-m1',
        teamId: 'nr-u14',
        opponent: 'Some Team',
        date: 'May 10',
      );

      await tester.pumpWidget(_buildPage(db.value));
      final container = _container(tester);
      await _awaitLibrary(tester, container);

      // Set sport filter to something that matches nothing in the library.
      container.read(librarySportFilterProvider.notifier).state = 'Basketball';
      await tester.pump();

      expect(find.text('No matches for this filter'), findsOneWidget);
      expect(find.text('Clear filters'), findsOneWidget);
    });

    testWidgets('tapping "Clear filters" resets sport and team filters',
        (tester) async {
      await _insertMatch(
        db.value,
        id: 'ef-m2',
        teamId: 'nr-u14',
        opponent: 'Another Team',
        date: 'May 11',
      );

      await tester.pumpWidget(_buildPage(db.value));
      final container = _container(tester);
      await _awaitLibrary(tester, container);

      // Apply a non-matching filter.
      container.read(librarySportFilterProvider.notifier).state = 'Hockey';
      await tester.pump();

      expect(find.text('Clear filters'), findsOneWidget);
      await tester.tap(find.text('Clear filters'));
      await tester.pump();

      // After clearing, matches should be visible again.
      expect(find.text('No matches for this filter'), findsNothing);
      expect(container.read(librarySportFilterProvider), isNull);
    });
  });

  // Navigation ------------------------------------------------------------------

  group('Match card navigation', () {
    testWidgets('tapping a match card pushes VideoMatchDetailPage',
        (tester) async {
      // Use a tall surface so VideoMatchDetailPage (a Column with fixed
      // children) does not overflow and cause a spurious rendering error.
      await tester.binding.setSurfaceSize(const Size(800, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await _insertMatch(
        db.value,
        id: 'nav-m1',
        teamId: 'nr-u14',
        opponent: 'Navigation FC',
        date: 'Jun 01',
        result: 'W 1-0',
      );

      await tester.pumpWidget(_buildPage(db.value));
      final container = _container(tester);
      await _awaitLibrary(tester, container);

      // Find and tap the match card row.
      final cardFinder = find.text('Northside Rovers U14 vs Navigation FC');
      expect(cardFinder, findsOneWidget);
      await tester.tap(cardFinder);
      await tester.pumpAndSettle(const Duration(milliseconds: 300));

      // After navigation, VideoMatchDetailPage shows the match date in the
      // AppBar title.
      expect(find.text('Jun 01'), findsOneWidget);
    });
  });
}
