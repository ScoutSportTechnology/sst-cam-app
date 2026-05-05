import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/device.dart';
import '../state/app_data.dart';
import '../state/ble_providers.dart';
import '../state/last_camera.dart';
import '../theme/tokens.dart';
import '../widgets/wf_button.dart';
import '../widgets/wf_card.dart';
import '../widgets/wf_chip.dart';
import 'diagnostics_page.dart';
import 'discovery_page.dart';
import 'sport_presets_page.dart';
import 'user_form_sheet.dart';

/// Settings — U7 layer over the U6 shell.
///
/// Two render shapes:
///   1. Empty state when no camera is connected, mirroring the
///      `_ConnectCameraScreen` pattern from `match_page.dart`. The CTA
///      now drives a one-tap reconnect state machine: if a last-camera id
///      is persisted, attempt `bleService.connect(lastId).timeout(5s)`
///      before falling back to a fresh scan in `DiscoveryPage`.
///   2. Populated layout (5 sections) when a camera is connected. The
///      Camera section is the real 2x2 button card here; User and
///      Streaming Setup remain placeholders that U8 / U9 fill in.
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
          // 1. Camera — connected-camera card with 2x2 button grid.
          _CameraCard(deviceId: activeId),
          const SizedBox(height: 14),

          // 2. User — inline section. Active user at top with an "Active"
          // badge; other users below with delete affordances; "Add user"
          // row at the bottom. When activeUserProvider is null (post-
          // reconnect with no camera-side active user) renders the
          // "Pick a user" shape instead. See U8.
          const WfSection('User', padding: EdgeInsets.only(bottom: 6)),
          const _UserSection(),
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
          // camera card per R5 (one of the four buttons).
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
// Camera card — connected-state. Top row shows display name + fw/proto /
// connection dot; bottom is a 2x2 WfButton grid (Reboot, Update fw,
// Disconnect, Diagnostics) per R4/R5.
//
// Reboot and Update fw are intentional placeholders until firmware lands —
// rendered disabled with a `Tooltip("Coming soon — firmware integration")`
// so the affordance reads as "deferred" rather than "broken".
//
// TODO: pipe `fw` and `proto` from the ScoutDevice / telemetry stream once
// the device record is reachable from this scope. For U7 we surface the
// connected device id (which serves as the display name) and a static
// fw/proto label — sufficient to render and exercise the four-button card
// in tests.
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
          // Top button row: Reboot · Update fw — both disabled placeholders
          // wrapped in a Tooltip explaining the deferred state.
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
// Empty state — full-screen "Connect camera" prompt mirroring
// `_ConnectCameraScreen` from match_page.dart so the three tabs feel like
// one product when no camera is paired.
//
// The CTA runs a small state machine:
//   1. On tap → loading (disabled, "Connecting…", inline spinner).
//   2. If `lastConnectedDeviceIdProvider` has a value, attempt
//      `bleService.connect(lastId).timeout(5s)`.
//   3. Success: write `activeCameraIdProvider`; the page rerenders to the
//      populated layout. (Active-user hydration is U8's concern — if
//      `getActiveUser` returns null, we leave `activeUserProvider` null
//      and the User section renders the "Pick a user" prompt.)
//   4. Failure (any exception or timeout): push `DiscoveryPage` and
//      surface a `SnackBar` with the "Couldn't reconnect" copy.
//   5. No persisted last id: push `DiscoveryPage` directly without
//      attempting reconnect (no loading state, no snackbar).
// ---------------------------------------------------------------------------

class _ConnectCameraEmptyState extends ConsumerStatefulWidget {
  const _ConnectCameraEmptyState();

  @override
  ConsumerState<_ConnectCameraEmptyState> createState() =>
      _ConnectCameraEmptyStateState();
}

