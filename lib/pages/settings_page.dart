import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/device.dart';
import '../state/app_data.dart';
import '../state/ble_providers.dart';
import '../theme/tokens.dart';
import '../widgets/wf_button.dart';
import '../widgets/wf_card.dart';
import 'discovery_page.dart';
import 'sport_presets_page.dart';

/// Settings — U6 shell.
///
/// Two render shapes:
///   1. Empty state when no camera is connected, mirroring the
///      `_ConnectCameraScreen` pattern from `match_page.dart`.
///   2. Populated layout (5 sections) when a camera is connected. The
///      Camera / User / Streaming Setup sections are placeholders that
///      U7 / U8 / U9 fill in. Match Setup and App are real here.
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeId = ref.watch(activeCameraIdProvider);
    final connected =
        activeId != null &&
        ref.watch(connectionStateProvider(activeId)).valueOrNull ==
            CameraConnectionState.connected;

    if (!connected) {
      return const _ConnectCameraEmptyState();
    }

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
          // 1. Camera — placeholder card (U7 fills in the 4-button card).
          const WfCard(
            child: Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'Camera section — populated in U7',
                style: TextStyle(color: T.ink2, fontSize: 12),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // 2. User — placeholder (U8).
          const WfSection('User', padding: EdgeInsets.only(bottom: 6)),
          const WfCard(
            child: Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'User section — populated in U8',
                style: TextStyle(color: T.ink2, fontSize: 12),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // 3. Match Setup — real nav row to the existing SportPresetsPage.
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

          // 4. Streaming Setup — placeholder (U9).
          const WfSection(
            'Streaming setup',
            padding: EdgeInsets.only(bottom: 6),
          ),
          const WfCard(
            child: Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'Streaming Setup section — populated in U9',
                style: TextStyle(color: T.ink2, fontSize: 12),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // 5. App — Theme / Permissions / About. Diagnostics moved to the
          // camera card per R5 (U7).
          const WfSection('App', padding: EdgeInsets.only(bottom: 6)),
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
          const _RowItem(
            leading: Icon(Icons.info_outline),
            label: 'About',
            trailing: Text(
              '0.3.2',
              style: TextStyle(color: T.ink2, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Empty state — full-screen "Connect camera" prompt mirroring
// `_ConnectCameraScreen` from match_page.dart so the three tabs feel like
// one product when no camera is paired.
//
// U7 will replace the simple DiscoveryPage push with a one-tap reconnect
// state machine. For U6 the CTA is the unconditional fallback.
// ---------------------------------------------------------------------------

class _ConnectCameraEmptyState extends StatelessWidget {
  const _ConnectCameraEmptyState();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: T.bg,
      appBar: AppBar(title: const Text('Settings')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 64,
                height: 64,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: T.fillSoft,
                  shape: BoxShape.circle,
                  border: Border.all(color: T.hair),
                ),
                child: const Icon(
                  Icons.videocam_off_outlined,
                  color: T.ink2,
                  size: 28,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'No camera connected',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: T.ink,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Connect a camera to manage users, formats, and streaming '
                'destinations.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: T.ink2, height: 1.4),
              ),
              const SizedBox(height: 18),
              WfButton(
                label: 'Connect camera',
                variant: WfButtonVariant.primary,
                full: true,
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const DiscoveryPage()),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared row primitives — kept from the previous shell because U7-U9 reuse
// them inside their section bodies.
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
    required this.onTap,
  });
  final Widget leading;
  final String label;
  final String? sub;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: _RowItem(
        leading: leading,
        label: label,
        sub: sub,
        trailing: const Icon(Icons.chevron_right, color: T.ink3, size: 18),
      ),
    );
  }
}
