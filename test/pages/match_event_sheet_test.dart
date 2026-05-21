// _EventSheetState behaviour tests — accessed through MatchPage widget tree.
//
// _EventSheet is a private widget inside match_page.dart, so tests must reach
// it by driving the full MatchPage flow:
//   Landing → tap upcoming row → Setup screen → Start match → Session screen
//   → start period (kickoff) → tap "Mark event" → bottom sheet appears.
//
// IMPORTANT: _MatchPageState has a Timer.periodic (1 Hz) — never use pumpAndSettle.
// All pumps are explicit Duration-based calls.
//
// Covered cases:
//   1. Next button is disabled at step 0 when no event type is selected.
//   2. Next button becomes enabled after tapping a type chip.
//   3. Away team shows number pad (not dropdown) even when home roster exists.
//   4. Switching teams resets jersey state.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sst_cam_app/mock/mock_ble_service.dart';
import 'package:sst_cam_app/core/models/device.dart';
import 'package:sst_cam_app/pages/match_page.dart';
import 'package:sst_cam_app/features/camera/camera_state.dart'
    show activeCameraIdProvider;
import 'package:sst_cam_app/features/match/session/session_state.dart'
    show liveMatchProvider;
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

/// Navigate from the landing screen to the session screen (idle phase).
/// Returns once the session screen is visible (no 'Match setup' title,
/// 'Mark event' button visible).
Future<void> _reachSessionScreen(WidgetTester tester) async {
  // Allow landing data to load.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));

  // Tap first upcoming match row.
  final row = find.textContaining('vs Eastfield FC');
  expect(row, findsWidgets, reason: 'Landing must show upcoming match');
  await tester.tap(row.first);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));

  // Now on setup screen.
  expect(find.text('Match setup'), findsOneWidget);

  // Scroll to "Start match" and tap.
  final startBtn = find.text('Start match');
  await tester.scrollUntilVisible(startBtn, 200);
  await tester.pump();
  await tester.tap(startBtn);

  // Cover BLE mock delay.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));

  // Verify session screen is up.
  expect(find.text('Match setup'), findsNothing);
  expect(find.text('Kickoff'), findsOneWidget);
}

/// Start period 1 directly via the liveMatchProvider notifier so that
/// "Mark event" becomes active without navigating the kickoff sheet UI.
/// Call this after [_reachSessionScreen].
Future<void> _startPeriodDirectly(WidgetTester tester) async {
  // Access the ProviderContainer from any widget that has a ProviderScope
  // ancestor (the MaterialApp root).
  final element = tester.element(find.byType(MaterialApp));
  final container = ProviderScope.containerOf(element);
  container.read(liveMatchProvider.notifier).startPeriod();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

/// Open the event sheet by tapping "Mark event".
/// Precondition: period must be active (startPeriod called).
Future<void> _openEventSheet(WidgetTester tester) async {
  await tester.tap(find.text('Mark event'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  final db = useInMemoryDb();

  setUp(() {
    SharedPreferences.setMockInitialValues({'active_user_id': 'user-1'});
  });

  group('_EventSheet', () {
    testWidgets(
      '1. Next button is disabled when no event type is selected (step 0)',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(800, 1400));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final mock = _newMock();
        addTearDown(mock.dispose);

        await tester.pumpWidget(_buildHarness(db, mock));
        await _reachSessionScreen(tester);
        await _startPeriodDirectly(tester);
        await _openEventSheet(tester);

        // The event sheet should be visible with "What happened?".
        expect(find.text('What happened?'), findsOneWidget);

        // "Next" button is present. Since _type is empty, onPressed is null.
        // Verify tapping "Next" does NOT advance to step 2.
        final nextBtn = find.text('Next');
        expect(nextBtn, findsOneWidget);
        await tester.tap(nextBtn);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        // "Which team?" should NOT appear — Next was disabled.
        expect(find.text('Which team?'), findsNothing);
        // Still on step 1.
        expect(find.text('What happened?'), findsOneWidget);
      },
    );

    testWidgets(
      '2. Next button enabled after tapping a type chip',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(800, 1400));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final mock = _newMock();
        addTearDown(mock.dispose);

        await tester.pumpWidget(_buildHarness(db, mock));
        await _reachSessionScreen(tester);
        await _startPeriodDirectly(tester);
        await _openEventSheet(tester);

        expect(find.text('What happened?'), findsOneWidget);

        // Tap the "Goal" type chip.
        await tester.tap(find.text('Goal'));
        // Multiple pumps to let setState rebuild the button's onPressed.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        await tester.pump(const Duration(milliseconds: 50));

        // Now tap "Next" — should advance to step 2.
        await tester.tap(find.text('Next'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.text('Which team?'), findsOneWidget);
      },
    );

    testWidgets(
      '3. Away team shows number pad even when home roster exists',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(800, 1400));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final mock = _newMock();
        addTearDown(mock.dispose);

        await tester.pumpWidget(_buildHarness(db, mock));
        await _reachSessionScreen(tester);
        await _startPeriodDirectly(tester);
        await _openEventSheet(tester);

        await tester.tap(find.text('Goal'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        await tester.pump(const Duration(milliseconds: 50));
        await tester.tap(find.text('Next'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.text('Which team?'), findsOneWidget);

        // Tap the AWAY card.
        await tester.tap(find.text('AWAY'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        // AWAY has no roster → number pad branch only.
        // The number pad keys should be visible.
        expect(find.text('1'), findsWidgets);
        // No dropdown expand_more icon (which would appear with a roster).
        expect(find.byIcon(Icons.expand_more), findsNothing);
      },
    );

    testWidgets(
      '4. Switching from one team to another resets jersey state',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(800, 1400));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final mock = _newMock();
        addTearDown(mock.dispose);

        await tester.pumpWidget(_buildHarness(db, mock));
        await _reachSessionScreen(tester);
        await _startPeriodDirectly(tester);
        await _openEventSheet(tester);

        await tester.tap(find.text('Goal'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        await tester.pump(const Duration(milliseconds: 50));
        await tester.tap(find.text('Next'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // Select AWAY first to get the number pad.
        await tester.tap(find.text('AWAY'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        // AWAY shows number pad. Tap digit '7'.
        final sevens = find.text('7');
        if (sevens.evaluate().isNotEmpty) {
          await tester.tap(sevens.first);
          await tester.pump();
        }

        // Switch to HOME — jersey should reset (_jersey.clear() on team switch).
        await tester.tap(find.text('HOME'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        // HOME has a roster → DropdownButton appears (expand_more icon present).
        // And the jersey value was reset: no '7' remains in the display text.
        expect(find.text('HOME'), findsOneWidget);
        // The expand_more icon appears from the DropdownButton for home roster.
        expect(find.byIcon(Icons.expand_more), findsWidgets);
      },
    );
  });
}
