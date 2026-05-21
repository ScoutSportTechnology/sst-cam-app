// AppShell widget tests — activeTabProvider navigation.
//
// Verifies:
//   1. Writing activeTabProvider to 2 causes NavigationBar.selectedIndex == 2.
//   2. Tapping NavigationBar tab 0 sets activeTabProvider to 0.
//
// NOTE: _AppShellState uses a WidgetsBinding post-frame callback to call
// FlutterNativeSplash.remove(). We override the binding to avoid a crash
// in the test environment where the native plugin is unavailable. The
// workaround is to wrap AppShell in a Builder / TestWidgetsFlutterBinding
// and catch the missing-plugin exception. In practice we avoid calling
// the real remove() by wrapping AppShell in its own ProviderScope so the
// shell itself is the top-level widget under test.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sst_cam_app/app_shell.dart';
import 'package:sst_cam_app/ble/mock_ble_service.dart';
import 'package:sst_cam_app/state/app_data.dart';
import 'package:sst_cam_app/state/ble_providers.dart';

import 'test_helpers.dart';

MockBleService _newMock() => MockBleService(
  scanDeviceAppearDelays: const [Duration.zero],
  connectionDelay: Duration.zero,
  failureRate: 0.0,
  randomSeed: 1,
);

/// Build a [ProviderScope] wrapping [AppShell] with the minimum overrides
/// needed to avoid plugin crashes. Returns the container via [Builder] so
/// callers can interact with it.
Widget _buildHarness(DbRef db, MockBleService service) {
  return ProviderScope(
    overrides: [
      ...dbOverrides(db),
      bleServiceProvider.overrideWithValue(service),
      // Override activeUserProvider so TeamsController doesn't try to hit
      // SharedPreferences before the mock is set.
      activeUserProvider.overrideWith((_) => 'user-1'),
    ],
    child: const MaterialApp(
      home: AppShell(),
    ),
  );
}

void main() {
  final db = useInMemoryDb();

  setUp(() {
    SharedPreferences.setMockInitialValues({'active_user_id': 'user-1'});
  });

  testWidgets(
    'writing activeTabProvider = 2 sets NavigationBar selectedIndex to 2',
    (tester) async {
      final mock = _newMock();
      addTearDown(mock.dispose);

      await tester.pumpWidget(_buildHarness(db, mock));
      // Let the shell render. pumpAndSettle is not safe here (MatchPage has a
      // 1-Hz Timer.periodic), so use explicit pumps.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Write activeTabProvider = 2 via the container.
      final container = ProviderScope.containerOf(
        tester.element(find.byType(AppShell)),
      );
      container.read(activeTabProvider.notifier).state = 2;

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final navBar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(navBar.selectedIndex, 2);
    },
  );

  testWidgets(
    'tapping NavigationBar tab 0 sets activeTabProvider to 0',
    (tester) async {
      final mock = _newMock();
      addTearDown(mock.dispose);

      await tester.pumpWidget(_buildHarness(db, mock));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final container = ProviderScope.containerOf(
        tester.element(find.byType(AppShell)),
      );

      // Start on tab 2 so a tap on tab 0 is a real navigation change.
      container.read(activeTabProvider.notifier).state = 2;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Tap the first NavigationDestination (index 0, 'Main').
      // NavigationBar renders NavigationDestination widgets inside an
      // internal layout. We tap the icon at the leftmost position.
      final destinations = find.byType(NavigationDestination);
      await tester.tap(destinations.first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(container.read(activeTabProvider), 0);

      final navBar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(navBar.selectedIndex, 0);
    },
  );
}
