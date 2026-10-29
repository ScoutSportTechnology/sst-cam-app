// U5 — Settings → Network page: loads the camera's uplink config over BLE,
// edits it, and applies it back.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sst_cam_app/core/ble/ble_providers.dart';
import 'package:sst_cam_app/core/ble/ble_service.dart'
    show BleNetworkConfigUnsupportedException;
import 'package:sst_cam_app/core/models/network_config.dart';
import 'package:sst_cam_app/features/camera/camera_state.dart'
    show activeCameraIdProvider;
import 'package:sst_cam_app/features/settings/network/network_settings_page.dart';
import 'package:sst_cam_app/mock/emulator/mock_ble_service.dart';

MockBleService _newMock() => MockBleService(
  scanDeviceAppearDelays: const [Duration.zero],
  connectionDelay: Duration.zero,
  randomSeed: 1,
);

/// A MockBleService whose network-config round-trips are scripted by the test:
/// a fixed get result, a settable set behaviour, and a call counter — lets the
/// widget tests drive the error / unsupported / live-state / double-tap paths
/// without touching the rest of the BLE surface.
class _ScriptedBleService extends MockBleService {
  _ScriptedBleService({this.getResult, this.getThrows, this.setThrows})
    : super(
        scanDeviceAppearDelays: const [Duration.zero],
        connectionDelay: Duration.zero,
        randomSeed: 1,
      );

  final NetworkConfigResult? getResult;
  final Object? getThrows;
  final Object? setThrows;

  int setCalls = 0;
  NetworkConfig? lastSet;

  @override
  Future<NetworkConfigResult> getNetworkConfig(String deviceId) async {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    if (getThrows != null) throw getThrows!;
    return getResult ?? _empty();
  }

  @override
  Future<NetworkConfigResult> setNetworkConfig(
    String deviceId,
    NetworkConfig config,
  ) async {
    setCalls++;
    lastSet = config;
    await Future<void>.delayed(const Duration(milliseconds: 10));
    if (setThrows != null) throw setThrows!;
    return NetworkConfigResult(
      config: config,
      ethernetUp: config.ethernet.enabled,
      ethernetAddress: config.ethernet.enabled ? '10.0.0.5/24' : '',
      wifiUp: false,
      wifiStatus: '',
    );
  }

  static NetworkConfigResult _empty() => const NetworkConfigResult(
    config: NetworkConfig(),
    ethernetUp: false,
    ethernetAddress: '',
    wifiUp: false,
    wifiStatus: '',
  );
}

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

  // --- Toggle-intent preservation (correctness / FR-002) -------------------

  testWidgets(
    'live-up but configured-off ethernet: Apply preserves stored intent '
    '(enabled stays false)',
    (tester) async {
      final mock = _ScriptedBleService(
        // Configured OFF, but the link is physically up.
        getResult: const NetworkConfigResult(
          config: NetworkConfig(ethernet: EthernetUplink(enabled: false)),
          ethernetUp: true,
          ethernetAddress: '10.0.0.9/24',
          wifiUp: false,
          wifiStatus: '',
        ),
      );
      await _pump(tester, mock);

      // The toggle DISPLAYS on (live-derived) ...
      final ethSwitch = tester.widget<Switch>(find.byType(Switch).first);
      expect(ethSwitch.value, isTrue);

      // ... but the user never touched it, so Apply must NOT flip stored intent.
      await tester.tap(find.text('Apply'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(mock.lastSet, isNotNull);
      expect(mock.lastSet!.ethernet.enabled, isFalse);

      await mock.dispose();
    },
  );

  testWidgets('user toggles ethernet on → Apply pushes enabled=true', (
    tester,
  ) async {
    final mock = _ScriptedBleService(
      getResult: const NetworkConfigResult(
        config: NetworkConfig(ethernet: EthernetUplink(enabled: false)),
        ethernetUp: false,
        ethernetAddress: '',
        wifiUp: false,
        wifiStatus: '',
      ),
    );
    await _pump(tester, mock);

    // User explicitly toggles ethernet ON.
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Apply'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(mock.lastSet, isNotNull);
    expect(mock.lastSet!.ethernet.enabled, isTrue);

    await mock.dispose();
  });

  // --- Double-tap Apply (FR-003) -------------------------------------------

  testWidgets('double-tap Apply with no intervening pump → one set call', (
    tester,
  ) async {
    final mock = _ScriptedBleService();
    await _pump(tester, mock);

    // Two taps in the same frame, before the button can re-render disabled.
    await tester.tap(find.text('Apply'));
    await tester.tap(find.text('Apply'), warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(mock.setCalls, 1);

    await mock.dispose();
  });

  // --- Save-error path (T05) -----------------------------------------------

  testWidgets('setNetworkConfig throws → "Save failed" shown', (tester) async {
    final mock = _ScriptedBleService(setThrows: Exception('boom'));
    await _pump(tester, mock);

    await tester.tap(find.text('Apply'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.textContaining('Save failed'), findsOneWidget);

    await mock.dispose();
  });

  // --- Unsupported (old firmware) path (AC-001) ----------------------------

  testWidgets('getNetworkConfig unsupported → "firmware too old" message', (
    tester,
  ) async {
    final mock = _ScriptedBleService(
      getThrows: const BleNetworkConfigUnsupportedException(),
    );
    await _pump(tester, mock);

    expect(find.textContaining('firmware is too old'), findsOneWidget);

    await mock.dispose();
  });

  testWidgets('setNetworkConfig unsupported → "firmware too old" message', (
    tester,
  ) async {
    final mock = _ScriptedBleService(
      setThrows: const BleNetworkConfigUnsupportedException(),
    );
    await _pump(tester, mock);

    await tester.tap(find.text('Apply'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.textContaining('firmware is too old'), findsOneWidget);

    await mock.dispose();
  });

  // --- Load-error path (T??) -----------------------------------------------

  testWidgets('getNetworkConfig throws → error text shown, no hang', (
    tester,
  ) async {
    final mock = _ScriptedBleService(getThrows: Exception('radio gone'));
    await _pump(tester, mock);

    expect(
      find.textContaining('Could not read network config'),
      findsOneWidget,
    );

    await mock.dispose();
  });

  // --- DHCP toggle reveals static fields (T06) -----------------------------

  testWidgets('DHCP toggle off reveals static IP/gateway/DNS fields', (
    tester,
  ) async {
    final mock = _newMock();
    await _pump(tester, mock);

    // Enable ethernet so its DHCP toggle + fields are visible.
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();

    // Static fields hidden while DHCP is on.
    expect(
      find.widgetWithText(TextField, 'IP address (CIDR, e.g. 10.0.0.5/24)'),
      findsNothing,
    );

    // Toggle DHCP off (the SwitchListTile labelled 'Automatic (DHCP)').
    await tester.tap(find.text('Automatic (DHCP)').first);
    await tester.pumpAndSettle();

    expect(
      find.widgetWithText(TextField, 'IP address (CIDR, e.g. 10.0.0.5/24)'),
      findsOneWidget,
    );
    expect(find.widgetWithText(TextField, 'Gateway'), findsWidgets);
    expect(find.widgetWithText(TextField, 'DNS'), findsWidgets);

    await mock.dispose();
  });
}
