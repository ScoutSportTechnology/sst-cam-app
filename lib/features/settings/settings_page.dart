import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/dev_navigation.dart';
import '../../core/models/device.dart';
import '../camera/camera_state.dart' show activeCameraIdProvider;
import 'streaming/streaming_state.dart'
    show streamingDestinationsControllerProvider;
import 'users/users_state.dart'
    show activeUserProvider, usersControllerProvider;
import '../../core/ble/ble_providers.dart';
import '../../core/state/last_camera.dart';
import '../../core/theme/tokens.dart';
import '../../core/version/version_info.dart';
import '../../core/widgets/wf_button.dart';
import '../../core/widgets/wf_card.dart';
import 'data/data_settings_page.dart';
import '../discovery/diagnostics_page.dart';
import '../discovery/discovery_page.dart';
import 'sport_presets/sport_presets_page.dart';
import 'network/network_settings_page.dart';
import 'streaming/streaming_destinations_page.dart';
import 'users/users_settings_page.dart';

/// Settings page. Always shows a single Scaffold.
///
/// When no camera is connected the body shows a slim `_ConnectCameraBanner`
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
            _CameraCard(deviceId: activeId)
          else
            const _ConnectCameraBanner(),
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
// Camera card. Reboot and Update fw remain visual placeholders until
// firmware lands; they render disabled with a tooltip explaining that.
// fw / proto values are now real: firmware from the device's firmwareVersion,
// proto from the built-against repo tag + the wire protocol_version.
// ---------------------------------------------------------------------------

class _CameraCard extends ConsumerWidget {
  const _CameraCard({required this.deviceId});

  final String deviceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Real firmware version from the connected camera's DeviceInfo (the
    // scan-time SstDevice carries empty fw). proto = the built-against repo tag.
    // The wire protocol_version is technical — it lives in Diagnostics, not here.
    final info = ref.watch(connectedDeviceInfoProvider(deviceId)).valueOrNull;
    final fwRaw = info?.firmwareVersion ?? '';
    final fw = fwRaw.isEmpty ? '—' : fwRaw;
    final protoLine = 'proto $protoRepoVersion';

    return WfCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const WfNote('Connected camera'),
                    const SizedBox(height: 4),
                    Text(
                      deviceId,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: T.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'fw $fw · $protoLine',
                      style: const TextStyle(
                        fontFamily: T.mono,
                        fontSize: 11,
                        color: T.ink2,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: T.accent,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: const [
              Expanded(
                child: Tooltip(
                  message: 'Coming soon — firmware integration',
                  child: WfButton(
                    label: 'Reboot',
                    size: WfButtonSize.sm,
                    onPressed: null,
                  ),
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                child: Tooltip(
                  message: 'Coming soon — firmware integration',
                  child: WfButton(
                    label: 'Upgrade',
                    size: WfButtonSize.sm,
                    onPressed: null,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Disconnect — Diagnostics now lives in the Settings list as its own
          // row (Settings → Diagnostics), not buried on the camera card.
          WfButton(
            label: 'Disconnect',
            variant: WfButtonVariant.danger,
            size: WfButtonSize.sm,
            full: true,
            onPressed: () => _disconnect(ref, deviceId),
          ),
        ],
      ),
    );
  }

  /// Drop the BLE link only — the camera stays in the known list so a
  /// subsequent one-tap reconnect from the empty state works without
  /// rescanning. Per R4.
  Future<void> _disconnect(WidgetRef ref, String deviceId) async {
    await ref.read(bleServiceProvider).disconnect(deviceId);
    ref.read(activeCameraIdProvider.notifier).state = null;
  }
}

// ---------------------------------------------------------------------------
// Slim "connect camera" banner — shown inside the shared Scaffold when no
// camera is connected. Replaces the old full-Scaffold _ConnectCameraEmptyState
// so the Data section can always render below it.
//
// The CTA runs a small state machine:
//   1. On tap → loading (disabled, "Connecting…", inline spinner).
//   2. If `lastConnectedDeviceIdProvider` has a value, attempt
//      `bleService.connect(lastId).timeout(5s)`.
//   3. Success: write `activeCameraIdProvider`; the page rerenders to the
//      populated layout. If `getActiveUser` returns null we leave
//      `activeUserProvider` null and the User section renders the
//      "Pick a user" prompt.
//   4. Failure (any exception or timeout): push `DiscoveryPage` and
//      surface a `SnackBar` with the "Couldn't reconnect" copy.
//   5. No persisted last id: push `DiscoveryPage` directly without
//      attempting reconnect (no loading state, no snackbar).
// ---------------------------------------------------------------------------

class _ConnectCameraBanner extends ConsumerStatefulWidget {
  const _ConnectCameraBanner();

  @override
  ConsumerState<_ConnectCameraBanner> createState() =>
      _ConnectCameraBannerState();
}

class _ConnectCameraBannerState extends ConsumerState<_ConnectCameraBanner> {
  bool _isConnecting = false;

  Future<void> _onConnectTapped() async {
    setState(() => _isConnecting = true);
    try {
      final lastIdAsync = ref.read(lastConnectedDeviceIdProvider);
      final lastId = lastIdAsync.valueOrNull;
      if (lastId == null) {
        // First-launch path: just push DiscoveryPage.
        if (!mounted) return;
        await Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const DiscoveryPage()));
        return;
      }

      // One-tap reconnect.
      final svc = ref.read(bleServiceProvider);
      try {
        await svc.connect(lastId).timeout(const Duration(seconds: 5));
        // Success: set active camera id; the page rerenders to populated.
        ref.read(activeCameraIdProvider.notifier).state = lastId;
      } catch (_) {
        // BleConnectionException, TimeoutException, anything else — same
        // user-facing fallback per the plan.
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "Couldn't reconnect to last camera — searching for cameras.",
            ),
          ),
        );
        await Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const DiscoveryPage()));
      }
    } finally {
      if (mounted) setState(() => _isConnecting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return WfCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: T.fillSoft,
                  shape: BoxShape.circle,
                  border: Border.all(color: T.hair),
                ),
                child: const Icon(
                  Icons.videocam_off_outlined,
                  color: T.ink2,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      'No camera connected',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: T.ink,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Connect a camera to manage users, formats, and streaming '
                      'destinations.',
                      style: TextStyle(
                        fontSize: 11,
                        color: T.ink2,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_isConnecting)
            Row(
              children: const [
                Expanded(
                  child: WfButton(
                    label: 'Connecting…',
                    variant: WfButtonVariant.primary,
                    full: true,
                    onPressed: null,
                  ),
                ),
                SizedBox(width: 10),
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(T.accent),
                  ),
                ),
              ],
            )
          else
            WfButton(
              label: 'Connect camera',
              variant: WfButtonVariant.primary,
              full: true,
              onPressed: _onConnectTapped,
            ),
        ],
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
