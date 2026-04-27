import 'package:flutter/material.dart';

/// Minimal enums local to the component (you can move them to core/enums later).
enum LinkState { disconnected, connected }

enum Activity { standby, recording, streaming }

class StatusBar extends StatelessWidget {
  const StatusBar({
    super.key,
    required this.expanded,
    required this.onToggle,
    required this.linkState,
    required this.activity,
    required this.cameraName,
    required this.batteryPercent,
    required this.onConnectPressed,
  });

  final bool expanded;
  final VoidCallback onToggle;
  final LinkState linkState;
  final Activity activity;
  final String? cameraName;
  final int batteryPercent;
  final VoidCallback onConnectPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final title = cameraName ?? 'No camera';
    final statusColor = _statusColor(linkState, activity, scheme);
    final activityLabel = _activityLabel(linkState, activity);

    return Material(
      color: scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Collapsed row
              Row(
                children: [
                  _IndicatorDot(color: statusColor),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: theme.textTheme.titleMedium),
                        const SizedBox(height: 2),
                        Text(
                          activityLabel,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _BatteryBadge(percent: batteryPercent),
                  const SizedBox(width: 8),
                  AnimatedRotation(
                    turns: expanded ? 0.5 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.expand_more,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),

              // Expanded content
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                child: expanded
                    ? Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Row(
                          children: [
                            FilledButton.tonalIcon(
                              onPressed: onConnectPressed,
                              icon: Icon(
                                linkState == LinkState.connected
                                    ? Icons.link_off
                                    : Icons.link,
                              ),
                              label: Text(
                                linkState == LinkState.connected
                                    ? 'Disconnect'
                                    : 'Connect',
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Quick actions when expanded.',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _statusColor(LinkState link, Activity act, ColorScheme scheme) {
    if (link == LinkState.disconnected) return scheme.outline;
    switch (act) {
      case Activity.recording:
        return Colors.red;
      case Activity.streaming:
        return Colors.blue;
      case Activity.standby:
        return Colors.green;
    }
  }

  String _activityLabel(LinkState link, Activity act) {
    if (link == LinkState.disconnected) return 'Not connected';
    switch (act) {
      case Activity.recording:
        return 'Recording';
      case Activity.streaming:
        return 'Streaming';
      case Activity.standby:
        return 'Standby';
    }
  }
}

class _IndicatorDot extends StatelessWidget {
  const _IndicatorDot({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.6),
            blurRadius: 6,
            spreadRadius: 1,
          ),
        ],
      ),
    );
  }
}

class _BatteryBadge extends StatelessWidget {
  const _BatteryBadge({required this.percent});
  final int percent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_icon(percent), size: 18, color: scheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Text('$percent%', style: TextStyle(color: scheme.onSurface)),
        ],
      ),
    );
  }

  IconData _icon(int p) {
    if (p >= 90) return Icons.battery_full;
    if (p >= 60) return Icons.battery_6_bar;
    if (p >= 40) return Icons.battery_4_bar;
    if (p >= 20) return Icons.battery_2_bar;
    if (p > 0) return Icons.battery_1_bar;
    return Icons.battery_alert;
  }
}
