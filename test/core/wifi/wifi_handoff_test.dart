// Tests for WifiHandoffController — the single owner of the WiFi Direct group
// lifecycle. Lean recovery model: the controller brings the group up on BLE
// connect and tears it down on MANUAL BLE disconnect / camera change / U6
// reconnect give-up, and does NOTHING in response to wifi-state transitions.
// Rejoining a dropped-but-stable group is the phone OS's job; the app must
// not re-form the group (that reactive loop was the SSID-flap storm).
//
// U6 addition proven here: an UNEXPECTED BLE drop arms the auto-reconnect
// loop, and while it is eligible the group teardown is suppressed — the
// firmware keeps its side up and the app rejoins, never cycles (group
// re-formation kills Argus capture mid-session). Teardown happens only when
// the loop gives up.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sst_cam_app/core/ble/ble_providers.dart';
import 'package:sst_cam_app/core/ble/ble_service.dart';
import 'package:sst_cam_app/core/models/device.dart';
import 'package:sst_cam_app/core/models/wifi.dart';
import 'package:sst_cam_app/core/state/reconnect_controller.dart';
import 'package:sst_cam_app/core/wifi/wifi_handoff.dart';
import 'package:sst_cam_app/core/wifi/wifi_providers.dart';
import 'package:sst_cam_app/core/wifi/wifi_service.dart';
import 'package:sst_cam_app/features/camera/camera_state.dart'
    show activeCameraIdProvider;

const _id = 'cam-1';

class _FakeBle implements BleService {
  final ctrl = StreamController<CameraConnectionState>.broadcast();
  final bt = StreamController<bool>.broadcast();

  @override
  Stream<CameraConnectionState> connectionStateStream(String deviceId) =>
      ctrl.stream;

  @override
  Stream<bool> get bluetoothOn async* {
    yield true;
    yield* bt.stream;
  }

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
      // Keep U6 loop ATTEMPTS out of these tests: the loop still arms on an
      // unexpected drop (that eligibility is what the handoff keys off), but
      // no retry fires inside the test window.
      reconnectBackoffProvider.overrideWithValue(
        const ReconnectBackoff(quickDelay: Duration(minutes: 5)),
      ),
    ],
  );
  // Mount the handoff (a lazy Notifier) and keep it alive. It watches the
  // reconnect controller, which mounts the U6 loop alongside it.
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

  test('MANUAL BLE disconnect (disconnecting → disconnected) tears the group '
      'down; later wifi churn does nothing', () async {
    final ble = _FakeBle();
    final wifi = _FakeWifi();
    final container = _container(ble, wifi);
    addTearDown(container.dispose);

    ble.ctrl.add(CameraConnectionState.connected);
    await _settle();
    expect(wifi.connectCalls, 1);

    // A manual disconnect announces itself: `disconnecting` first (both
    // the real impl and the parity mock do), so the U6 loop never arms
    // and the teardown proceeds.
    ble.ctrl.add(CameraConnectionState.disconnecting);
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
  });

  test('UNEXPECTED BLE drop keeps the group up while the reconnect loop is '
      'eligible; loop give-up finally tears it down', () async {
    final ble = _FakeBle();
    final wifi = _FakeWifi();
    final container = _container(ble, wifi);
    addTearDown(container.dispose);

    ble.ctrl.add(CameraConnectionState.connected);
    await _settle();
    expect(wifi.connectCalls, 1);

    // Bare connected→disconnected edge = unexpected drop → U6 loop arms.
    ble.ctrl.add(CameraConnectionState.disconnected);
    await _settle();
    expect(
      container.read(reconnectControllerProvider).isReconnecting(_id),
      isTrue,
      reason: 'sanity: the loop must be eligible for the suppression',
    );
    expect(
      wifi.disconnectCalls,
      0,
      reason:
          'the firmware keeps its side up — the app must rejoin, not '
          'cycle the group (re-formation kills Argus capture mid-session)',
    );

    // Bluetooth off → loop gives up → the deferred teardown fires.
    ble.bt.add(false);
    await _settle();
    expect(
      container.read(reconnectControllerProvider).phase,
      ReconnectPhase.gaveUp,
    );
    expect(
      wifi.disconnectCalls,
      1,
      reason: 'give-up is the moment the retained group is torn down',
    );
  });
}
