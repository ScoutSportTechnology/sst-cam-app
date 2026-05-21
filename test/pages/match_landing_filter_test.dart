// Match landing filter chips widget tests.
//
// Seed data: user-1 has upcoming matches only on nr-u14 (Soccer).
// We insert an extra upcoming match for a Basketball team (rd-utd, but we
// update its sport in the DB) to exercise sport chip filtering.
//
// IMPORTANT: MatchPage has a Timer.periodic (1 Hz) — never use pumpAndSettle.
// All pumps are explicit Duration-based calls.
//
// Cases:
//   1. With 2 matches of different teams, both visible initially.
//   2. Tap a sport chip → only matching sport visible.
//   3. Clear chip (tap "All") → both visible again.
//   4. Text search by opponent name filters correctly.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sst_cam_app/mock/mock_ble_service.dart';
import 'package:sst_cam_app/core/models/device.dart';
import 'package:sst_cam_app/pages/match_page.dart';
import 'package:sst_cam_app/features/camera/camera_state.dart'
    show activeCameraIdProvider;
import 'package:sst_cam_app/features/settings/users/users_state.dart'
    show activeUserProvider;
import 'package:sst_cam_app/core/ble/ble_providers.dart';

import '../test_helpers.dart';

const _kFakeDeviceId = 'SST-CAM-001';

MockBleService _newMock() => MockBleService(
  scanDeviceAppearDelays: const [Duration.zero],
  connectionDelay: Duration.zero,
  failureRate: 0.0,
  randomSeed: 1,
);

Widget _buildHarness(DbRef db, MockBleService service) {
  return ProviderScope(
    overrides: [
      ...dbOverrides(db),
      bleServiceProvider.overrideWithValue(service),
      activeCameraIdProvider.overrideWith((_) => _kFakeDeviceId),
      connectionStateProvider(_kFakeDeviceId).overrideWith(
        (_) => Stream<CameraConnectionState>.value(
          CameraConnectionState.connected,
        ),
      ),
      activeUserProvider.overrideWith((_) => 'user-1'),
    ],
    child: const MaterialApp(home: MatchPage()),
  );
}

/// Pump enough for Drift stream + Riverpod to emit the first snapshot.
Future<void> _pumpLanding(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  final db = useInMemoryDb();

  setUp(() async {
    SharedPreferences.setMockInitialValues({'active_user_id': 'user-1'});

    // Insert a Basketball team and one upcoming match for it.
    // rd-utd is 'Soccer' in seed; we add a new basketball team instead.
    await db.value.teamsDao.insertTeam(
      TeamsTableCompanion.insert(
        id: 'bball-team',
        userId: 'user-1',
        name: 'Riverside Ballers',
        shortName: 'RBB',
        sport: 'Basketball',
      ),
    );
    await db.value.teamsDao.insertTeamMatch(
      TeamMatchesTableCompanion.insert(
        id: 'bball-up1',
        teamId: 'bball-team',
        opponent: 'vs Hoopsters',
        date: 'Jun 01',
        result: '',
        kind: 'upcoming',
        numPeriods: 4,
        periodLengthSeconds: 12 * 60,
      ),
    );
  });

  group('Match landing filter chips', () {
    testWidgets(
      '1. All matches from different sports visible initially',
      (tester) async {
        final mock = _newMock();
        addTearDown(mock.dispose);

        await tester.pumpWidget(_buildHarness(db, mock));
        await _pumpLanding(tester);

        // Should see both matches: soccer and basketball.
        expect(find.textContaining('vs Eastfield FC'), findsWidgets);
        expect(find.textContaining('vs Hoopsters'), findsWidgets);
      },
    );

    testWidgets(
      '2. Tapping Soccer chip hides Basketball match',
      (tester) async {
        final mock = _newMock();
        addTearDown(mock.dispose);

        await tester.pumpWidget(_buildHarness(db, mock));
        await _pumpLanding(tester);

        // Tap the "Soccer" sport chip.
        await tester.tap(find.text('Soccer'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        // Soccer matches still visible.
        expect(find.textContaining('vs Eastfield FC'), findsWidgets);
        // Basketball match gone.
        expect(find.textContaining('vs Hoopsters'), findsNothing);
      },
    );

    testWidgets(
      '3. Tapping "All" chip after sport filter restores all matches',
      (tester) async {
        final mock = _newMock();
        addTearDown(mock.dispose);

        await tester.pumpWidget(_buildHarness(db, mock));
        await _pumpLanding(tester);

        // Apply Soccer filter.
        await tester.tap(find.text('Soccer'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(find.textContaining('vs Hoopsters'), findsNothing);

        // Tap "All" to clear the filter.
        await tester.tap(find.text('All').first);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        // Both matches visible again.
        expect(find.textContaining('vs Eastfield FC'), findsWidgets);
        expect(find.textContaining('vs Hoopsters'), findsWidgets);
      },
    );

    testWidgets(
      '4. Text search by opponent name filters correctly',
      (tester) async {
        final mock = _newMock();
        addTearDown(mock.dispose);

        await tester.pumpWidget(_buildHarness(db, mock));
        await _pumpLanding(tester);

        // Both visible initially.
        expect(find.textContaining('vs Eastfield FC'), findsWidgets);
        expect(find.textContaining('vs Hoopsters'), findsWidgets);

        // Type in the search field.
        final searchField = find.byType(TextField).first;
        await tester.tap(searchField);
        await tester.enterText(searchField, 'Hoopsters');
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        // Only basketball match visible.
        expect(find.textContaining('vs Hoopsters'), findsWidgets);
        expect(find.textContaining('vs Eastfield FC'), findsNothing);

        // Clear query.
        await tester.enterText(searchField, '');
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        // Both back.
        expect(find.textContaining('vs Eastfield FC'), findsWidgets);
        expect(find.textContaining('vs Hoopsters'), findsWidgets);
      },
    );
  });
}
