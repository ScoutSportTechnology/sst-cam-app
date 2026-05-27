// Smoke test — verifies the app boots in dev-mock with the mock BLE backend.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sst_cam_app/app.dart';
import 'package:sst_cam_app/mock/emulator/mock_ble_service.dart';
import 'package:sst_cam_app/core/ble/ble_providers.dart';

import 'test_helpers.dart';

void main() {
  // Use an in-memory DB to avoid NativeDatabase.createInBackground IPC traffic
  // that prevents pumpAndSettle from settling.
  final db = useInMemoryDb();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

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
        overrides: [
          bleServiceProvider.overrideWithValue(mock),
          ...dbOverrides(db),
        ],
        child: const SstCamApp(),
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 200));

    expect(find.text('Teams'), findsOneWidget);
    expect(find.text('Match'), findsOneWidget);
    expect(find.text('Video'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
  });
}
