import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ble/ble_providers.dart';
import '../models/preview_layout.dart';
import '../theme/tokens.dart';
import '../wifi/wifi_providers.dart';

/// Compact single|side-by-side preview composition toggle (#6 A6b).
///
/// Issues the firmware `set-preview-layout` command and reflects the
/// acknowledged layout in [previewLayoutProvider]. The RTSP URL is unchanged
/// across a switch — only the composited frame geometry changes, which the
/// preview surface picks up from the stream descriptor. Optimistic: flips the
/// provider immediately and reverts if the firmware rejects the switch.
class PreviewLayoutToggle extends ConsumerWidget {
  const PreviewLayoutToggle({super.key, required this.deviceId});

  /// Null when no camera is connected — the toggle renders disabled.
  final String? deviceId;

  Future<void> _select(
    BuildContext context,
    WidgetRef ref,
    PreviewLayout target,
  ) async {
    final id = deviceId;
    if (id == null) return;
    final notifier = ref.read(previewLayoutProvider(deviceId).notifier);
    final previous = notifier.state;
    if (previous == target) return;

    notifier.state = target; // optimistic
    try {
      await ref.read(bleServiceProvider).setPreviewLayout(id, target);
    } catch (_) {
      notifier.state = previous; // revert on failure
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Camera rejected the preview switch')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(previewLayoutProvider(deviceId));
    final enabled = deviceId != null;

    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: T.fillSoft,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: T.hair),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Segment(
              icon: Icons.crop_portrait_rounded,
              label: 'Single',
              active: selected == PreviewLayout.single,
              onTap: enabled
                  ? () => _select(context, ref, PreviewLayout.single)
                  : null,
            ),
            _Segment(
              icon: Icons.splitscreen_rounded,
              label: 'Both',
              active: selected == PreviewLayout.sideBySide,
              onTap: enabled
                  ? () => _select(context, ref, PreviewLayout.sideBySide)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: T.fast,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: active ? T.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: active ? T.accentInk : T.ink2),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
                color: active ? T.accentInk : T.ink2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
