// Smoke test — verifies the app boots in dev-mock with the mock BLE backend.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scout_camera/app.dart';
import 'package:scout_camera/ble/mock_ble_service.dart';
import 'package:scout_camera/state/ble_providers.dart';

void main() {
  testWidgets('app boots and shows the bottom-nav tabs', (
    WidgetTester tester,
  ) async {
    final mock = MockBleService(
      scanDeviceAppearDelays: [Duration.zero, Duration.zero],
      connectionDelay: Duration.zero,
      failureRate: 0.0,
    );
    addTearDown(mock.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [bleServiceProvider.overrideWithValue(mock)],
        child: const ScoutCameraApp(),
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 200));

    expect(find.text('Teams'), findsOneWidget);
    expect(find.text('Match'), findsOneWidget);
    expect(find.text('Video'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
  });
}
