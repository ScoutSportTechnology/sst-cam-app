import 'package:flutter_test/flutter_test.dart';
import 'package:sst_cam_app/core/models/network_config.dart';
import 'package:sst_cam_app/mock/emulator/mock_ble_service.dart';

// U4: the NetworkConfig BLE round-trip against the emulated firmware — set the
// camera's uplink, read it back, and confirm the gated wifi-STA status.
MockBleService _newMock() => MockBleService(
  scanDeviceAppearDelays: const [Duration.zero],
  connectionDelay: Duration.zero,
  randomSeed: 1,
);

void main() {
  const deviceId = 'sst-cam-0001';

  test(
    'setNetworkConfig applies + echoes ethernet status; getNetworkConfig reads it back',
    () async {
      final ble = _newMock();
      const config = NetworkConfig(
        ethernet: EthernetUplink(
          enabled: true,
          ip: UplinkIp(
            dhcp: false,
            address: '10.10.1.30/24',
            gateway: '10.10.1.1',
          ),
        ),
      );

      final setResult = await ble.setNetworkConfig(deviceId, config);
      expect(setResult.config.ethernet.enabled, isTrue);
      expect(setResult.config.ethernet.ip.address, '10.10.1.30/24');
      expect(setResult.ethernetUp, isTrue);
      expect(setResult.ethernetAddress, '10.10.1.30/24');

      final getResult = await ble.getNetworkConfig(deviceId);
      expect(getResult.config.ethernet.enabled, isTrue);
      expect(getResult.config.ethernet.ip.gateway, '10.10.1.1');
      expect(getResult.ethernetUp, isTrue);

      await ble.dispose();
    },
  );

  test('wifi-STA uplink begins a shared-WiFi (STA) migration — gate opened, '
      'protocol v4 (KTD2)', () async {
    final ble = _newMock();
    const config = NetworkConfig(
      wifi: WifiUplink(enabled: true, ssid: 'venue', password: 'secret'),
    );

    final result = await ble.setNetworkConfig(deviceId, config);
    expect(result.config.wifi.ssid, 'venue');
    // The connectivity arbiter starts a migration: a non-zero migration id +
    // an authenticated LAN preview endpoint/credential for the app to probe.
    expect(result.isMigrating, isTrue);
    expect(result.migrationId, isNot(0));
    expect(result.previewEndpoint, isNotEmpty);
    expect(result.previewCredential, isNotEmpty);
    // STA is not reported "up" until the app confirms reachability.
    expect(result.wifiUp, isFalse);

    // The app probes, then confirms reachable → the arbiter settles into S2.
    final confirm = await ble.confirmPreviewReachable(
      deviceId,
      migrationId: result.migrationId,
      reachable: true,
    );
    expect(confirm.migrationId, result.migrationId);
    expect(confirm.inSharedWifi, isTrue);

    await ble.dispose();
  });

  test('defaults: both uplinks disabled, nothing up', () async {
    final ble = _newMock();
    final result = await ble.getNetworkConfig(deviceId);
    expect(result.config.ethernet.enabled, isFalse);
    expect(result.config.wifi.enabled, isFalse);
    expect(result.ethernetUp, isFalse);
    expect(result.wifiUp, isFalse);
    await ble.dispose();
  });
}
