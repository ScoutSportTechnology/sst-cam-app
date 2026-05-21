import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../env.dart';
import '../core/models/wifi.dart';
import '../mock/mock_wifi_service.dart';
import '../core/wifi/wifi_service.dart';
import '../core/wifi/wifi_service_impl.dart';

// ---------------------------------------------------------------------------
// Service — backend chosen by `kAppEnv` (see lib/env.dart). Tests override
// via `wifiServiceProvider.overrideWithValue(MockWifiService())`.
// ---------------------------------------------------------------------------

final wifiServiceProvider = Provider<WifiService>((ref) {
  final WifiService svc = kAppEnv.isDevBackend
      ? MockWifiService()
      : WifiServiceImpl();
  ref.onDispose(svc.dispose);
  return svc;
});

// ---------------------------------------------------------------------------
// Per-device (family = one provider instance per deviceId)
// ---------------------------------------------------------------------------

/// Live WiFi Direct state — independent of the BLE connection state.
final wifiConnectionStateProvider =
    StreamProvider.family<WifiDirectState, String>((ref, deviceId) {
      return ref.watch(wifiServiceProvider).connectionStateStream(deviceId);
    });

/// Live preview frames at the codec's native rate (typically 15 fps).
/// Subscribers should debounce / drop frames on the UI side if they cannot
/// keep up rather than blocking the producer.
final previewFrameProvider = StreamProvider.family<PreviewFrame, String>((
  ref,
  deviceId,
) {
  return ref.watch(wifiServiceProvider).previewFrames(deviceId);
});

/// Rolling preview stats — fps / kbps / latency. Updated ~1 Hz.
final previewStatsProvider = StreamProvider.family<PreviewStats, String>((
  ref,
  deviceId,
) {
  return ref.watch(wifiServiceProvider).previewStats(deviceId);
});

/// Current preview stream descriptor for [deviceId], or null when the WiFi
/// Direct group isn't up. Re-evaluates whenever the WiFi connection state
/// changes (descriptor lives behind the same group lifecycle).
final previewDescriptorProvider =
    Provider.family<PreviewStreamDescriptor?, String>((ref, deviceId) {
      ref.watch(wifiConnectionStateProvider(deviceId));
      return ref.watch(wifiServiceProvider).previewDescriptor(deviceId);
    });

/// Cross-cutting feed of every download's progress events. UI surfaces that
/// need a "downloads in flight" badge can listen here without needing the
/// individual handle returned by `startDownload`.
final allDownloadsProgressProvider = StreamProvider<VideoDownloadProgress>((
  ref,
) {
  return ref.watch(wifiServiceProvider).allDownloadProgress();
});
