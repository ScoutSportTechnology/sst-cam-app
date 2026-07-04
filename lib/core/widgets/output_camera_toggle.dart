import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../features/camera/camera_state.dart'
    show activeOutputCameraProvider;
import '../ble/ble_providers.dart';
import '../services/log_service.dart';
import '../theme/tokens.dart';

final _log = Logger('OutputCamera');

/// Manual tracking — pick which physical camera (Cam 1 / Cam 2) feeds the
/// record / stream / single-preview output. Sent live to the firmware
/// (ManualDecision); the single preview switches to the chosen camera, so this
/// lives next to the live preview (hero card + live match). Optimistic: flips
/// [activeOutputCameraProvider] immediately and reverts if the firmware rejects.
class OutputCameraToggle extends ConsumerWidget {
  const OutputCameraToggle({
    super.key,
    required this.deviceId,
    this.full = false,
  });

  /// Null when no camera is connected — the toggle renders disabled.
  final String? deviceId;

  /// When true the two segments stretch to fill the available width.
  final bool full;

  Future<void> _select(BuildContext context, WidgetRef ref, int index) async {
    final id = deviceId;
    if (id == null) return;
    final notifier = ref.read(activeOutputCameraProvider.notifier);
    final previous = notifier.state;
    if (previous == index) return;

    _log.debug(
      'output camera → cam$index (${index == 0 ? 'Left' : 'Right'}) (user)',
    );
    notifier.state = index; // optimistic
    try {
      await ref.read(bleServiceProvider).setActiveCamera(id, index);
    } catch (e) {
      _log.warn('output camera switch failed', e);
      notifier.state = previous; // revert on failure
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Camera switch failed')));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(activeOutputCameraProvider);
    final enabled = deviceId != null;

    final cam1 = _Segment(
      icon: Icons.chevron_left_rounded,
      label: 'Left',
      active: selected == 0,
      onTap: enabled ? () => _select(context, ref, 0) : null,
    );
    final cam2 = _Segment(
      icon: Icons.chevron_right_rounded,
      label: 'Right',
      active: selected == 1,
      onTap: enabled ? () => _select(context, ref, 1) : null,
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
              ? [Expanded(child: cam1), Expanded(child: cam2)]
              : [cam1, cam2],
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
