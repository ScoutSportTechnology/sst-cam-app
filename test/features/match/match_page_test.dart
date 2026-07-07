// U9 — match_page.dart setup screen pushSessionConfig tests.
//
// Verifies that:
//   - Happy path: pushSessionConfig succeeds → session screen entered,
//     MockBleService.lastPushedConfig has correct matchUuid / sport / numPeriods.
//   - Error path: pushSessionConfig throws BleTimeoutException → setup screen stays,
//     error text shown.
//   - Exception path: pushSessionConfig throws BleTimeoutException or
//     BleConnectionException → same error UX.
//
// IMPORTANT: _MatchPageState has a Timer.periodic (1 Hz tick) which prevents
// pumpAndSettle from ever terminating. All test pumps use explicit durations
// via tester.pump(Duration) rather than pumpAndSettle.
//
// Test isolation: `useInMemoryDb()` provides a fresh Drift in-memory DB
// seeded with user-1 / 4 teams / 2 upcoming matches under nr-u14.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sst_cam_app/core/ble/ble_service.dart';
import 'package:sst_cam_app/mock/emulator/mock_ble_service.dart';
import 'package:sst_cam_app/core/models/command.dart';
import 'package:sst_cam_app/core/models/device.dart';
import 'package:sst_cam_app/features/match/match_page.dart';
import 'package:sst_cam_app/features/camera/camera_state.dart'
    show activeCameraIdProvider;
import 'package:sst_cam_app/features/settings/users/users_state.dart'
    show activeUserProvider;
import 'package:sst_cam_app/core/ble/ble_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../test_helpers.dart';

const _kFakeDeviceId = 'SST-CAM-001';

// ---------------------------------------------------------------------------
// Mock variants for error-path testing
// ---------------------------------------------------------------------------

/// Throws [BleTimeoutException] on every [pushSessionConfig] call.
class _TimeoutMockBleService extends MockBleService {
  _TimeoutMockBleService()
    : super(
        scanDeviceAppearDelays: const [Duration.zero],
        connectionDelay: Duration.zero,
        failureRate: 0.0,
        randomSeed: 1,
      );

  @override
  Future<void> pushSessionConfig(
    String deviceId,
    PushSessionConfig config,
  ) async {
    throw const BleTimeoutException('Simulated BLE timeout');
  }
}

/// Throws [BleConnectionException] on every [pushSessionConfig] call.
class _ConnectionErrorMockBleService extends MockBleService {
  _ConnectionErrorMockBleService()
    : super(
        scanDeviceAppearDelays: const [Duration.zero],
        connectionDelay: Duration.zero,
        failureRate: 0.0,
        randomSeed: 1,
      );

  @override
  Future<void> pushSessionConfig(
    String deviceId,
    PushSessionConfig config,
  ) async {
    throw const BleConnectionException('Simulated BLE disconnect');
  }
}

MockBleService _newMock() => MockBleService(
  scanDeviceAppearDelays: const [Duration.zero],
  connectionDelay: Duration.zero,
  failureRate: 0.0,
  randomSeed: 1,
);

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

Widget _buildHarness({
  required MockBleService service,
  required DbRef db,
  CameraConnectionState connectionState = CameraConnectionState.connected,
}) {
  return ProviderScope(
    overrides: [
      ...dbOverrides(db),
      bleServiceProvider.overrideWithValue(service),
      activeCameraIdProvider.overrideWith((_) => _kFakeDeviceId),
      connectionStateProvider(_kFakeDeviceId).overrideWith(
        (_) => Stream<CameraConnectionState>.value(connectionState),
      ),
      // Faked connection ⇒ no handshake/telemetry health readings — pin the
      // U3 gate open (health gating has its own dedicated tests).
      healthyDeviceOverride(),
      activeUserProvider.overrideWith((_) => 'user-1'),
    ],
    child: const MaterialApp(home: MatchPage()),
  );
}