class _ConnectCameraEmptyStateState
    extends ConsumerState<_ConnectCameraEmptyState> {
  bool _isConnecting = false;

  Future<void> _onConnectTapped() async {
    setState(() => _isConnecting = true);
    try {
      final lastIdAsync = ref.read(lastConnectedDeviceIdProvider);
      final lastId = lastIdAsync.valueOrNull;
      if (lastId == null) {
        // First-launch path: just push DiscoveryPage. No loading state
        // would have been useful, but we already entered it on tap; the
        // finally block resets us when the route returns.
        if (!mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const DiscoveryPage()),
        );
        return;
      }

      // One-tap reconnect.
      final svc = ref.read(bleServiceProvider);
      try {
        await svc.connect(lastId).timeout(const Duration(seconds: 5));
        // Success: set active camera id; the page rerenders to populated.
        // Active-user hydration happens lazily via UsersController.build.
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
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const DiscoveryPage()),
        );
      }
    } finally {
      if (mounted) setState(() => _isConnecting = false);
    }
  }

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
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared row primitives — kept from the previous shell because U8/U9 reuse
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

// ---------------------------------------------------------------------------
// User section (U8) — inline active-user row + others-with-delete + Add user.
//
// Shape A (`activeUserProvider` non-null): active row with an "Active" badge,
// divider, list of others (each tappable to switch, with a trailing delete
// icon disabled per R10's UI rules), divider, "Add user" row.
//
// Shape B (`activeUserProvider` null — post-reconnect with no camera-side
// active user, or empty user list): a centered "Pick a user" note, list of
// all users with a trailing "Make active" icon button (Icons.radio_button_
// unchecked), and the "Add user" row. The active row + Active badge are
// not rendered.
//
// The delete icon's `onPressed` is set to null when:
//   * users.length == 1 (last remaining user) — subtitle: "Add another user
//     before deleting the last one"
//   * a live match is in progress — subtitle: "End the live match before
//     deleting"
// The active user is never rendered in the others list, so the "switch
// before deleting" disabled case is structurally enforced rather than
// conditionally rendered.
// ---------------------------------------------------------------------------

class _UserSection extends ConsumerWidget {
  const _UserSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usersAsync = ref.watch(usersControllerProvider);
    final activeId = ref.watch(activeUserProvider);
    final liveMatchRunning = isLiveMatchRunning(ref.watch(liveMatchProvider));

    return usersAsync.when(
      loading: () => const WfCard(
        child: Padding(
          padding: EdgeInsets.all(12),
          child: Center(
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
      ),
      error: (e, _) => WfCard(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            'Could not load users: $e',
            style: const TextStyle(color: T.ink2, fontSize: 12),
          ),
        ),
      ),
      data: (users) {
        if (activeId == null) {
          return _NoActiveUserCard(
            users: users,
            onMakeActive: (u) => _onSwitchTapped(context, ref, u),
            onAdd: () => _onAddTapped(context, ref),
          );
        }
        final active = users.firstWhere(
          (u) => u.id == activeId,
          orElse: () => UserRecord(id: activeId, name: activeId),
        );
        final others = users.where((u) => u.id != activeId).toList();
        return _ActiveUserCard(
          active: active,
          others: others,
          isLastRemaining: users.length <= 1,
          liveMatchRunning: liveMatchRunning,
          onSwitchTapped: (u) => _onSwitchTapped(context, ref, u),
          onDeleteTapped: (u) => _onDeleteTapped(context, ref, u),
          onAdd: () => _onAddTapped(context, ref),
        );
      },
    );
  }

  Future<void> _onSwitchTapped(
    BuildContext context,
    WidgetRef ref,
    UserRecord target,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: T.surface,
        title: const Text('Switch user?'),
        content: Text(
          'Switch to ${target.name}? Your teams, matches, and streaming '
          'destinations will reload to show their data.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Switch'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(usersControllerProvider.notifier).setActive(target.id);
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't switch user — try again.")),
      );
    }
  }

  Future<void> _onDeleteTapped(
    BuildContext context,
    WidgetRef ref,
    UserRecord target,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: T.surface,
        title: const Text('Delete user?'),
        content: Text(
          'Deleting ${target.name} permanently removes their teams, match '
          'history, sport setups, and streaming destinations. This cannot be '
          'undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              'Delete user',
              style: TextStyle(color: T.danger, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(usersControllerProvider.notifier).delete(target.id);
    } on UsersControllerException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not delete user: $e')));
    }
  }

  Future<void> _onAddTapped(BuildContext context, WidgetRef ref) async {
    final draft = await showUserFormSheet(context);
    if (draft == null) return;
    try {
      await ref.read(usersControllerProvider.notifier).create(draft.name);
    } on UsersControllerException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not add user: $e')));
    }
  }
}

