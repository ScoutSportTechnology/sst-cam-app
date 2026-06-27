// #6 A6b — PreviewLayoutToggle widget tests.
//
// Verifies:
//   - Tapping "Both" issues setPreviewLayout(side-by-side) and reflects it in
//     previewLayoutProvider (optimistic).
//   - A firmware rejection reverts the optimistic state and surfaces a snackbar.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sst_cam_app/core/ble/ble_providers.dart';
import 'package:sst_cam_app/core/models/preview_layout.dart';
import 'package:sst_cam_app/core/widgets/preview_layout_toggle.dart';
import 'package:sst_cam_app/core/wifi/wifi_providers.dart';
import 'package:sst_cam_app/mock/emulator/mock_ble_service.dart';

const _deviceId = 'SST-CAM-001';

void main() {
  testWidgets('tapping Both switches layout to side-by-side', (tester) async {
    final ble = MockBleService();
    late ProviderContainer container;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [bleServiceProvider.overrideWithValue(ble)],
        child: Builder(
          builder: (context) {
            container = ProviderScope.containerOf(context);
            return const MaterialApp(
              home: Scaffold(
                body: Center(child: PreviewLayoutToggle(deviceId: _deviceId)),
              ),
            );
          },
        ),
      ),
    );

    expect(
      container.read(previewLayoutProvider(_deviceId)),
      PreviewLayout.single,
    );

    await tester.tap(find.text('Both'));
    await tester.pump(); // optimistic flip
    expect(
      container.read(previewLayoutProvider(_deviceId)),
      PreviewLayout.sideBySide,
    );

    await tester.pump(const Duration(milliseconds: 120)); // mock latency
    expect(ble.lastPreviewLayout, PreviewLayout.sideBySide);
  });

  testWidgets('firmware rejection reverts and shows snackbar', (tester) async {
    final ble = MockBleService()..failNextSetPreviewLayout = true;
    late ProviderContainer container;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [bleServiceProvider.overrideWithValue(ble)],
        child: Builder(
          builder: (context) {
            container = ProviderScope.containerOf(context);
            return const MaterialApp(
              home: Scaffold(
                body: Center(child: PreviewLayoutToggle(deviceId: _deviceId)),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Both'));
    await tester.pump(); // optimistic flip to side-by-side
    expect(
      container.read(previewLayoutProvider(_deviceId)),
      PreviewLayout.sideBySide,
    );

    await tester.pump(const Duration(milliseconds: 120)); // failure resolves
    expect(
      container.read(previewLayoutProvider(_deviceId)),
      PreviewLayout.single, // reverted
    );
    await tester.pump();
    expect(find.byType(SnackBar), findsOneWidget);
  });

  testWidgets('null deviceId renders disabled (no crash on tap)', (
    tester,
  ) async {
    final ble = MockBleService();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [bleServiceProvider.overrideWithValue(ble)],
        child: const MaterialApp(
          home: Scaffold(body: PreviewLayoutToggle(deviceId: null)),
        ),
      ),
    );
    await tester.tap(find.text('Both'));
    await tester.pump();
    expect(ble.lastPreviewLayout, PreviewLayout.single);
  });
}
