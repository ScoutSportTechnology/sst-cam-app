// Derived per-camera device health — the ONE gate every capture surface keys
// off (U3, state-health cycle). Folds the connect handshake's session-snapshot
// health with the live 1 Hz telemetry health (newest source wins) into a
// device-level status:
//
//   any camera DOWN        → inoperable   preview / recording-start /
//                                         streaming-start disabled + the
//                                         persistent inoperable banner;
//                                         downloads, WiFi and diagnostics stay
//                                         reachable (the gate never touches
//                                         those paths)
//   any camera RECOVERING  → recovering   soft inline indicator only — actions
//                                         stay enabled (the firmware refuses
//                                         starts with DEVICE_INOPERABLE as the
//                                         backstop), so OK↔RECOVERING flapping
//                                         never flashes the banner
//   nothing reported       → unknown      render "—", never fabricate OK
//   otherwise              → ok
//
// Freshness: a health reading is only trusted for [healthFreshnessWindow]
// (a few missed 1 Hz telemetry polls). If readings stall while connected the
// state degrades to unknown — a stale OK must never hold the gate open — and
// [captureBlockedProvider] treats unknown-while-connected conservatively
// (starts disabled) until a fresh reading arrives. While disconnected the
// health is unknown and the gate is a no-op: the existing connection gates
// own that case.
//
// The gate holds in dev/mock mode too (docs/solutions/conventions/
// isdevbackend-must-not-bypass-connection-state-guards-2026-05-19.md): it is
// derived purely from the BleService port streams, which the mock implements
// with the same semantics.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ble/ble_providers.dart';
import '../models/device.dart';
import '../models/telemetry.dart';
import 'camera_selection.dart' show activeCameraIdProvider;
import 'connect_controller.dart' show sessionSnapshotProvider;

/// How long a health reading stays trusted (≈5 missed 1 Hz telemetry polls).
/// A provider (not a const) so tests can override it to a short window.
final healthFreshnessWindowProvider = Provider<Duration>(
  (_) => const Duration(seconds: 5),
);

/// Device-level health folded from the per-camera values.
enum DeviceHealth { unknown, ok, recovering, inoperable }

/// Latest known per-camera health. U4's diagnostics tiles consume the
/// per-camera values; the gate + banner consume the folded [device] level.
class DeviceHealthState {
  const DeviceHealthState({required this.camera0, required this.camera1});

  /// No health reported by any source (disconnected, stale, or absent fields).
  static const unreported = DeviceHealthState(
    camera0: CameraHealth.unknown,
    camera1: CameraHealth.unknown,
  );

  final CameraHealth camera0;
  final CameraHealth camera1;

  DeviceHealth get device {
    if (camera0 == CameraHealth.down || camera1 == CameraHealth.down) {
      return DeviceHealth.inoperable;
    }
    if (camera0 == CameraHealth.recovering ||
        camera1 == CameraHealth.recovering) {
      return DeviceHealth.recovering;
    }
    if (camera0 == CameraHealth.unknown && camera1 == CameraHealth.unknown) {
      return DeviceHealth.unknown;
    }
    return DeviceHealth.ok;
  }

  @override
  bool operator ==(Object other) =>
      other is DeviceHealthState &&
      other.camera0 == camera0 &&
      other.camera1 == camera1;

  @override
  int get hashCode => Object.hash(camera0, camera1);
}

class DeviceHealthController extends Notifier<DeviceHealthState> {
  Timer? _staleTimer;

  @override
  DeviceHealthState build() {
    // Rebuild (camera change, connection transition, new snapshot) and
    // dispose both cancel the previous window — onDispose runs on each.
    ref.onDispose(() {
      _staleTimer?.cancel();
      _staleTimer = null;
    });

    final camId = ref.watch(activeCameraIdProvider);
    if (camId == null) return DeviceHealthState.unreported;

    final connected =
        ref.watch(connectionStateProvider(camId)).valueOrNull ==
        CameraConnectionState.connected;
    // Disconnected → unknown, never a stale OK (readings from a previous link
    // don't survive; U4 tiles render "—").
    if (!connected) return DeviceHealthState.unreported;

    // Live refresh: the 1 Hz telemetry poll postdates the handshake snapshot,
    // so a health-bearing sample always wins (newest source wins).
    ref.listen(telemetryProvider(camId), (_, next) {
      final t = next.valueOrNull;
      if (t == null) return;
      if (t.camera0Health == null && t.camera1Health == null) {
        // Health-less sample: NOT a reading — it neither updates the values
        // nor refreshes the freshness clock (absent must never fabricate OK,
        // and must not silently keep an old reading "fresh" either... the old
        // reading simply ages out through the unrefreshed window).
        return;
      }
      _armStaleTimer();
      state = DeviceHealthState(
        camera0: t.camera0Health ?? CameraHealth.unknown,
        camera1: t.camera1Health ?? CameraHealth.unknown,
      );
    });

    // Baseline: the session snapshot read by this connect's handshake.
    final snap = ref.watch(sessionSnapshotProvider);
    final c0 = snap?.camera0Health;
    final c1 = snap?.camera1Health;
    if (c0 == null && c1 == null) return DeviceHealthState.unreported;
    _armStaleTimer();
    return DeviceHealthState(
      camera0: c0 ?? CameraHealth.unknown,
      camera1: c1 ?? CameraHealth.unknown,
    );
  }

  void _armStaleTimer() {
    _staleTimer?.cancel();
    _staleTimer = Timer(ref.read(healthFreshnessWindowProvider), () {
      // No successful health reading for the whole window while connected:
      // the last value is stale — degrade to unknown so a stale OK cannot
      // hold the gate open forever (nor a stale DOWN hold it shut).
      state = DeviceHealthState.unreported;
    });
  }
}

/// The latest known per-camera health for the active camera, freshness-bound.
/// Consumers: [captureBlockedProvider], the inoperable banner / recovering
/// indicator ([DeviceHealthNotice]), and U4's diagnostics tiles.
final deviceHealthProvider =
    NotifierProvider<DeviceHealthController, DeviceHealthState>(
      DeviceHealthController.new,
    );

/// True while capture-start actions — live preview, recording start,
/// streaming start — must be disabled: the device is [DeviceHealth.inoperable]
/// or its health is [DeviceHealth.unknown] *while connected* (no fresh reading
/// — treated conservatively until one arrives). RECOVERING does NOT block
/// (soft indicator only; the firmware's DEVICE_INOPERABLE refusal is the
/// backstop). False while disconnected — the existing connection gates own
/// that case. Downloads, WiFi and diagnostics never consult this provider.
final captureBlockedProvider = Provider<bool>((ref) {
  final camId = ref.watch(activeCameraIdProvider);
  if (camId == null) return false;
  final connected =
      ref.watch(connectionStateProvider(camId)).valueOrNull ==
      CameraConnectionState.connected;
  if (!connected) return false;
  final device = ref.watch(deviceHealthProvider).device;
  return device == DeviceHealth.inoperable || device == DeviceHealth.unknown;
});
