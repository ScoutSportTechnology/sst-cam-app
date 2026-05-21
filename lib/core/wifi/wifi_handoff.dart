import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/device.dart';
import '../../state/app_data.dart';
import '../ble/ble_providers.dart';
import 'wifi_providers.dart';

/// Single owner of the WiFi Direct group lifecycle. Watches the active BLE
/// camera and its connection state; brings the WiFi group up automatically
/// when BLE connects, tears it down on disconnect or camera change.
///
/// The handoff is intentionally one-way (BLE first, then WiFi) and uses the
/// credentials returned by the firmware over BLE — see
/// `WifiDirectGroupResponse` in proto/wifi.proto. There is no hardcoded
/// fallback.
///
/// This Notifier exposes no state to the UI; it only runs side effects.
/// Mount it once at the root of the widget tree (see lib/app.dart) so it
/// stays alive for the app's lifetime — Notifiers are lazy and won't run
/// without a reader.
class WifiHandoffController extends Notifier<void> {
  String? _activeId;
  CameraConnectionState? _lastState;

  @override
  void build() {
    final id = ref.watch(activeCameraIdProvider);

    if (id != _activeId) {
      final prev = _activeId;
      _activeId = id;
      _lastState = null;
      if (prev != null) {
        unawaited(ref.read(wifiServiceProvider).disconnectGroup(prev));
      }
    }
    if (id == null) return;

    final state = ref.watch(connectionStateProvider(id)).valueOrNull;
    if (state == _lastState) return;
    _lastState = state;

    final wifi = ref.read(wifiServiceProvider);
    switch (state) {
      case CameraConnectionState.connected:
        unawaited(wifi.connectGroup(id));
      case CameraConnectionState.disconnected:
        unawaited(wifi.disconnectGroup(id));
      default:
        break;
    }
  }
}

final wifiHandoffProvider = NotifierProvider<WifiHandoffController, void>(
  WifiHandoffController.new,
);
