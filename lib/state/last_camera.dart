// Persists the most recently successfully-connected camera id so the
// Settings empty-state CTA can attempt a one-tap reconnect before falling
// back to a fresh scan in `DiscoveryPage`.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _kLastConnectedDeviceIdKey = 'last_connected_device_id';

/// Persisted id of the most recently successfully-connected camera.
///
/// Null means "never connected" or "preference cleared". Updated by the
/// discovery flow on successful connect; consumed by the Settings empty-
/// state CTA to attempt a one-tap reconnect before falling back to a
/// fresh scan.
class LastCameraIdNotifier extends AsyncNotifier<String?> {
  @override
  Future<String?> build() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kLastConnectedDeviceIdKey);
  }

  /// Persist [deviceId] as the last successfully-connected camera. The
  /// state is updated synchronously after the write so a subsequent read
  /// of [lastConnectedDeviceIdProvider] sees the new value immediately.
  Future<void> set(String deviceId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLastConnectedDeviceIdKey, deviceId);
    state = AsyncData(deviceId);
  }

  /// Clear the persisted last-camera id. Currently unused by app code —
  /// disconnect drops the BLE link but keeps the camera in the known
  /// list so one-tap reconnect still works on the next attempt.
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kLastConnectedDeviceIdKey);
    state = const AsyncData(null);
  }
}

final lastConnectedDeviceIdProvider =
    AsyncNotifierProvider<LastCameraIdNotifier, String?>(
      LastCameraIdNotifier.new,
    );
