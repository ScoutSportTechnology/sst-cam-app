import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/dev_navigation.dart';
import '../../core/models/device.dart';
import '../camera/camera_state.dart' show activeCameraIdProvider;
import 'streaming/streaming_state.dart'
    show streamingDestinationsControllerProvider;
import 'users/users_state.dart'
    show activeUserProvider, usersControllerProvider;
import '../../core/state/auto_stop.dart' show autoStopMinutesProvider;
import '../../core/ble/ble_providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/version/version_info.dart';
import '../../core/widgets/wf_card.dart';
import 'camera_card.dart';
import 'connect_camera_banner.dart';
import 'data/data_settings_page.dart';
import '../discovery/diagnostics_page.dart';
import 'sport_presets/sport_presets_page.dart';
import 'calibration/calibration_page.dart';
import 'network/network_settings_page.dart';
import 'streaming/streaming_destinations_page.dart';
import 'users/users_settings_page.dart';

/// Settings page. Always shows a single Scaffold.
///
/// When no camera is connected the body shows a slim [ConnectCameraBanner]
/// in place of the camera-gated sections. The Data (Backup & Restore) section
/// is always visible at the bottom, regardless of camera connection state.
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeId = ref.watch(activeCameraIdProvider);
    final connected =
        activeId != null &&
        ref.watch(connectionStateProvider(activeId)).valueOrNull ==
            CameraConnectionState.connected;

    return Scaffold(
      backgroundColor: T.bg,
      appBar: AppBar(
        title: const Text('Settings'),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 8),
            child: Icon(Icons.more_vert),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
        children: [
          // Camera card / connect banner
          if (connected)
            SettingsCameraCard(deviceId: activeId)
          else
            const ConnectCameraBanner(),
          const SizedBox(height: 16),
          // Grouped nav rows — single card, no per-section headers
          WfCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                Builder(
                  builder: (ctx) {
                    final activeUserId = ref.watch(activeUserProvider);
                    final usersAsync = ref.watch(usersControllerProvider);
                    final activeName = usersAsync.valueOrNull
                        ?.where((u) => u.id == activeUserId)
                        .firstOrNull
                        ?.name;
                    return _NavRow(
                      leading: const Icon(Icons.person_outline),
                      label: 'Users',
                      sub: 'Manage operator profiles',
                      badge: activeName,
                      onTap: () => Navigator.of(ctx).push(
                        MaterialPageRoute(
                          builder: (_) => const UsersSettingsPage(),
                        ),
                      ),
                    );
                  },
                ),
                const Divider(height: 1, color: T.rule),
                _NavRow(
                  leading: const Icon(Icons.sports_soccer_outlined),
                  label: 'Sport setups',
                  sub: 'Saved time configs per sport',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SportPresetsPage()),
                  ),
                ),
                const Divider(height: 1, color: T.rule),
                const _StreamingRow(),
                const Divider(height: 1, color: T.rule),
                _NavRow(
                  leading: const Icon(Icons.lan_outlined),
                  label: 'Network',
                  sub: 'Camera internet uplink (ethernet / wifi)',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const NetworkSettingsPage(),
                    ),
                  ),
                ),
                const Divider(height: 1, color: T.rule),
                _NavRow(
                  leading: const Icon(Icons.tune_rounded),
                  label: 'Calibration',
                  sub: 'Camera colour, focus + output tracking',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const CalibrationPage()),
                  ),
                ),
                const Divider(height: 1, color: T.rule),
                const _AutoStopRow(),
                const Divider(height: 1, color: T.rule),
                _NavRow(
                  leading: const Icon(Icons.storage_outlined),
                  label: 'Backup & restore',
                  sub: 'Export or restore app data',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const DataSettingsPage()),
                  ),
                ),
                const Divider(height: 1, color: T.rule),
                _NavRow(
                  leading: const Icon(Icons.monitor_heart_outlined),
                  label: 'Diagnostics',
                  sub: 'Camera telemetry · app build · live logs',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => DiagnosticsPage(deviceId: activeId),
                    ),
                  ),
                ),
                Builder(
                  builder: (ctx) {
                    final devNav = ref.watch(devNavigationProvider);
                    if (devNav.developerSettings == null) {
                      return const SizedBox.shrink();
                    }
                    return Column(
                      children: [
                        const Divider(height: 1, color: T.rule),
                        _NavRow(
                          leading: const Icon(Icons.code),
                          label: 'Developer',
                          sub: 'Dev tools & data mode',
                          onTap: () => Navigator.of(ctx).push(
                            MaterialPageRoute(
                              builder: (_) => devNav.developerSettings!(),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // App section — static info, inline at the bottom
          WfCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                const _RowItem(
                  leading: Icon(Icons.palette_outlined),
                  label: 'Theme',
                  trailing: Text(
                    'Dark',
                    style: TextStyle(color: T.ink2, fontSize: 12),
                  ),
                ),
                const Divider(height: 1, color: T.rule),
                const _RowItem(
                  leading: Icon(Icons.lock_outline),
                  label: 'Permissions',
                  trailing: Text(
                    '3 granted',
                    style: TextStyle(color: T.ink2, fontSize: 12),
                  ),
                ),
                const Divider(height: 1, color: T.rule),
                // The DB debug browser used to hide behind a long-press here;
                // it now has a visible row in Settings → Developer.
                const _AboutRow(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Streaming nav row — used inside the grouped settings card.
// ---------------------------------------------------------------------------

class _StreamingRow extends ConsumerWidget {
  const _StreamingRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count =
        ref
            .watch(streamingDestinationsControllerProvider)
            .valueOrNull
            ?.length ??
        0;
    return _NavRow(
      leading: const Icon(Icons.cast_outlined),
      label: 'Streaming destinations',
      sub: 'Live stream endpoints',
      badge: count > 0
          ? '$count ${count == 1 ? 'destination' : 'destinations'}'
          : null,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const StreamingDestinationsPage()),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Auto-stop row — the unsupervised-session timeout (R5). Inline dropdown, no
// sub-page: one value, picked from a bounded ladder (the notifier clamps to
// kAutoStopMinMinutes..kAutoStopMaxMinutes as the backstop). Changing it
// while a session is live re-pushes the session config immediately — that
// side effect lives in the notifier (core/state/auto_stop.dart), not here.
// ---------------------------------------------------------------------------

class _AutoStopRow extends ConsumerWidget {
  const _AutoStopRow();

  /// Picker ladder — all within [kAutoStopMinMinutes]..[kAutoStopMaxMinutes].
  static const _choices = [5, 10, 15, 20, 30, 45, 60, 90, 120, 180, 240];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final minutes = ref.watch(autoStopMinutesProvider).valueOrNull;
    // A persisted value outside the ladder (defensive) still has to appear in
    // the dropdown's items, or DropdownButton asserts.
    final items = {..._choices, ?minutes}.toList()..sort();
    return _RowItem(
      leading: const Icon(Icons.timer_outlined),
      label: 'Auto-stop',
      sub: 'End unsupervised sessions after this long',
      trailing: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: minutes,
          isDense: true,
          dropdownColor: T.surface,
          style: const TextStyle(fontSize: 12, color: T.ink2),
          icon: const Icon(Icons.expand_more, size: 16, color: T.ink3),
          items: [
            for (final m in items)
              DropdownMenuItem(value: m, child: Text('$m min')),
          ],
          onChanged: minutes == null
              ? null // still loading the persisted value
              : (v) {
                  if (v == null) return;
                  ref.read(autoStopMinutesProvider.notifier).set(v);
                },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// About row — real app version (git-derived define, package metadata fallback)
// plus channel, replacing the old hardcoded literal.
// ---------------------------------------------------------------------------

class _AboutRow extends ConsumerWidget {
  const _AboutRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final version = ref.watch(appVersionProvider).valueOrNull ?? '—';
    return _RowItem(
      leading: const Icon(Icons.info_outline),
      label: 'About',
      trailing: Text(
        version,
        style: const TextStyle(color: T.ink2, fontSize: 12),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared row primitives reused across Match Setup, Streaming Setup sections.
// ---------------------------------------------------------------------------

class _RowItem extends StatelessWidget {
  const _RowItem({
    required this.leading,
    required this.label,
    this.sub,
    this.trailing,
  });
  final Widget leading;
  final String label;
  final String? sub;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          SizedBox(width: 24, child: Center(child: leading)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: T.ink,
                  ),
                ),
                if (sub != null) ...[const SizedBox(height: 2), WfNote(sub!)],
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class _NavRow extends StatelessWidget {
  const _NavRow({
    required this.leading,
    required this.label,
    this.sub,
    this.badge,
    required this.onTap,
  });
  final Widget leading;
  final String label;
  final String? sub;
  final String? badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: _RowItem(
        leading: leading,
        label: label,
        sub: sub,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (badge != null) ...[
              Text(badge!, style: const TextStyle(color: T.ink2, fontSize: 12)),
              const SizedBox(width: 4),
            ],
            const Icon(Icons.chevron_right, color: T.ink3, size: 18),
          ],
        ),
      ),
    );
  }
}
