import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/device.dart';
import '../models/wifi.dart' show WifiDirectState;
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
  CameraConnectionState? _lastBleState;
  WifiDirectState? _lastWifiState;
  Timer? _debounce;

  /// Bounded WiFi-group recovery. The P2P group can drop on its own — the OS
  /// tears it down when the app backgrounds, the screen locks, or the GO cycles
  /// — while BLE stays connected. Because the handoff is otherwise BLE-driven,
  /// such a WiFi-only drop had no recovery path and the live preview stuck on
  /// the placeholder. Re-form the group, but cap attempts so a GO that
  /// genuinely can't form doesn't spin connectGroup forever; the budget resets
  /// once the group is back up.
  int _wifiRecoveryAttempts = 0;
  static const _maxWifiRecoveryAttempts = 3;

  /// How long a connection state must hold before we act on it. Rapid
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
      _lastBleState = null;
      _lastWifiState = null;
      _wifiRecoveryAttempts = 0;
      _debounce?.cancel();
      if (prev != null) {
        unawaited(ref.read(wifiServiceProvider).disconnectGroup(prev));
      }
    }
    if (id == null) return;

    final wifi = ref.read(wifiServiceProvider);
    final bleState = ref.watch(connectionStateProvider(id)).valueOrNull;
    final wifiState = ref.watch(wifiConnectionStateProvider(id)).valueOrNull;

    // BLE-driven group lifecycle (unchanged): bring WiFi up when BLE connects,
    // tear it down when BLE disconnects. A BLE transition supersedes WiFi
    // recovery this build.
    if (bleState != _lastBleState) {
      _lastBleState = bleState;
      _debounce?.cancel();
      switch (bleState) {
        case CameraConnectionState.connected:
          _wifiRecoveryAttempts = 0; // fresh session
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
      return;
    }

    // WiFi-drop recovery: BLE is up but the group fell from connected to a
    // non-running state on its own — re-form it (bounded).
    if (wifiState != _lastWifiState) {
      final wasConnected = _lastWifiState == WifiDirectState.connected;
      _lastWifiState = wifiState;
      if (wifiState == WifiDirectState.connected) {
        _wifiRecoveryAttempts = 0; // recovered — restore the budget
      } else if (bleState == CameraConnectionState.connected &&
          wasConnected &&
          (wifiState == WifiDirectState.failed ||
              wifiState == WifiDirectState.idle ||
              wifiState == WifiDirectState.stopping) &&
          _wifiRecoveryAttempts < _maxWifiRecoveryAttempts) {
        _wifiRecoveryAttempts++;
        _debounce?.cancel();
        _debounce = Timer(
          _debounceDelay,
          () => unawaited(wifi.connectGroup(id)),
        );
      }
    }
  }
}

final wifiHandoffProvider = NotifierProvider<WifiHandoffController, void>(
  WifiHandoffController.new,
);
