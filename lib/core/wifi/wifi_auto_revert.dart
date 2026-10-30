import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/camera/camera_state.dart' show activeCameraIdProvider;
import '../ble/ble_providers.dart';
import 'wifi_providers.dart';

/// How long a phone-Wi-Fi loss must persist before the auto-revert fires, so a
/// brief flap that recovers yields zero reverts. Longer than the handoff debounce
/// — a WiFi transition is noisier than a BLE one. Overridable in tests.
final wifiAutoRevertDebounceProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 3),
);

/// Shared-WiFi (S2) auto-revert (U5 / R4). Observes the PHONE's Wi-Fi via
/// [wifiAvailableProvider]; when the phone drops the shared network AND the camera
/// is confirmed in S2, it sends ONE `SetNetworkConfig{wifi.enabled=false}` so the
/// firmware arbiter reverts to the direct WiFi-Direct (P2P) link and live preview
/// keeps working. S2 is confirmed at the moment of action from the camera's
/// GetNetworkConfig reply — no shared page state to keep in sync.
///
/// **Lean model, preserved.** This sends exactly one revert on a SETTLED loss —
/// never a reconnect loop, never a group re-form (that was the SSID-flap storm).
/// A down→up flap that recovers before the debounce expires sends nothing: the
/// settled state is re-sampled at expiry. If BLE is also down the revert simply
/// fails; the firmware's S2 carrier-loss watchdog (D2a) is the backstop for that
/// both-links-down case.
///
/// Exposes no UI state — mount it once at the app root (see lib/app.dart) so it
/// stays alive for the app's lifetime.
class WifiAutoRevertController extends Notifier<void> {
  Timer? _debounce;
  bool _reverting = false;

  @override
  void build() {
    ref.onDispose(() => _debounce?.cancel());

    final id = ref.watch(activeCameraIdProvider);
    if (id == null) {
      _debounce?.cancel();
      return;
    }
    final lossDebounce = ref.watch(wifiAutoRevertDebounceProvider);

    // React to phone-Wi-Fi transitions WITHOUT rebuilding on every event.
    ref.listen<AsyncValue<bool>>(wifiAvailableProvider, (previous, next) {
      final available = next.valueOrNull ?? true;
      if (available) {
        // Available (or a flap that came back) → cancel any pending revert.
        _debounce?.cancel();
        return;
      }
      // Wi-Fi lost — start the settled-loss debounce. Whether the camera is
      // actually in S2 (and so whether to revert) is confirmed at expiry.
      _debounce?.cancel();
      _debounce = Timer(lossDebounce, () => unawaited(_maybeRevert(id)));
    });
  }

  /// At debounce expiry, SAMPLE the settled state: revert once iff the phone is
  /// still off Wi-Fi AND the camera confirms it is in S2. A flap that recovered
  /// already cancelled the timer, so this only runs on a genuine settled loss.
  Future<void> _maybeRevert(String id) async {
    if (_reverting) return;
    final available = ref.read(wifiAvailableProvider).valueOrNull ?? true;
    if (available) return; // recovered by expiry → nothing to do

    _reverting = true;
    try {
      final ble = ref.read(bleServiceProvider);
      // Confirm S2 from the camera itself (not stale app state). This Get also
      // gives us the current uplink so the full-replace SetNetworkConfig can
      // preserve Ethernet and only disable WiFi -> the arbiter reverts to P2P.
      final current = await ble.getNetworkConfig(id);
      if (!current.inSharedWifi) return; // not in S2 → nothing to revert
      await ble.setNetworkConfig(
        id,
        current.config.copyWith(
          wifi: current.config.wifi.copyWith(enabled: false),
        ),
      );
      debugPrint(
        '[wifi-auto-revert] phone left shared Wi-Fi → reverted camera to P2P',
      );
    } catch (e) {
      // BLE likely also down — the firmware S2 carrier watchdog (D2a) recovers.
      debugPrint('[wifi-auto-revert] revert failed (BLE down?): $e');
    } finally {
      _reverting = false;
    }
  }
}

final wifiAutoRevertProvider = NotifierProvider<WifiAutoRevertController, void>(
  WifiAutoRevertController.new,
);
