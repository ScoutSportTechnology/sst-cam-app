// U5 — Settings → Network page: loads the camera's uplink config over BLE,
// edits it, and applies it back.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sst_cam_app/core/ble/ble_providers.dart';
import 'package:sst_cam_app/features/camera/camera_state.dart'
    show activeCameraIdProvider;
import 'package:sst_cam_app/features/settings/network/network_settings_page.dart';
import 'package:sst_cam_app/mock/emulator/mock_ble_service.dart';

MockBleService _newMock() => MockBleService(
  scanDeviceAppearDelays: const [Duration.zero],
  connectionDelay: Duration.zero,
  randomSeed: 1,
);

Future<void> _pump(WidgetTester tester, MockBleService mock) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        bleServiceProvider.overrideWithValue(mock),
        activeCameraIdProvider.overrideWith((ref) => 'sst-cam-0001'),
      ],
      child: const MaterialApp(home: NetworkSettingsPage()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('loads config and renders both uplink sections', (tester) async {
    final mock = _newMock();
    await _pump(tester, mock);

    expect(find.text('Ethernet'), findsOneWidget);
    expect(find.text('WiFi'), findsOneWidget);
    expect(find.text('Apply'), findsOneWidget);
    // Fresh camera: both uplinks default off, so no IP fields are shown yet.
    expect(find.widgetWithText(TextField, 'SSID'), findsNothing);

    await mock.dispose();
  });

  testWidgets('enabling ethernet reveals it and Apply pushes the config', (
    tester,
  ) async {
    final mock = _newMock();
    await _pump(tester, mock);

    // Toggle the first Switch (the Ethernet section's enable).
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Apply'));
    // pump past the mock's apply delay (don't pumpAndSettle — the success
    // SnackBar's auto-dismiss timer never settles).
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // The camera applied it: the success SnackBar shows and the live address
    // (ip/mask only, no verbose status) is displayed.
    expect(find.text('Network config applied'), findsOneWidget);
    expect(find.textContaining('10.10.1.30'), findsOneWidget);

    await mock.dispose();
  });

  testWidgets('shows a hint when no camera is connected', (tester) async {
    final mock = _newMock();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bleServiceProvider.overrideWithValue(mock),
          activeCameraIdProvider.overrideWith((ref) => null),
        ],
        child: const MaterialApp(home: NetworkSettingsPage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Connect to a camera'), findsOneWidget);
    await mock.dispose();
  });
}
