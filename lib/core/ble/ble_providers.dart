import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ble_service.dart';
import 'ble_service_impl.dart';
import '../models/command.dart' show DeviceInfoResponse;
import '../models/device.dart';
import '../models/telemetry.dart';
import '../models/match.dart';
import '../models/recording.dart';

// ---------------------------------------------------------------------------
// Service — defaults to BleServiceImpl (real hardware). Dev entry-point
// (main.dart) overrides with MockBleService; tests override via
// bleServiceProvider.overrideWithValue(MockBleService()).
// ---------------------------------------------------------------------------

final bleServiceProvider = Provider<BleService>((ref) {
  final svc = BleServiceImpl();
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

/// The connected camera's real DeviceInfo (firmware version + wire
/// protocol_version). Null until connected — the scan-time SstDevice carries
/// empty firmware/0 protocol. Re-fetches when connection state changes.
final connectedDeviceInfoProvider =
    FutureProvider.family<DeviceInfoResponse?, String>((ref, deviceId) async {
      final state = ref.watch(connectionStateProvider(deviceId)).valueOrNull;
      if (state != CameraConnectionState.connected) return null;
      return ref.read(bleServiceProvider).getDeviceInfo(deviceId);
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
