// U2 — diagnostics page renders real telemetry, never fabricated values (R4-R6).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sst_cam_app/core/ble/ble_providers.dart';
import 'package:sst_cam_app/core/models/command.dart';
import 'package:sst_cam_app/core/models/telemetry.dart';
import 'package:sst_cam_app/core/version/version_info.dart';
import 'package:sst_cam_app/features/discovery/diagnostics_page.dart';

import '../../test_helpers.dart';

const _deviceId = 'SST-CAM-001';

DeviceTelemetry _telemetry({int? battery, int? rssi, bool internet = false}) =>
    DeviceTelemetry(
      storageFreeBytes: 32 * 1024 * 1024 * 1024,
      storageTotalBytes: 64 * 1024 * 1024 * 1024,
      wifiState: WifiState.connected,
      wifiSsid: 'SST-AP',
      wifiSignalDbm: rssi,
      internetReachable: internet,
      tempCelsius: 47,
      ramUsedPct: 31,
      cpuUsedPct: 12,
      uptimeSeconds: 3720, // 1h 2m
      isRecording: true,
      isStreaming: false,
      batteryLevelPct: battery,
    );

Future<void> _pump(
  WidgetTester tester, {
  required List<Override> overrides,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        // Real DeviceInfo so the fw/wire row shows values, not extra "—".
        connectedDeviceInfoProvider(_deviceId).overrideWith(
          (ref) async => const DeviceInfoResponse(
            deviceId: _deviceId,
            firmwareVersion: '0.1.0',
            protocolVersion: 2,
          ),
        ),
        ...overrides,
      ],
      child: const MaterialApp(home: DiagnosticsPage(deviceId: _deviceId)),
    ),
  );
  await tester.pump(); // let stream/future providers emit
}

void main() {
  testWidgets('renders real telemetry; no fabricated mock-page symbols', (
    tester,
  ) async {
    await _pump(
      tester,
      overrides: [
        telemetryProvider(
          _deviceId,
        ).overrideWith((ref) => Stream.value(_telemetry(internet: true))),
        appVersionProvider.overrideWith((ref) async => '0.1.0 (dev)'),
      ],
    );
    expect(find.text('32 / 64 GB'), findsOneWidget);
    expect(find.text('47 °C'), findsOneWidget);
    expect(find.text('1h 2m'), findsOneWidget);
    expect(find.text('SST-AP'), findsOneWidget);
    expect(find.text('Online'), findsOneWidget);
    // The old all-mock page is gone — no fabricated MTU / command-log content.
    expect(find.text('MTU'), findsNothing);
    expect(find.text('Recent commands'), findsNothing);
  });

  testWidgets('battery + RSSI unavailable render "—", never zero', (
    tester,
  ) async {
    await _pump(
      tester,
      overrides: [
        telemetryProvider(_deviceId).overrideWith(
          (ref) => Stream.value(_telemetry(battery: null, rssi: null)),
        ),
        appVersionProvider.overrideWith((ref) async => '0.1.0 (dev)'),
        // Pin health OK so the U4 camera tiles don't add their own "—"s —
        // this test counts the battery + RSSI dashes only.
        healthyDeviceOverride(),
      ],
    );
    // Battery + WiFi RSSI tiles both show the em dash, not "0".
    expect(find.text('—'), findsNWidgets(2));
    expect(find.text('0 %'), findsNothing);
  });

  testWidgets('disconnected shows a note, not a grid of zeros', (tester) async {
    await _pump(
      tester,
      overrides: [
        telemetryProvider(
          _deviceId,
        ).overrideWith((ref) => const Stream.empty()),
        appVersionProvider.overrideWith((ref) async => '0.1.0 (dev)'),
      ],
    );
    expect(
      find.text('Connect to a camera to view diagnostics'),
      findsOneWidget,
    );
  });
}
