// Tests for WifiHandoffController — the single owner of the WiFi Direct group
// lifecycle. Regression focus: a WiFi-only group drop (BLE still connected)
// must auto-reconnect, because the OS can tear down the P2P group on its own
// (backgrounding / screen lock / GO cycling) and the preview otherwise sticks
// on the placeholder forever.
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
  test('a WiFi-only group drop reconnects while BLE stays connected', () async {
    final ble = _FakeBle();
    final wifi = _FakeWifi();
    final container = _container(ble, wifi);
    addTearDown(container.dispose);

    // BLE connects → the group is brought up.
    ble.ctrl.add(CameraConnectionState.connected);
    await _settle();
    expect(wifi.connectCalls, 1);

    // The group reaches connected, then drops on its own (BLE still up).
    wifi.ctrl.add(WifiDirectState.connected);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    wifi.ctrl.add(WifiDirectState.failed);
    await _settle();

    expect(
      wifi.connectCalls,
      2,
      reason: 'a WiFi-only drop must trigger an automatic reconnect',
    );
  });

  test('a failed INITIAL connect is not treated as a drop-recovery', () async {
    final ble = _FakeBle();
    final wifi = _FakeWifi();
    final container = _container(ble, wifi);
    addTearDown(container.dispose);

    ble.ctrl.add(CameraConnectionState.connected);
    await _settle();
    expect(wifi.connectCalls, 1);

    // Never reached connected — idle → starting → failed. The recovery only
    // fires on a drop FROM connected, so no extra connectGroup here.
    wifi.ctrl.add(WifiDirectState.idle);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    wifi.ctrl.add(WifiDirectState.starting);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    wifi.ctrl.add(WifiDirectState.failed);
    await _settle();

    expect(wifi.connectCalls, 1, reason: 'no recovery without a prior connect');
  });

  test('no WiFi recovery once BLE has disconnected', () async {
    final ble = _FakeBle();
    final wifi = _FakeWifi();
    final container = _container(ble, wifi);
    addTearDown(container.dispose);

    ble.ctrl.add(CameraConnectionState.connected);
    await _settle();
    wifi.ctrl.add(WifiDirectState.connected);
    await Future<void>.delayed(const Duration(milliseconds: 30));

    // BLE drops → the handoff tears the group down; a subsequent WiFi-state
    // change must not re-form a group for a camera that's no longer connected.
    ble.ctrl.add(CameraConnectionState.disconnected);
    await _settle();
    final afterBleDrop = wifi.connectCalls;

    wifi.ctrl.add(WifiDirectState.failed);
    await _settle();

    expect(
      wifi.connectCalls,
      afterBleDrop,
      reason: 'BLE is down — no reconnect',
    );
    expect(wifi.disconnectCalls, greaterThanOrEqualTo(1));
  });
}
