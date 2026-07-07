// Preview controls row — the Preview/Stop button next to the Single|Both
// layout toggle in two equal columns. Shared by the main page's hero card and
// the match session screen (previously two identical copies), so widths and
// right edges line up across both surfaces by construction.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/device_health.dart' show captureBlockedProvider;
import '../theme/tokens.dart';
import '../wifi/wifi_providers.dart' show livePreviewEnabledProvider;
import 'preview_layout_toggle.dart';
import 'wf_button.dart';

class PreviewControlsRow extends ConsumerWidget {
  const PreviewControlsRow({super.key, required this.deviceId});

  final String deviceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final previewOn = ref.watch(livePreviewEnabledProvider(deviceId));
    // U3 health gate: STARTING a preview is blocked while the device is
    // inoperable (or health unknown while connected); stopping stays allowed.
    final captureBlocked = ref.watch(captureBlockedProvider);

    return Row(
      children: [
        Expanded(
          child: WfButton(
            label: previewOn ? 'Stop preview' : 'Preview',
            variant: previewOn
                ? WfButtonVariant.danger
                : WfButtonVariant.outline,
            size: WfButtonSize.sm,
            full: true,
            leading: previewOn
                ? null
                : const Icon(Icons.play_arrow_rounded, size: 13, color: T.ink),
            onPressed: (captureBlocked && !previewOn)
                ? null
                : () {
                    ref
                            .read(livePreviewEnabledProvider(deviceId).notifier)
                            .state =
                        !previewOn;
                  },
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: previewOn
              ? PreviewLayoutToggle(deviceId: deviceId, full: true)
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}
