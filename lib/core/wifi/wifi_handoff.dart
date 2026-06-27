import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/device.dart';
import '../../features/camera/camera_state.dart' show activeCameraIdProvider;
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
  Timer? _debounce;

  /// How long the BLE connection state must hold before we act on it. Rapid
  /// connect/disconnect flaps would otherwise churn the WiFi group
  /// (connect→disconnect→connect), widening the firmware P2P join race and
  /// surfacing as intermittent "wifi failed". Collapsing flaps to the final
  /// stable state removes that churn.
  static const _debounceDelay = Duration(milliseconds: 400);

  @override
  void build() {
    ref.onDispose(() => _debounce?.cancel());

    final id = ref.watch(activeCameraIdProvider);

    if (id != _activeId) {
      final prev = _activeId;
      _activeId = id;
      _lastState = null;
      _debounce?.cancel();
      if (prev != null) {
        unawaited(ref.read(wifiServiceProvider).disconnectGroup(prev));
      }
    }
    if (id == null) return;

    final state = ref.watch(connectionStateProvider(id)).valueOrNull;
    if (state == _lastState) return;
    _lastState = state;

    // Supersede any pending action with the latest state, then act after the
    // state has settled.
    _debounce?.cancel();
    final wifi = ref.read(wifiServiceProvider);
    switch (state) {
      case CameraConnectionState.connected:
        _debounce = Timer(
          _debounceDelay,
          () => unawaited(wifi.connectGroup(id)),
        );
      case CameraConnectionState.disconnected:
        _debounce = Timer(
          _debounceDelay,
          () => unawaited(wifi.disconnectGroup(id)),
        );
      default:
        break;
    }
  }
}

final wifiHandoffProvider = NotifierProvider<WifiHandoffController, void>(
  WifiHandoffController.new,
);
