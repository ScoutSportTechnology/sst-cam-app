// U6 — app provisioning flow: offer ONLY the phone's current SSID, run the
// migration handshake (transition → authenticated preview probe → confirm/deny
// by migration-id), gated on protocol_version >= 4.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sst_cam_app/core/ble/ble_providers.dart';
import 'package:sst_cam_app/core/models/command.dart' show DeviceInfoResponse;
import 'package:sst_cam_app/core/errors/friendly_status.dart'
    show ConnectivityOutcome, FriendlyStatus;
import 'package:sst_cam_app/core/models/network_config.dart'
    show
        EthernetUplink,
        LanPath,
        NetworkConfig,
        NetworkConfigResult,
        WifiUplink;
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

/// A BLE service whose plain Get reports a COMMITTED WiFi-STA LAN path with a
/// usable credential (proto v5, migration_id == 0) — a reconnect probe target,
/// NOT a new migration. Lets a widget test exercise the U9 gate: "connected"
/// only after the identity probe passes.
class _LanCommittedBle extends MockBleService {
  _LanCommittedBle()
    : super(
        scanDeviceAppearDelays: const [Duration.zero],
        connectionDelay: Duration.zero,
        randomSeed: 1,
      );

  static const ssid = 'Field-House-WiFi';

  @override
  Future<NetworkConfigResult> getNetworkConfig(String deviceId) async {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    return NetworkConfigResult(
      config: NetworkConfig(wifi: WifiUplink(enabled: true, ssid: ssid)),
      ethernetUp: false,
      ethernetAddress: '',
      wifiUp: true,
      wifiStatus: 'connected',
      inSharedWifi: true,
      currentSsid: ssid,
      lanPath: LanPath.wifiSta,
      previewEndpoint: '10.10.1.142',
      previewCredential: 'preview:secret',
    );
  }
}

/// U10: Ethernet is the COMMITTED LAN path on a plain Get (confirm id 0 — already
/// settled, NOT a pending handshake): the gate identity-probes the Ethernet IP,
/// then the card shows the Ethernet-connected state (no Wi-Fi password).
class _EthernetLanBle extends MockBleService {
  _EthernetLanBle()
    : super(
        scanDeviceAppearDelays: const [Duration.zero],
        connectionDelay: Duration.zero,
        randomSeed: 1,
      );

  @override
  Future<NetworkConfigResult> getNetworkConfig(String deviceId) async {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    return const NetworkConfigResult(
      config: NetworkConfig(ethernet: EthernetUplink(enabled: true)),
      ethernetUp: true,
      ethernetAddress: '10.10.1.30/24',
      wifiUp: false,
      wifiStatus: '',
      lanPath: LanPath.ethernet,
      ethernetEndpoint: '10.10.1.30',
      ethernetCredential: 'preview:eth-secret',
      ethernetDhcp: true,
    );
  }
}

/// U10: a PENDING Ethernet-LAN handshake on a plain Get (confirm id != 0) — the
/// app must probe the Ethernet IP + send confirmLanPath (AE8).
class _EthernetHandshakeBle extends MockBleService {
  _EthernetHandshakeBle()
    : super(
        scanDeviceAppearDelays: const [Duration.zero],
        connectionDelay: Duration.zero,
        randomSeed: 1,
      );

  static const confirmId = 7;

  @override
  Future<NetworkConfigResult> getNetworkConfig(String deviceId) async {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    return const NetworkConfigResult(
      config: NetworkConfig(ethernet: EthernetUplink(enabled: true)),
      ethernetUp: true,
      ethernetAddress: '10.10.1.30/24',
      wifiUp: false,
      wifiStatus: '',
      lanPath: LanPath.ethernet,
      ethernetEndpoint: '10.10.1.30',
      ethernetCredential: 'preview:eth-secret',
      ethernetConfirmId: confirmId,
      ethernetDhcp: true,
    );
  }
}

/// U10 E5: Ethernet is present as a DIFFERENT-subnet uplink (up + addressed) but
/// NOT the committed LAN path (P2P) — Wi-Fi provisioning must STILL be offered.
class _EthernetUplinkBle extends MockBleService {
  _EthernetUplinkBle()
    : super(
        scanDeviceAppearDelays: const [Duration.zero],
        connectionDelay: Duration.zero,
        randomSeed: 1,
      );

  @override
  Future<NetworkConfigResult> getNetworkConfig(String deviceId) async {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    return const NetworkConfigResult(
      config: NetworkConfig(ethernet: EthernetUplink(enabled: true)),
      ethernetUp: true,
      ethernetAddress: '192.168.9.20/24',
      wifiUp: false,
      wifiStatus: '',
      lanPath: LanPath.p2p,
      ethernetDhcp: true,
    );
  }
}

