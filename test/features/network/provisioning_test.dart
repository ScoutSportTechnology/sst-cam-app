// U6 — app provisioning flow: offer ONLY the phone's current SSID, run the
// migration handshake (transition → authenticated preview probe → confirm/deny
// by migration-id), gated on protocol_version >= 4.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sst_cam_app/core/ble/ble_providers.dart';
import 'package:sst_cam_app/core/models/command.dart' show DeviceInfoResponse;
import 'package:sst_cam_app/core/models/network_config.dart'
    show NetworkConfig, NetworkConfigResult, WifiUplink;
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

/// A BLE service that reports the camera ALREADY connected in shared-WiFi (S2)
/// to [currentSsid] on load, so a test can exercise the reconnect / change-
/// networks / Disconnect surface without replaying the migration handshake.
class _ConnectedBle extends MockBleService {
  _ConnectedBle({required this.currentSsid, this.switchFails = false})
    : super(
        scanDeviceAppearDelays: const [Duration.zero],
        connectionDelay: Duration.zero,
        randomSeed: 1,
      );

  final String currentSsid;
  final bool switchFails;

  @override
  Future<NetworkConfigResult> getNetworkConfig(String deviceId) async {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    return NetworkConfigResult(
      config: NetworkConfig(wifi: WifiUplink(enabled: true, ssid: currentSsid)),
      ethernetUp: false,
      ethernetAddress: '',
      wifiUp: true,
      wifiStatus: 'connected',
      inSharedWifi: true,
      currentSsid: currentSsid,
    );
  }

  @override
  Future<NetworkConfigResult> setNetworkConfig(
    String deviceId,
    NetworkConfig config,
  ) async {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    // A change-networks that fails: the firmware has already reverted to P2P, so
    // the handler returns ERROR — modelled here as a thrown BLE failure.
    if (switchFails && config.wifi.enabled) {
      throw Exception('failed to join wifi (check the password)');
    }
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

      // U4: a connected banner naming the SSID + a Disconnect action replace the
      // old "Connected" button label.
      expect(find.textContaining('Connected to'), findsOneWidget);
      expect(find.textContaining('streaming are on'), findsOneWidget);
      expect(find.text('Disconnect'), findsOneWidget);
      // The link was bonded before credentials were sent (INV6/AE7).
      expect(ble.bonded, isTrue);

      // U4: Disconnect reverts to P2P → the card returns to the Connect flow.
      await tester.tap(find.text('Disconnect'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      expect(find.text('Connect'), findsOneWidget);
      expect(find.text('Disconnect'), findsNothing);

      await ble.dispose();
      await wifi.dispose();
    },
  );

  testWidgets(
    'phone on 2.4 GHz → validated up front: needs-5GHz message, nothing sent',
    (tester) async {
      final ble = _BondFailBle(); // counts setNetworkConfig; must stay 0
      final wifi = MockWifiService(
        mockPhoneSsid: 'Field-House-WiFi',
        mockPhoneFrequencyMhz: 2437, // 2.4 GHz (ch 6)
      );
      await _pump(tester, ble: ble, wifi: wifi, reachable: true);

      await tester.tap(find.text('Connect'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Blocked before any BLE traffic — clear "switch to 5 GHz" guidance.
      expect(find.textContaining('5 GHz'), findsWidgets);
      expect(ble.setCalls, 0);
      expect(find.text('Connected'), findsNothing);

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

  testWidgets(
    'reconnect while camera is on a DIFFERENT network → connected banner + a '
    'guarded Switch to the phone\'s network (R3 change-networks)',
    (tester) async {
      final ble = _ConnectedBle(currentSsid: 'Old-Net');
      // The phone has since moved to a different Wi-Fi than the camera is on.
      final wifi = MockWifiService(mockPhoneSsid: 'New-Net');
      await _pump(tester, ble: ble, wifi: wifi, reachable: true);

      // The connected banner names the arbiter's SSID, and the change-networks
      // affordance offers a guarded switch to the phone's current network.
      expect(find.textContaining('Connected to'), findsOneWidget);
      expect(find.textContaining('Old-Net'), findsWidgets);
      expect(find.textContaining('Switch to'), findsOneWidget);
      expect(find.textContaining('Switching will disconnect'), findsOneWidget);
      expect(find.text('Disconnect'), findsOneWidget);
      // Never the alarming "in progress" copy while merely connected.
      expect(find.textContaining('already in progress'), findsNothing);

      await ble.dispose();
      await wifi.dispose();
    },
  );

  testWidgets(
    'change-networks that FAILS → "reverted to direct" copy, not a generic '
    'error (R3 destructive-switch)',
    (tester) async {
      final ble = _ConnectedBle(currentSsid: 'Old-Net', switchFails: true);
      final wifi = MockWifiService(mockPhoneSsid: 'New-Net');
      await _pump(tester, ble: ble, wifi: wifi, reachable: true);

      await tester.tap(find.textContaining('Switch to'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));

      // The destructive-failure path: the camera fell back to direct (P2P), and
      // the copy says so rather than surfacing a raw join error.
      expect(
        find.textContaining('went back to a direct connection'),
        findsOneWidget,
      );

      await ble.dispose();
      await wifi.dispose();
    },
  );
}
