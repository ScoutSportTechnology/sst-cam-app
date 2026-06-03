import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sst_cam_app/app.dart';
import 'package:sst_cam_app/mock/emulator/mock_ble_service.dart';
import 'package:sst_cam_app/features/discovery/discovery_page.dart';
import 'package:sst_cam_app/core/ble/ble_providers.dart';
import 'package:sst_cam_app/core/widgets/wf_button.dart';

import '../test_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final db = useInMemoryDb();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  // CRITICAL: DiscoveryPage has a repeating RotationTransition (_ScanIndicator)
  // and MockBleService starts a Timer.periodic for telemetry on connect. Both
  // prevent pumpAndSettle from settling — use pump(duration) throughout.
  testWidgets('Main page: discovery page finds devices and connect works', (
    tester,
  ) async {
    final mock = MockBleService(
      scanDeviceAppearDelays: [
        const Duration(milliseconds: 50),
        const Duration(milliseconds: 100),
      ],
      connectionDelay: Duration.zero,
      failureRate: 0.0,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bleServiceProvider.overrideWithValue(mock),
          ...dbOverrides(db),
        ],
        child: const SstCamApp(),
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 200));

    // Main tab is selected ('Teams' appears only once as a nav label).
    expect(find.text('Teams'), findsOneWidget);

    // The 'Connect camera' button is in a ListView after the hero card; scroll
    // it into view before tapping.
    await tester.ensureVisible(find.text('Connect camera'));
    await tester.pump(); // commit the scroll before tapping
    await tester.tap(find.text('Connect camera'));
    // Use bounded pumps — DiscoveryPage's scan indicator prevents pumpAndSettle.
    // Need ~300 ms to complete the MaterialPageRoute transition.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // DiscoveryPage is now in the tree.
    expect(find.byType(DiscoveryPage), findsOneWidget);

    // Advance past device-appear delays (50 ms + 100 ms). startScan() was
    // called in DiscoveryPage.initState via addPostFrameCallback; an extra pump
    // ensures those timers fire.
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('sst-cam-0001'), findsOneWidget);
    expect(find.text('sst-cam-0002'), findsOneWidget);

    // Connect to the first device. connectionDelay is zero so the connect
    // resolves immediately; pump briefly to let the UI update and pop complete.
    await tester.tap(find.widgetWithText(WfButton, 'Connect').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // DiscoveryPage pops after connect; the app shows 'Disconnect' (main
    // page hero card and possibly settings page both react to camera state).
    expect(find.widgetWithText(WfButton, 'Disconnect'), findsWidgets);

    // Stop scan to avoid dangling timers after the test.
    await mock.stopScan();
    await mock.dispose();
  });
}