class _ActiveUserCard extends StatelessWidget {
  const _ActiveUserCard({
    required this.active,
    required this.others,
    required this.isLastRemaining,
    required this.liveMatchRunning,
    required this.onSwitchTapped,
    required this.onDeleteTapped,
    required this.onAdd,
  });

  final UserRecord active;
  final List<UserRecord> others;
  final bool isLastRemaining;
  final bool liveMatchRunning;
  final ValueChanged<UserRecord> onSwitchTapped;
  final ValueChanged<UserRecord> onDeleteTapped;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return WfCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Active user row.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                const SizedBox(
                  width: 24,
                  child: Center(
                    child: Icon(Icons.person_outline, color: T.ink2),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              active.name,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14,
                                color: T.ink,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          const WfChip(label: 'Active', active: true),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        active.id,
                        style: const TextStyle(
                          fontFamily: T.mono,
                          fontSize: 11,
                          color: T.ink2,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: T.rule),
          // Others — tap to switch, trailing delete icon (with rule-aware
          // disabled state + subtitle).
          for (final u in others) ...[
            _OtherUserRow(
              user: u,
              isLastRemaining: isLastRemaining,
              liveMatchRunning: liveMatchRunning,
              onTap: () => onSwitchTapped(u),
              onDelete: () => onDeleteTapped(u),
            ),
            const Divider(height: 1, color: T.rule),
          ],
          InkWell(
            onTap: onAdd,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  SizedBox(
                    width: 24,
                    child: Center(
                      child: Icon(Icons.person_add_outlined, color: T.ink2),
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Add user',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: T.ink,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OtherUserRow extends StatelessWidget {
  const _OtherUserRow({
    required this.user,
    required this.isLastRemaining,
    required this.liveMatchRunning,
    required this.onTap,
    required this.onDelete,
  });

  final UserRecord user;
  final bool isLastRemaining;
  final bool liveMatchRunning;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final String subtitle;
    final bool deleteEnabled;
    if (isLastRemaining) {
      subtitle = 'Add another user before deleting the last one';
      deleteEnabled = false;
    } else if (liveMatchRunning) {
      subtitle = 'End the live match before deleting';
      deleteEnabled = false;
    } else {
      subtitle = 'Switch to set as active';
      deleteEnabled = true;
    }
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            const SizedBox(
              width: 24,
              child: Center(
                child: Icon(Icons.person_outline, color: T.ink2),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.name,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: T.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11,
                      color: deleteEnabled ? T.ink2 : T.ink3,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 18),
              color: deleteEnabled ? T.ink2 : T.ink3,
              onPressed: deleteEnabled ? onDelete : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _NoActiveUserCard extends StatelessWidget {
  const _NoActiveUserCard({
    required this.users,
    required this.onMakeActive,
    required this.onAdd,
  });

  final List<UserRecord> users;
  final ValueChanged<UserRecord> onMakeActive;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return WfCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(14, 14, 14, 12),
            child: Center(
              child: WfNote(
                'Pick a user to organize your teams, matches, and streaming '
                'destinations.',
              ),
            ),
          ),
          const Divider(height: 1, color: T.rule),
          for (final u in users) ...[
            InkWell(
              onTap: () => onMakeActive(u),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 24,
                      child: Center(
                        child: Icon(Icons.person_outline, color: T.ink2),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        u.name,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: T.ink,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.radio_button_unchecked,
                        size: 18,
                      ),
                      color: T.ink2,
                      tooltip: 'Make active',
                      onPressed: () => onMakeActive(u),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1, color: T.rule),
          ],
          InkWell(
            onTap: onAdd,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  SizedBox(
                    width: 24,
                    child: Center(
                      child: Icon(Icons.person_add_outlined, color: T.ink2),
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Add user',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: T.ink,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
