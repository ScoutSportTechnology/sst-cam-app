import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/device.dart';
import '../state/app_data.dart';
import '../state/ble_providers.dart';
import '../state/last_camera.dart';
import '../theme/tokens.dart';
import '../widgets/wf_button.dart';
import '../widgets/wf_card.dart';
import 'app_settings_page.dart';
import 'data_settings_page.dart';
import 'diagnostics_page.dart';
import 'discovery_page.dart';
import 'sport_presets_page.dart';
import 'streaming_destinations_page.dart';
import 'users_settings_page.dart';

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
          // Camera card: only when connected. _ConnectCameraBanner replaces it
          // when no camera is present so the user can reconnect.
          if (connected)
            _CameraCard(deviceId: activeId)
          else
            const _ConnectCameraBanner(),
          const SizedBox(height: 14),
          const WfSection('Users', padding: EdgeInsets.only(bottom: 6)),
          Builder(
            builder: (context) {
              final activeId = ref.watch(activeUserProvider);
              final usersAsync = ref.watch(usersControllerProvider);
              final activeName = usersAsync.valueOrNull
                  ?.where((u) => u.id == activeId)
                  .firstOrNull
                  ?.name;
              return WfCard(
                padding: EdgeInsets.zero,
                child: _NavRow(
                  leading: const Icon(Icons.person_outline),
                  label: 'Users',
                  badge: activeName ?? 'Pick a user to get started',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const UsersSettingsPage(),
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 14),
          const WfSection('Match setup', padding: EdgeInsets.only(bottom: 6)),
          WfCard(
            padding: EdgeInsets.zero,
            child: _NavRow(
              leading: const Icon(Icons.sports_soccer_outlined),
              label: 'Sport setups',
              sub: 'Saved time configs per sport',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SportPresetsPage()),
                );
              },
            ),
          ),
          const SizedBox(height: 14),
          const _StreamingSection(),
          const SizedBox(height: 14),
          const WfSection('App', padding: EdgeInsets.only(bottom: 6)),
          WfCard(
            padding: EdgeInsets.zero,
            child: _NavRow(
              leading: const Icon(Icons.settings_outlined),
              label: 'App',
              sub: 'Theme, permissions, about',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AppSettingsPage()),
              ),
            ),
          ),
          const SizedBox(height: 14),
          const WfSection('Data', padding: EdgeInsets.only(bottom: 6)),
          WfCard(
            padding: EdgeInsets.zero,
            child: _NavRow(
              leading: const Icon(Icons.storage_outlined),
              label: 'Backup & restore',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const DataSettingsPage()),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Streaming setup section
// ---------------------------------------------------------------------------

class _StreamingSection extends ConsumerWidget {
  const _StreamingSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final streamingCount =
        ref
            .watch(streamingDestinationsControllerProvider)
            .valueOrNull
            ?.length ??
        0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const WfSection('Streaming setup', padding: EdgeInsets.only(bottom: 6)),
        WfCard(
          padding: EdgeInsets.zero,
          child: _NavRow(
            leading: const Icon(Icons.cast_outlined),
            label: 'Streaming destinations',
            badge: streamingCount > 0
                ? '$streamingCount ${streamingCount == 1 ? 'destination' : 'destinations'}'
                : null,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const StreamingDestinationsPage(),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Camera card. Reboot and Update fw remain visual placeholders until
// firmware lands; they render disabled with a tooltip explaining that.
// fw / proto values are placeholder strings — pipe them from the
// SstDevice / telemetry stream when that data is reachable here.
// ---------------------------------------------------------------------------

class _CameraCard extends ConsumerWidget {
  const _CameraCard({required this.deviceId});

  final String deviceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                    const Text(
                      'fw 0.3.2 · proto v0.3',
                      style: TextStyle(
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
                    label: 'Update fw',
                    size: WfButtonSize.sm,
                    onPressed: null,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Bottom button row: Disconnect · Diagnostics — both wired.
          Row(
            children: [
              Expanded(
                child: WfButton(
                  label: 'Disconnect',
                  size: WfButtonSize.sm,
                  onPressed: () => _disconnect(ref, deviceId),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: WfButton(
                  label: 'Diagnostics',
                  size: WfButtonSize.sm,
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const DiagnosticsPage(),
                      ),
                    );
                  },
                ),
              ),
            ],
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