/// U10 E3: Ethernet is the LAN on load, but a subsequent Set reports the cable
/// pulled with NO Wi-Fi provisioned — the app must surface "connect to Wi-Fi to
/// keep app access" rather than silently dropping to P2P/offline.
class _EthernetThenLostBle extends MockBleService {
  _EthernetThenLostBle()
    : super(
        scanDeviceAppearDelays: const [Duration.zero],
        connectionDelay: Duration.zero,
        randomSeed: 1,
      );

  @override
  Future<NetworkConfigResult> getNetworkConfig(String deviceId) async {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    return const NetworkConfigResult(
      config: NetworkConfig(ethernet: EthernetUplink(enabled: true)),
      ethernetUp: true,
      ethernetAddress: '10.10.1.30/24',
      wifiUp: false,
      wifiStatus: '',
      lanPath: LanPath.ethernet,
      ethernetEndpoint: '10.10.1.30',
      ethernetCredential: 'preview:eth-secret',
      ethernetDhcp: true,
    );
  }

  @override
  Future<NetworkConfigResult> setNetworkConfig(
    String deviceId,
    NetworkConfig config,
  ) async {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    // Cable pulled between load and Apply: no LAN path, Ethernet down, no Wi-Fi.
    return const NetworkConfigResult(
      config: NetworkConfig(),
      ethernetUp: false,
      ethernetAddress: '',
      wifiUp: false,
      wifiStatus: '',
      lanPath: LanPath.p2p,
    );
  }
}

