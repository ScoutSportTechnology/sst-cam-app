// Device-health notice — the shared surface widget for the U3 health gate.
// Dropped onto every surface that hosts preview/record/stream actions (main
// page, session screen, setup screen) so the presentation can never diverge
// per page; the gating itself keys off [captureBlockedProvider].
//
// Renders by [deviceHealthProvider] state, only while connected:
//   inoperable → persistent "Device inoperable" banner (dismiss-proof: purely
//                state-driven, no close affordance) + a Diagnostics pointer.
//                Downloads/WiFi stay reachable — the banner says so.
//   unknown    → soft "waiting for camera health" note (conservative lockout
//                while readings are stale — see captureBlockedProvider).
//   recovering → soft "camera recovering…" note; nothing is locked.
//   ok         → nothing.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ble/ble_providers.dart' show connectionStateProvider;
import '../models/device.dart';
import '../state/device_health.dart';
import '../theme/tokens.dart';
import '../../features/camera/camera_state.dart' show activeCameraIdProvider;
// core→feature import, same precedent as core/state/connect_controller.dart:
// the diagnostics pointer must open the one real diagnostics page.
import '../../features/discovery/diagnostics_page.dart' show DiagnosticsPage;
import 'wf_button.dart';

class DeviceHealthNotice extends ConsumerWidget {
  const DeviceHealthNotice({super.key, this.margin});

  /// Outer margin — defaults to the standard 14 px page inset.
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final camId = ref.watch(activeCameraIdProvider);
    if (camId == null) return const SizedBox.shrink();
    final connected =
        ref.watch(connectionStateProvider(camId)).valueOrNull ==
        CameraConnectionState.connected;
    // Disconnected is a normal state with its own affordances — no notice.
    if (!connected) return const SizedBox.shrink();

    return switch (ref.watch(deviceHealthProvider).device) {
      DeviceHealth.ok => const SizedBox.shrink(),
      DeviceHealth.recovering => _softNote(
        'Camera recovering — capture may stutter briefly.',
      ),
      DeviceHealth.unknown => _softNote(
        'Camera health unknown — waiting for the camera. '
        'Capture is paused until it reports back.',
      ),
      DeviceHealth.inoperable => _inoperableBanner(context, camId),
    };
  }

  Widget _softNote(String text) {
    return Container(
      width: double.infinity,
      margin: margin ?? const EdgeInsets.fromLTRB(14, 8, 14, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: T.fillSoft,
        border: Border.all(color: T.rule, width: 1),
      ),
      child: Row(
        children: [
          const Icon(Icons.autorenew, size: 14, color: T.warn),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: T.ink2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _inoperableBanner(BuildContext context, String deviceId) {
    return Container(
      width: double.infinity,
      margin: margin ?? const EdgeInsets.fromLTRB(14, 8, 14, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: T.dangerSoft,
        border: Border.all(color: T.danger, width: 1),
      ),
      child: Row(
        children: [
          const Icon(Icons.videocam_off, size: 20, color: T.danger),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Device inoperable',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: T.ink,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'A camera is down. Preview, recording and streaming are '
                  'unavailable — downloads still work.',
                  style: TextStyle(fontSize: 11, color: T.ink2, height: 1.35),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          WfButton(
            label: 'Diagnostics',
            size: WfButtonSize.sm,
            variant: WfButtonVariant.outline,
            onPressed: () {
              Navigator.of(context, rootNavigator: true).push(
                MaterialPageRoute<void>(
                  builder: (_) => DiagnosticsPage(deviceId: deviceId),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
