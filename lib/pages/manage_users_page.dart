import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/app_data.dart';
import '../theme/tokens.dart';
import '../widgets/wf_card.dart';
import '../widgets/wf_chip.dart';
import 'user_form_sheet.dart';

/// Full-page user management. Lists all camera-side users with an active badge,
/// switch affordance (tap non-active row), delete affordance (R10 rules),
/// and a FAB for adding new users.
class ManageUsersPage extends ConsumerWidget {
  const ManageUsersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usersAsync = ref.watch(usersControllerProvider);
    final activeId = ref.watch(activeUserProvider);
    final liveMatchRunning = isLiveMatchRunning(ref.watch(liveMatchProvider));

    return Scaffold(
      backgroundColor: T.bg,
      appBar: AppBar(title: const Text('Manage users')),
      body: usersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Could not load users: $e',
              textAlign: TextAlign.center,
              style: const TextStyle(color: T.ink2, fontSize: 12),
            ),
          ),
        ),
        data: (users) {
          if (users.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 32),
                child: WfNote('No users on this camera yet.'),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.only(bottom: 80),
            children: [
              for (final user in users) ...[
                _UserRow(
                  user: user,
                  isActive: user.id == activeId,
                  isLastRemaining: users.length <= 1,
                  liveMatchRunning: liveMatchRunning,
                  onSwitch: () => _onSwitchTapped(context, ref, user),
                  onDelete: () => _onDeleteTapped(context, ref, user),
                ),
                const Divider(height: 1, color: T.rule),
              ],
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(heroTag: null,
        onPressed: () => _onAddTapped(context, ref),
        backgroundColor: T.accent,
        foregroundColor: T.accentInk,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(4)),
        ),
        child: const Icon(Icons.person_add_outlined, size: 26),
      ),
    );
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
}

class _UserRow extends StatelessWidget {
  const _UserRow({
    required this.user,
    required this.isActive,
    required this.isLastRemaining,
    required this.liveMatchRunning,
    required this.onSwitch,
    required this.onDelete,
  });

  final UserRecord user;
  final bool isActive;
  final bool isLastRemaining;
  final bool liveMatchRunning;
  final VoidCallback onSwitch;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final String subtitle;
    final bool deleteEnabled;
    if (isLastRemaining) {
      subtitle = 'Add another user before deleting the last one';
      deleteEnabled = false;
    } else if (isActive) {
      subtitle = 'Switch to another user before deleting';
      deleteEnabled = false;
    } else if (liveMatchRunning) {
      subtitle = 'End the live match before deleting';
      deleteEnabled = false;
    } else {
      subtitle = '';
      deleteEnabled = true;
    }

    return InkWell(
      onTap: isActive ? null : onSwitch,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            const SizedBox(
              width: 24,
              child: Center(child: Icon(Icons.person_outline, color: T.ink2)),
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
                          user.name,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            color: T.ink,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      if (isActive) ...[
                        const SizedBox(width: 8),
                        const WfChip(label: 'Active', active: true),
                      ],
                    ],
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11,
                        color: deleteEnabled ? T.ink2 : T.ink3,
                      ),
                    ),
                  ],
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
