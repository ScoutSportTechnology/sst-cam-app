import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../ble/ble_providers.dart';
import '../models/preview_layout.dart';
import '../theme/tokens.dart';
import '../wifi/wifi_providers.dart';

final _log = Logger('PreviewLayout');

/// Compact single|side-by-side preview composition toggle (#6 A6b).
///
/// Issues the firmware `set-preview-layout` command and reflects the
/// acknowledged layout in [previewLayoutProvider]. The RTSP URL is unchanged
/// across a switch — only the composited frame geometry changes, which the
/// preview surface picks up from the stream descriptor. Optimistic: flips the
/// provider immediately and reverts if the firmware rejects the switch.
class PreviewLayoutToggle extends ConsumerWidget {
  const PreviewLayoutToggle({
    super.key,
    required this.deviceId,
    this.full = false,
  });

  /// Null when no camera is connected — the toggle renders disabled.
  final String? deviceId;

  /// When true the two segments stretch to fill the available width (each takes
  /// half), so the control lines up edge-to-edge with a sibling button. Default
  /// is compact (intrinsic width), used inline on the main camera card.
  final bool full;

  Future<void> _select(
    BuildContext context,
    WidgetRef ref,
    PreviewLayout target,
  ) async {
    final id = deviceId;
    if (id == null) return;
    final notifier = ref.read(previewLayoutProvider(id).notifier);
    final previous = notifier.state;
    if (previous == target) return;

    _log.fine('preview mode → ${target.name} (user)');
    notifier.state = target; // optimistic
    try {
      await ref.read(bleServiceProvider).setPreviewLayout(id, target);
    } catch (e) {
      _log.warning('preview mode switch rejected by camera', e);
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

    final single = _Segment(
      icon: Icons.crop_portrait_rounded,
      label: 'Single',
      active: selected == PreviewLayout.single,
      onTap: enabled ? () => _select(context, ref, PreviewLayout.single) : null,
    );
    final both = _Segment(
      icon: Icons.splitscreen_rounded,
      label: 'Both',
      active: selected == PreviewLayout.sideBySide,
      onTap: enabled
          ? () => _select(context, ref, PreviewLayout.sideBySide)
          : null,
    );

    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: T.fillSoft,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: T.hair),
        ),
        child: Row(
          mainAxisSize: full ? MainAxisSize.max : MainAxisSize.min,
          children: full
              ? [Expanded(child: single), Expanded(child: both)]
              : [single, both],
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
          mainAxisAlignment: MainAxisAlignment.center,
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
