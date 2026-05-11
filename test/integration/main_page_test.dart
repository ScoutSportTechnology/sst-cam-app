import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:scout_camera/app.dart';
import 'package:scout_camera/ble/mock_ble_service.dart';
import 'package:scout_camera/state/ble_providers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Main page: scan discovers mock devices and connect works', (
    tester,
  ) async {
    final mock = MockBleService(
      scanDeviceAppearDelays: [
        const Duration(milliseconds: 100),
        const Duration(milliseconds: 200),
      ],
      connectionDelay: const Duration(milliseconds: 100),
      failureRate: 0.0,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [bleServiceProvider.overrideWithValue(mock)],
        child: const SstCamApp(),
      ),
    );

    expect(find.text('Scout Camera'), findsOneWidget);

    // Trigger scan
    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pump();

    // Wait for devices
    await tester.pumpAndSettle(const Duration(milliseconds: 500));

    expect(find.text('sst-cam-0001'), findsOneWidget);
    expect(find.text('sst-cam-0002'), findsOneWidget);

    // Connect to first device
    final connectBtns = find.widgetWithText(FilledButton, 'Connect');
    expect(connectBtns, findsWidgets);

    await tester.tap(connectBtns.first);
    await tester.pumpAndSettle(const Duration(milliseconds: 300));

    expect(find.widgetWithText(FilledButton, 'Disconnect'), findsOneWidget);

    await mock.dispose();
  });
}