Future<void> _pump(
  WidgetTester tester, {
  required MockBleService ble,
  required MockWifiService wifi,
  required bool reachable,
  int protocolVersion = 5,
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
    'U10 regression: provisioning against a 2.4 GHz network is ACCEPTED — the '
    'stale needs-5GHz gate no longer blocks it (regdomain finding)',
    (tester) async {
      final ble = _newBle();
      final wifi = MockWifiService(
        mockPhoneSsid: 'Field-House-WiFi',
        mockPhoneFrequencyMhz: 2437, // 2.4 GHz (ch 6) — must NOT be rejected
      );
      await _pump(tester, ble: ble, wifi: wifi, reachable: true);

      await tester.tap(find.text('Connect'));
      await tester.pump(); // enter the transition (proves it was NOT gated)
      expect(find.text('Switching to your network…'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 120));
      await tester.pump(const Duration(milliseconds: 120));

      // The join proceeded to a connected state — never a "switch to 5 GHz" block.
      expect(find.textContaining('Connected to'), findsOneWidget);
      expect(find.textContaining('5 GHz'), findsNothing);

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
    'U9: committed LAN path (v5 plain Get) + probe 2xx → "connected" shown '
    '(gated on the identity probe, not inSharedWifi alone) (R8)',
    (tester) async {
      final ble = _LanCommittedBle();
      final wifi = MockWifiService(mockPhoneSsid: 'Field-House-WiFi');
      // Probe passes → the identity gate lets "connected" through.
      await _pump(tester, ble: ble, wifi: wifi, reachable: true);

      expect(find.textContaining('Connected to'), findsOneWidget);
      expect(find.text('Disconnect'), findsOneWidget);
      // The transient / probe-failure copy is NOT shown once the probe passes.
      expect(find.textContaining('Reconnecting your camera'), findsNothing);

      await ble.dispose();
      await wifi.dispose();
    },
  );

  testWidgets(
    'U9: committed LAN answers but identity check FAILS → NOT "connected"; '
    'probe-failure copy shown, DISTINCT from the isolated copy (AE7)',
    (tester) async {
      final ble = _LanCommittedBle();
      final wifi = MockWifiService(mockPhoneSsid: 'Field-House-WiFi');
      // A same-subnet host answers but fails the auth/identity check → probe false.
      await _pump(tester, ble: ble, wifi: wifi, reachable: false);

      // Not connected.
      expect(find.textContaining('Connected to'), findsNothing);
      // The probe-failure banner renders its own copy…
      expect(
        find.textContaining("Couldn't reach your camera on the local network"),
        findsOneWidget,
      );
      // …which is DISTINCT from the different-subnet `isolated` copy.
      final isolatedCopy = FriendlyStatus.forOutcome(
        ConnectivityOutcome.isolated,
      ).message;
      expect(find.textContaining(isolatedCopy), findsNothing);

      await ble.dispose();
      await wifi.dispose();
    },
  );

  test('U9: probe-failure + switching copy are DISTINCT from isolated', () {
    final isolated = FriendlyStatus.forOutcome(
      ConnectivityOutcome.isolated,
    ).message;
    final probeFailed = FriendlyStatus.forOutcome(
      ConnectivityOutcome.reachabilityProbeFailed,
    ).message;
    final switching = FriendlyStatus.forOutcome(
      ConnectivityOutcome.switching,
    ).message;
    expect(probeFailed, isNot(isolated));
    expect(switching, isNot(isolated));
    expect(probeFailed, isNot(switching));
  });

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

  testWidgets(
    'U10: committed Ethernet LAN (v5 plain Get) + probe 2xx → Ethernet-connected '
    'card, NO password field, "on your network via Ethernet" banner (AE9)',
    (tester) async {
      final ble = _EthernetLanBle();
      final wifi = MockWifiService(mockPhoneSsid: 'Field-House-WiFi');
      await _pump(tester, ble: ble, wifi: wifi, reachable: true);

      // Ethernet-connected state — the dead Wi-Fi password field is suppressed.
      expect(
        find.textContaining('on your network via Ethernet'),
        findsOneWidget,
      );
      expect(find.widgetWithText(TextField, 'Wi-Fi password'), findsNothing);
      // No STA connected card / Connect flow while Ethernet is the LAN.
      expect(find.text('Connect'), findsNothing);
      expect(find.textContaining('Connected to "'), findsNothing);

      await ble.dispose();
      await wifi.dispose();
    },
  );

  testWidgets(
    'U10: pending Ethernet handshake → probe Ethernet endpoint+credential → '
    'confirmLanPath(reachable) → connected via Ethernet (AE8)',
    (tester) async {
      final ble = _EthernetHandshakeBle();
      final wifi = MockWifiService(mockPhoneSsid: 'Field-House-WiFi');
      await _pump(tester, ble: ble, wifi: wifi, reachable: true);

      // The app ran the handshake: confirmLanPath was sent for the Ethernet path
      // with the firmware's confirm id + a reachable verdict.
      expect(ble.lastConfirmLanPath, isNotNull);
      expect(
        ble.lastConfirmLanPath!.confirmId,
        _EthernetHandshakeBle.confirmId,
      );
      expect(ble.lastConfirmLanPath!.path, LanPath.ethernet);
      expect(ble.lastConfirmLanPath!.reachable, isTrue);
      // …and the card shows the Ethernet-connected state.
      expect(
        find.textContaining('on your network via Ethernet'),
        findsOneWidget,
      );

      await ble.dispose();
      await wifi.dispose();
    },
  );

  testWidgets(
    'U10: Ethernet present as a different-subnet uplink (not the LAN) → Wi-Fi '
    'provisioning STILL offered + an "Ethernet: powering stream upload" line',
    (tester) async {
      final ble = _EthernetUplinkBle();
      final wifi = MockWifiService(mockPhoneSsid: 'Field-House-WiFi');
      await _pump(tester, ble: ble, wifi: wifi, reachable: true);

      // The dead password field is NOT suppressed — Ethernet is only an uplink.
      expect(find.widgetWithText(TextField, 'Wi-Fi password'), findsOneWidget);
      expect(find.text('Connect'), findsOneWidget);
      // Not the Ethernet-connected LAN state.
      expect(find.textContaining('on your network via Ethernet'), findsNothing);
      // The uplink status line signals the consequence of unplugging (E5).
      expect(find.textContaining('powering stream upload'), findsOneWidget);

      await ble.dispose();
      await wifi.dispose();
    },
  );

  testWidgets(
    'U10: Ethernet handshake probe FAILS → probe-failure copy, NOT connected, '
    'falls back to offering Wi-Fi provisioning',
    (tester) async {
      final ble = _EthernetHandshakeBle();
      final wifi = MockWifiService(mockPhoneSsid: 'Field-House-WiFi');
      // Probe returns false → de-select; confirmLanPath(reachable:false).
      await _pump(tester, ble: ble, wifi: wifi, reachable: false);

      expect(ble.lastConfirmLanPath!.reachable, isFalse);
      // Not connected via Ethernet…
      expect(find.textContaining('on your network via Ethernet'), findsNothing);
      // …probe-failure copy shown, and the Wi-Fi Connect flow is offered again.
      expect(
        find.textContaining("Couldn't reach your camera on the local network"),
        findsOneWidget,
      );
      expect(find.text('Connect'), findsOneWidget);

      await ble.dispose();
      await wifi.dispose();
    },
  );

  testWidgets(
    'U10 E3: Ethernet was the LAN with no Wi-Fi, cable pulled → "connect to '
    'Wi-Fi to keep app access" state (reverse of R14)',
    (tester) async {
      final ble = _EthernetThenLostBle();
      final wifi = MockWifiService(mockPhoneSsid: 'Field-House-WiFi');
      await _pump(tester, ble: ble, wifi: wifi, reachable: true);

      // Loaded on Ethernet as the LAN.
      expect(
        find.textContaining('on your network via Ethernet'),
        findsOneWidget,
      );

      // A re-apply now reports the cable pulled with no Wi-Fi provisioned (E3).
      await tester.tap(find.text('Apply'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));

      expect(
        find.textContaining('Ethernet disconnected — connect to Wi-Fi'),
        findsOneWidget,
      );
      expect(find.textContaining('on your network via Ethernet'), findsNothing);

      await ble.dispose();
      await wifi.dispose();
    },
  );
}
