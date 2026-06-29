// Tests for WifiHandoffController — the single owner of the WiFi Direct group
// lifecycle. Lean recovery model: the controller brings the group up on BLE
// connect and tears it down on BLE disconnect, and does NOTHING in response to
// wifi-state transitions. Rejoining a dropped-but-stable group is the phone
// OS's job; the app must not re-form the group (that reactive loop was the
// SSID-flap storm). The key regression here is the inverse of the old behavior:
// a WiFi-only drop must NOT trigger an app-driven reconnect.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sst_cam_app/core/ble/ble_providers.dart';
import 'package:sst_cam_app/core/ble/ble_service.dart';
import 'package:sst_cam_app/core/models/device.dart';
import 'package:sst_cam_app/core/models/wifi.dart';
import 'package:sst_cam_app/core/wifi/wifi_handoff.dart';
import 'package:sst_cam_app/core/wifi/wifi_providers.dart';
import 'package:sst_cam_app/core/wifi/wifi_service.dart';
import 'package:sst_cam_app/features/camera/camera_state.dart'
    show activeCameraIdProvider;

const _id = 'cam-1';

class _FakeBle implements BleService {
  final ctrl = StreamController<CameraConnectionState>.broadcast();
  @override
  Stream<CameraConnectionState> connectionStateStream(String deviceId) =>
      ctrl.stream;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeWifi implements WifiService {
  final ctrl = StreamController<WifiDirectState>.broadcast();
  int connectCalls = 0;
  int disconnectCalls = 0;

  @override
  Stream<WifiDirectState> connectionStateStream(String deviceId) => ctrl.stream;

  @override
  Future<WifiDirectGroup> connectGroup(String deviceId) async {
    connectCalls++;
    return const WifiDirectGroup(
      ssid: '',
      psk: '',
      groupOwnerIp: '',
      previewPort: 0,
      downloadPort: 0,
      role: '',
    );
  }

  @override
  Future<void> disconnectGroup(String deviceId) async {
    disconnectCalls++;
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

ProviderContainer _container(_FakeBle ble, _FakeWifi wifi) {
  final c = ProviderContainer(
    overrides: [
      bleServiceProvider.overrideWithValue(ble),
      wifiServiceProvider.overrideWithValue(wifi),
      activeCameraIdProvider.overrideWith((ref) => _id),
    ],
  );
  // Mount the handoff (a lazy Notifier) and keep it alive.
  c.listen(wifiHandoffProvider, (_, _) {});
  return c;
}

// A little past the 400ms debounce.
Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 550));

void main() {
  test('BLE connect brings the WiFi group up exactly once', () async {
    final ble = _FakeBle();
    final wifi = _FakeWifi();
    final container = _container(ble, wifi);
    addTearDown(container.dispose);

    ble.ctrl.add(CameraConnectionState.connected);
    await _settle();

    expect(wifi.connectCalls, 1);
    expect(wifi.disconnectCalls, 0);
  });

  test('a WiFi-only drop while BLE stays connected does NOT reconnect', () async {
    // Lean model: the OS owns rejoining the stable saved network. The app must
    // not re-form the group on wifi-state transitions (the old flap source).
    final ble = _FakeBle();
    final wifi = _FakeWifi();
    final container = _container(ble, wifi);
    addTearDown(container.dispose);

    ble.ctrl.add(CameraConnectionState.connected);
    await _settle();
    expect(wifi.connectCalls, 1);

    // The group reaches connected, then drops on its own (BLE still up). None of
    // these transitions may trigger an app-driven reconnect.
    wifi.ctrl.add(WifiDirectState.connected);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    wifi.ctrl.add(WifiDirectState.failed);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    wifi.ctrl.add(WifiDirectState.idle);
    await _settle();

    expect(
      wifi.connectCalls,
      1,
      reason: 'a WiFi-only drop must NOT re-form the group (lean model)',
    );
  });

  test(
    'BLE disconnect tears the group down; later wifi churn does nothing',
    () async {
      final ble = _FakeBle();
      final wifi = _FakeWifi();
      final container = _container(ble, wifi);
      addTearDown(container.dispose);

      ble.ctrl.add(CameraConnectionState.connected);
      await _settle();
      expect(wifi.connectCalls, 1);

      ble.ctrl.add(CameraConnectionState.disconnected);
      await _settle();
      expect(wifi.disconnectCalls, greaterThanOrEqualTo(1));

      final connectsAfterDrop = wifi.connectCalls;
      wifi.ctrl.add(WifiDirectState.failed);
      await _settle();

      expect(
        wifi.connectCalls,
        connectsAfterDrop,
        reason: 'BLE is down — no reconnect',
      );
    },
  );
}