// ---------------------------------------------------------------------------
// Navigation helper
// ---------------------------------------------------------------------------

/// Pumps until the landing screen is ready, then taps the first upcoming
/// match row to enter the Setup screen.
///
/// Uses explicit [tester.pump] calls rather than [pumpAndSettle] because
/// [_MatchPageState] has a [Timer.periodic] (1 Hz tick) that prevents
/// [pumpAndSettle] from ever terminating.
Future<void> _navigateToSetup(WidgetTester tester) async {
  // Give Drift stream + Riverpod time to emit the first snapshot.
  // The upcomingMatchesProvider is a StreamProvider backed by a Drift watch
  // stream; allow several async gaps for the query to complete and propagate.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 100));

  // Expect upcoming match rows to be visible. The _UpcomingRow renders
  // "${teamName} vs Eastfield FC" in a single Text widget, so use
  // textContaining rather than an exact match.
  final row = find.textContaining('vs Eastfield FC');
  expect(
    row,
    findsWidgets,
    reason: 'Landing screen should show upcoming matches',
  );
  await tester.tap(row.first);

  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));

  expect(find.text('Match setup'), findsOneWidget);
}

/// Scrolls to the "Start match" (or [buttonText]) button and taps it.
/// The setup screen is a [ListView], so the button may be off-screen.
Future<void> _tapSetupButton(WidgetTester tester, String buttonText) async {
  final finder = find.text(buttonText);
  await tester.scrollUntilVisible(finder, 200);
  await tester.pump();
  await tester.tap(finder);
}

