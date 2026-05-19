import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ble/ble_service.dart';
import '../ble/ble_service_impl.dart';
import '../ble/mock_ble_service.dart';
import '../env.dart';
import '../models/device.dart';
import '../models/telemetry.dart';
import '../models/match.dart';
import '../models/recording.dart';

// ---------------------------------------------------------------------------
// Service — backend chosen by `kAppEnv` (see lib/env.dart). Tests still
// override via `bleServiceProvider.overrideWithValue(MockBleService())`.
// ---------------------------------------------------------------------------

final bleServiceProvider = Provider<BleService>((ref) {
  final BleService svc = kAppEnv.isDevBackend
      ? MockBleService(failureRate: 0)
      : BleServiceImpl();
  ref.onDispose(svc.dispose);
  return svc;
});

// ---------------------------------------------------------------------------
// Discovery
// ---------------------------------------------------------------------------

final discoveredDevicesProvider = StreamProvider<List<SstDevice>>((ref) {
  return ref.watch(bleServiceProvider).discoveredDevices;
});

// ---------------------------------------------------------------------------
// Per-device (family = one provider instance per deviceId)
// ---------------------------------------------------------------------------

final connectionStateProvider =
    StreamProvider.family<CameraConnectionState, String>((ref, deviceId) {
      return ref.watch(bleServiceProvider).connectionStateStream(deviceId);
    });

final telemetryProvider = StreamProvider.family<DeviceTelemetry, String>((
  ref,
  deviceId,
) {
  return ref.watch(bleServiceProvider).telemetryStream(deviceId);
});

final matchStateProvider = StreamProvider.family<MatchState, String>((
  ref,
  deviceId,
) {
  return ref.watch(bleServiceProvider).matchStateStream(deviceId);
});

final recordingsProvider =
    FutureProvider.family<List<RecordingMetadata>, String>((ref, deviceId) {
      return ref.watch(bleServiceProvider).listRecordings(deviceId);
    });
