// Keeps the app's session-scoped camera selections in sync with the firmware.
//
// The firmware clears its session-scoped selections — active output camera → 0,
// preview layout → single — on every BLE disconnect, so a fresh connection
// always starts at Left / single-view. The app's selection providers, by
// contrast, live for the whole app process: after picking Right, dropping BLE,
// and reconnecting, the UI keeps showing Right while the firmware serves camera
// 0 — a mismatch the user can only clear by toggling (or by killing and
// reopening the app, which is the tell that the providers never reset).
//
// Reset at the (re)connect call site. This is deterministic — it runs whenever
// the app establishes a connection — and does NOT depend on a `disconnected`
// event reaching the app: the real BLE connection-state stream does not
// reliably surface a reconnect through the cached per-device StreamProvider, so
// a disconnect-edge listener silently misses the reconnect on device.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/preview_layout.dart';
import '../wifi/wifi_providers.dart' show previewLayoutProvider;
import '../../features/camera/camera_state.dart'
    show activeOutputCameraProvider;

/// Reset the output-camera and preview-layout selections to the firmware's
/// fresh-session defaults (camera 0 / single view). Call right after a
/// successful `connect()` so the UI matches the firmware, which resets the same
/// state on its side of every disconnect.
void resetSelectionOnConnect(WidgetRef ref, String deviceId) {
  ref.read(activeOutputCameraProvider.notifier).state = 0;
  ref.read(previewLayoutProvider(deviceId).notifier).state =
      PreviewLayout.single;
}