/// Pumps enough time for the mock BLE delay (80 ms) plus rendering frames.
Future<void> _pumpAfterTap(WidgetTester tester) async {
  await tester.pump(); // start async gap
  await tester.pump(const Duration(milliseconds: 200)); // cover mock delay
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  final db = useInMemoryDb();

  setUp(() {
    SharedPreferences.setMockInitialValues({'active_user_id': 'user-1'});
  });

  group('_SetupScreen — pushSessionConfig (U9)', () {
    testWidgets('happy path: Start match → pushSessionConfig called, '
        'lastPushedConfig populated with correct values, session entered', (
      tester,
    ) async {
      // Use a tall surface so the _SessionScreen (a Column with fixed
      // children) does not overflow and cause a spurious rendering exception.
      await tester.binding.setSurfaceSize(const Size(800, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final mock = _newMock();
      await tester.pumpWidget(_buildHarness(service: mock, db: db));
      await _navigateToSetup(tester);

      // Tap the "Start match" button. The setup screen is a ListView, so
      // scroll the button into view first.
      await _tapSetupButton(tester, 'Start match');
      await _pumpAfterTap(tester);

      // Assertions on the pushed config.
      expect(mock.lastPushedConfig, isNotNull);
      final cfg = mock.lastPushedConfig!;
      expect(cfg.sport, equals('soccer'));
      expect(cfg.numPeriods, equals(2));
      expect(cfg.periodLengthSeconds, equals(35 * 60));
      expect(cfg.userUuid, equals('user-1'));
      expect(cfg.matchUuid, isNotEmpty);
      expect(
        cfg.videoOutputPath,
        equals('/var/lib/sst/cam/videos/user-1/${cfg.matchUuid}/'),
      );
      expect(
        cfg.thumbnailOutputPath,
        equals('/var/lib/sst/cam/thumbnails/user-1/${cfg.matchUuid}/'),
      );

      // Setup screen should no longer be visible — we entered the session.
      expect(find.text('Match setup'), findsNothing);
    });

    testWidgets('error path: pushSessionConfig throws BleTimeoutException → '
        'setup screen stays, error text shown, no navigation', (tester) async {
      final mock = _newMock();
      mock.failNextPushSessionConfig = true;

      await tester.pumpWidget(_buildHarness(service: mock, db: db));
      await _navigateToSetup(tester);

      await _tapSetupButton(tester, 'Start match');
      await _pumpAfterTap(tester);

      // Still on setup screen.
      expect(find.text('Match setup'), findsOneWidget);
      // Inline error message.
      expect(find.textContaining('Failed to configure camera'), findsOneWidget);
      // Retry affordance.
      expect(find.text('Retry'), findsOneWidget);
      // Config was NOT stored (error path in mock doesn't store it).
      expect(mock.lastPushedConfig, isNull);
    });

    testWidgets(
      'BleTimeoutException → setup screen stays, error message shown',
      (tester) async {
        final mock = _TimeoutMockBleService();
        await tester.pumpWidget(_buildHarness(service: mock, db: db));
        await _navigateToSetup(tester);

        await _tapSetupButton(tester, 'Start match');
        await _pumpAfterTap(tester);

        expect(find.text('Match setup'), findsOneWidget);
        expect(
          find.textContaining('Failed to configure camera'),
          findsOneWidget,
        );
        expect(find.text('Retry'), findsOneWidget);
      },
    );

    testWidgets(
      'BleConnectionException → setup screen stays, error message shown',
      (tester) async {
        final mock = _ConnectionErrorMockBleService();
        await tester.pumpWidget(_buildHarness(service: mock, db: db));
        await _navigateToSetup(tester);

        await _tapSetupButton(tester, 'Start match');
        await _pumpAfterTap(tester);

        expect(find.text('Match setup'), findsOneWidget);
        expect(
          find.textContaining('Failed to configure camera'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'retry: after error, tapping Retry re-invokes pushSessionConfig '
      'and enters the session on success',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(800, 1400));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final mock = _newMock();
        mock.failNextPushSessionConfig = true;

        await tester.pumpWidget(_buildHarness(service: mock, db: db));
        await _navigateToSetup(tester);

        // First tap — fails.
        await _tapSetupButton(tester, 'Start match');
        await _pumpAfterTap(tester);
        expect(find.text('Match setup'), findsOneWidget);
        expect(
          find.textContaining('Failed to configure camera'),
          findsOneWidget,
        );

        // Retry — succeeds (failNextPushSessionConfig was reset to false).
        await tester.tap(find.text('Retry'));
        await _pumpAfterTap(tester);

        expect(find.text('Match setup'), findsNothing);
        expect(mock.lastPushedConfig, isNotNull);
      },
    );

    testWidgets('Start match button is disabled when camera is disconnected', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(800, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final mock = _newMock();
      await tester.pumpWidget(
        _buildHarness(
          service: mock,
          db: db,
          connectionState: CameraConnectionState.disconnected,
        ),
      );
      await _navigateToSetup(tester);

      // Scroll to the button so the finder can locate it.
      final buttonFinder = find.text('Start match');
      await tester.scrollUntilVisible(buttonFinder, 200);
      await tester.pump();

      // Button must be disabled (no onPressed) — tapping it must NOT
      // call pushSessionConfig.
      await tester.tap(buttonFinder, warnIfMissed: false);
      await _pumpAfterTap(tester);

      expect(
        mock.lastPushedConfig,
        isNull,
        reason:
            'pushSessionConfig must not be called when camera is disconnected',
      );
      expect(
        find.text('Match setup'),
        findsOneWidget,
        reason: 'Setup screen must remain visible — session must not start',
      );
      expect(
        find.text('Connect a camera to start the match.'),
        findsOneWidget,
        reason: 'Hint text must appear when disconnected',
      );
    });

    testWidgets('matchUuid is a valid UUID v4', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final mock = _newMock();
      await tester.pumpWidget(_buildHarness(service: mock, db: db));
      await _navigateToSetup(tester);

      await _tapSetupButton(tester, 'Start match');
      await _pumpAfterTap(tester);

      final uuid = mock.lastPushedConfig?.matchUuid ?? '';
      expect(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ).hasMatch(uuid),
        isTrue,
        reason: 'matchUuid must be a valid UUID v4, got: $uuid',
      );
    });
  });
}
