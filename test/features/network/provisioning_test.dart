// U6 — app provisioning flow: offer ONLY the phone's current SSID, run the
// migration handshake (transition → authenticated preview probe → confirm/deny
// by migration-id), gated on protocol_version >= 4.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sst_cam_app/core/ble/ble_providers.dart';
import 'package:sst_cam_app/core/models/command.dart' show DeviceInfoResponse;
import 'package:sst_cam_app/core/models/network_config.dart'
    show NetworkConfig, NetworkConfigResult;
import 'package:sst_cam_app/core/wifi/wifi_handoff.dart'
    show
        PreviewReachabilityProbe,
        previewProbeProvider,
        kPreviewProbeTimeout,
        kFirmwareSelfRevertWindow;
import 'package:sst_cam_app/core/wifi/wifi_providers.dart'
    show wifiServiceProvider;
import 'package:sst_cam_app/features/camera/camera_state.dart'
    show activeCameraIdProvider;
import 'package:sst_cam_app/features/settings/network/network_settings_page.dart';
import 'package:sst_cam_app/mock/emulator/mock_ble_service.dart';
import 'package:sst_cam_app/mock/emulator/mock_wifi_service.dart';

const _deviceId = 'sst-cam-0001';

/// A probe with a scripted, immediate verdict — the migration flow under test
/// must not touch a real socket.
class _FakeProbe implements PreviewReachabilityProbe {
  const _FakeProbe(this.reachable);
  final bool reachable;
  @override
  Future<bool> probe(String endpoint, String credential) async => reachable;
}

MockBleService _newBle() => MockBleService(
  scanDeviceAppearDelays: const [Duration.zero],
  connectionDelay: Duration.zero,
  randomSeed: 1,
);

/// A BLE service whose bond step always fails, and which counts setNetworkConfig
/// calls — so a test can prove credentials are never sent when bonding fails.
class _BondFailBle extends MockBleService {
  _BondFailBle()
    : super(
        scanDeviceAppearDelays: const [Duration.zero],
        connectionDelay: Duration.zero,
        randomSeed: 1,
      );

  int setCalls = 0;

  @override
  Future<void> ensureBonded(String deviceId) async {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    throw Exception('bond rejected');
  }

  @override
  Future<NetworkConfigResult> setNetworkConfig(
    String deviceId,
    NetworkConfig config,
  ) async {
    setCalls++;
    return super.setNetworkConfig(deviceId, config);
  }
}

Future<void> _pump(
  WidgetTester tester, {
  required MockBleService ble,
  required MockWifiService wifi,
  required bool reachable,
  int protocolVersion = 4,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        bleServiceProvider.overrideWithValue(ble),
        wifiServiceProvider.overrideWithValue(wifi),
        activeCameraIdProvider.overrideWith((ref) => _deviceId),
        connectedDeviceInfoProvider(_deviceId).overrideWith(
          (ref) async => DeviceInfoResponse(
            deviceId: _deviceId,
            protocolVersion: protocolVersion,
          ),
        ),
        previewProbeProvider.overrideWithValue(_FakeProbe(reachable)),
      ],
      child: const MaterialApp(home: NetworkSettingsPage()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('app probe timeout is strictly shorter than the firmware self-revert '
      'window (KTD5 / OQ1)', () {
    expect(kPreviewProbeTimeout < kFirmwareSelfRevertWindow, isTrue);
  });

  testWidgets(
    'phone on a network → offers only that SSID; connect → transition '
    '→ probe success → confirm → connected + streaming (AE2)',
    (tester) async {
      final ble = _newBle();
      final wifi = MockWifiService(mockPhoneSsid: 'Field-House-WiFi');
      await _pump(tester, ble: ble, wifi: wifi, reachable: true);

      // The provisioning card offers exactly the phone's current SSID — never a
      // scan/pick-any list, so no SSID *input* field exists in the card.
      expect(find.text('Field-House-WiFi'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Wi-Fi password'), findsOneWidget);
      expect(find.text('Connect'), findsOneWidget);

      await tester.tap(find.text('Connect'));
      await tester.pump(); // enter the transition state
      expect(find.text('Switching to your network…'), findsOneWidget);

      // Advance past the mock's setNetworkConfig + confirm round-trip delays.
      await tester.pump(const Duration(milliseconds: 120));
      await tester.pump(const Duration(milliseconds: 120));

      expect(find.text('Connected'), findsOneWidget);
      expect(find.textContaining('streaming are on'), findsOneWidget);
      // The link was bonded before credentials were sent (INV6/AE7).
      expect(ble.bonded, isTrue);

      await ble.dispose();
      await wifi.dispose();
    },
  );

  testWidgets(
    'bonding fails → friendly message, credentials never sent (INV6/AE7)',
    (tester) async {
      final ble = _BondFailBle();
      final wifi = MockWifiService(mockPhoneSsid: 'Field-House-WiFi');
      await _pump(tester, ble: ble, wifi: wifi, reachable: true);

      await tester.tap(find.text('Connect'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      await tester.pump(const Duration(milliseconds: 120));

      // The provision aborted at the bond step: no SetNetworkConfig was sent, so
      // the passphrase never crossed the (unencrypted) link, and the user sees a
      // friendly failure rather than "Connected".
      expect(ble.setCalls, 0);
      expect(find.text('Connected'), findsNothing);

      await ble.dispose();
      await wifi.dispose();
    },
  );

  testWidgets('probe fails (client isolation) → deny → friendly message, '
      'streaming off (AE3)', (tester) async {
    final ble = _newBle();
    final wifi = MockWifiService(mockPhoneSsid: 'Guest-Isolated');
    await _pump(tester, ble: ble, wifi: wifi, reachable: false);

    await tester.tap(find.text('Connect'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pump(const Duration(milliseconds: 120));

    // U7 isolation copy — never a raw error.
    expect(
      find.textContaining('keeps devices from talking to each other'),
      findsOneWidget,
    );
    // Not connected: the action reverts to "Connect".
    expect(find.text('Connected'), findsNothing);

    await ble.dispose();
    await wifi.dispose();
  });

  testWidgets('phone offline → provisioning disabled, streaming greyed (AE1)', (
    tester,
  ) async {
    final ble = _newBle();
    final wifi = MockWifiService(mockPhoneSsid: null);
    await _pump(tester, ble: ble, wifi: wifi, reachable: true);

    expect(
      find.textContaining('Join a Wi-Fi network on your phone'),
      findsOneWidget,
    );
    // No password field, no connect action while the phone is offline.
    expect(find.widgetWithText(TextField, 'Wi-Fi password'), findsNothing);
    expect(find.text('Connect'), findsNothing);

    await ble.dispose();
    await wifi.dispose();
  });

  testWidgets(
    'older firmware (protocol_version < 4) → provisioning not offered',
    (tester) async {
      final ble = _newBle();
      final wifi = MockWifiService(mockPhoneSsid: 'Field-House-WiFi');
      await _pump(
        tester,
        ble: ble,
        wifi: wifi,
        reachable: true,
        protocolVersion: 3,
      );

      // The provisioning card is absent on pre-v4 firmware; the legacy advanced
      // editor still renders.
      expect(find.text('Connect the camera to your Wi-Fi'), findsNothing);
      expect(find.text('Advanced network settings'), findsOneWidget);

      await ble.dispose();
      await wifi.dispose();
    },
  );
}
