// U5 / R4 — shared-WiFi (S2) auto-revert: when the phone drops the shared Wi-Fi
// while the camera is in S2, the app sends exactly ONE wifi.enabled=false so the
// firmware reverts to P2P. A flap that recovers sends nothing (lean model — no
// reconnect loop, no group re-form).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sst_cam_app/core/ble/ble_providers.dart';
import 'package:sst_cam_app/core/ble/ble_service.dart';
import 'package:sst_cam_app/core/models/network_config.dart';
import 'package:sst_cam_app/core/wifi/wifi_auto_revert.dart';
import 'package:sst_cam_app/core/wifi/wifi_providers.dart';
import 'package:sst_cam_app/features/camera/camera_state.dart'
    show activeCameraIdProvider;
import 'package:sst_cam_app/mock/emulator/mock_wifi_connectivity_service.dart';

const _id = 'cam-1';

/// A BLE fake that answers GetNetworkConfig with a scriptable S2 state and
/// records every SetNetworkConfig's wifi.enabled — so a test can prove the revert
/// fired exactly once with WiFi disabled.
class _FakeBle implements BleService {
  _FakeBle({required this.inSharedWifi});
  bool inSharedWifi;
  int getCalls = 0;
  final List<bool> setWifiEnabled = [];

  @override
  Future<NetworkConfigResult> getNetworkConfig(String deviceId) async {
    getCalls++;
    return NetworkConfigResult(
      config: NetworkConfig(
        wifi: WifiUplink(enabled: inSharedWifi, ssid: 'Net'),
      ),
      ethernetUp: false,
      ethernetAddress: '',
      wifiUp: inSharedWifi,
      wifiStatus: '',
      inSharedWifi: inSharedWifi,
      currentSsid: inSharedWifi ? 'Net' : '',
    );
  }

  @override
  Future<NetworkConfigResult> setNetworkConfig(
    String deviceId,
    NetworkConfig config,
  ) async {
    setWifiEnabled.add(config.wifi.enabled);
    inSharedWifi = false; // arbiter reverted
    return NetworkConfigResult(
      config: config,
      ethernetUp: false,
      ethernetAddress: '',
      wifiUp: false,
      wifiStatus: '',
      inSharedWifi: false,
      currentSsid: '',
    );
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

ProviderContainer _container(_FakeBle ble, MockWifiConnectivityService conn) {
  final c = ProviderContainer(
    overrides: [
      bleServiceProvider.overrideWithValue(ble),
      wifiConnectivityServiceProvider.overrideWithValue(conn),
      activeCameraIdProvider.overrideWith((ref) => _id),
      wifiAutoRevertDebounceProvider.overrideWithValue(
        const Duration(milliseconds: 40),
      ),
    ],
  );
  c.listen(wifiAutoRevertProvider, (_, _) {});
  return c;
}

// Let the stream subscription attach + the initial "available" seed propagate.
Future<void> _subscribed() =>
    Future<void>.delayed(const Duration(milliseconds: 60));

// A little past the 40ms debounce + the async Get/Set round-trip.
Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 140));

void main() {
  test(
    'settled loss while in S2 → exactly one wifi.enabled=false revert',
    () async {
      final ble = _FakeBle(inSharedWifi: true);
      final conn = MockWifiConnectivityService();
      final c = _container(ble, conn);
      addTearDown(c.dispose);
      addTearDown(conn.dispose);
      await _subscribed();

      conn.emit(false); // phone dropped the shared Wi-Fi
      await _settle();

      expect(ble.setWifiEnabled, [
        false,
      ], reason: 'exactly one revert, WiFi off');
    },
  );

  test('flap that recovers before the debounce → zero reverts', () async {
    final ble = _FakeBle(inSharedWifi: true);
    final conn = MockWifiConnectivityService();
    final c = _container(ble, conn);
    addTearDown(c.dispose);
    addTearDown(conn.dispose);
    await _subscribed();

    conn.emit(false);
    await Future<void>.delayed(const Duration(milliseconds: 15)); // < debounce
    conn.emit(true); // recovered
    await _settle();

    expect(
      ble.setWifiEnabled,
      isEmpty,
      reason: 'a recovered flap reverts nothing',
    );
  });

  test('flap that settles disconnected → exactly one revert', () async {
    final ble = _FakeBle(inSharedWifi: true);
    final conn = MockWifiConnectivityService();
    final c = _container(ble, conn);
    addTearDown(c.dispose);
    addTearDown(conn.dispose);
    await _subscribed();

    conn.emit(false);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    conn.emit(true);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    conn.emit(false); // settles disconnected
    await _settle();

    expect(ble.setWifiEnabled, [false]);
  });

  test('not in S2 (P2P) → a Wi-Fi loss reverts nothing', () async {
    final ble = _FakeBle(inSharedWifi: false);
    final conn = MockWifiConnectivityService();
    final c = _container(ble, conn);
    addTearDown(c.dispose);
    addTearDown(conn.dispose);
    await _subscribed();

    conn.emit(false);
    await _settle();

    expect(
      ble.setWifiEnabled,
      isEmpty,
      reason: 'no revert when not in shared WiFi',
    );
  });
}
