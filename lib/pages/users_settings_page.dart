import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/app_data.dart';
import '../theme/tokens.dart';
import '../widgets/wf_chip.dart';
import 'user_form_sheet.dart';


class UsersSettingsPage extends ConsumerWidget {
  const UsersSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usersAsync = ref.watch(usersControllerProvider);
    final activeId = ref.watch(activeUserProvider);

    return Scaffold(
      backgroundColor: T.bg,
      appBar: AppBar(title: const Text('Users')),
      floatingActionButton: FloatingActionButton(
        heroTag: null,
        onPressed: () => _addUser(context, ref),
        backgroundColor: T.accent,
        foregroundColor: T.accentInk,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(4)),
        ),
        child: const Icon(Icons.add, size: 28),
      ),
      body: usersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Could not load users: $e',
              style: const TextStyle(color: T.ink2, fontSize: 12),
            ),
          ),
        ),
        data: (users) {
          if (users.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const WfChip(label: 'No users yet'),
                    const SizedBox(height: 12),
                    const Text(
                      'Add your first operator profile to start organising data.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: T.ink2, height: 1.4),
                    ),
                  ],
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(0, 0, 0, 80),
            itemCount: users.length,
            separatorBuilder: (_, _) => const Divider(height: 1, color: T.rule),
            itemBuilder: (_, i) {
              final u = users[i];
              final isActive = u.id == activeId;
              final canDelete = !isActive && users.length > 1;
              return _UserRow(
                user: u,
                isActive: isActive,
                canDelete: canDelete,
                onTap: () => _selectUser(context, ref, u),
                onDelete: canDelete ? () => _deleteUser(context, ref, u) : null,
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _addUser(BuildContext context, WidgetRef ref) async {
    final draft = await showUserFormSheet(context);
    if (draft == null) return;
    try {
      await ref.read(usersControllerProvider.notifier).create(draft.name);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not create user: $e')));
    }
  }

  Future<void> _deleteUser(
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not delete user: $e')));
    }
  }

  Future<void> _selectUser(
    BuildContext context,
    WidgetRef ref,
    UserRecord target,
  ) async {
    if (target.id == ref.read(activeUserProvider)) return;
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
}

class _UserRow extends StatelessWidget {
  const _UserRow({
    required this.user,
    required this.isActive,
    required this.canDelete,
    required this.onTap,
    this.onDelete,
  });
  final UserRecord user;
  final bool isActive;
  final bool canDelete;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: T.bg,
      child: InkWell(
        onTap: isActive ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: isActive ? T.accentSoft : T.fillSoft,
                  shape: BoxShape.circle,
                  border: Border.all(color: isActive ? T.accent : T.hair),
                ),
                alignment: Alignment.center,
                child: Text(
                  user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: isActive ? T.accent : T.ink2,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  user.name,
                  style: const TextStyle(
                    fontSize: 14,
                    color: T.ink,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (isActive)
                const Icon(Icons.check, color: T.accent, size: 18)
              else
                const Icon(Icons.radio_button_unchecked, color: T.ink3, size: 18),
              if (canDelete) ...[
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: onDelete,
                  child: const Icon(Icons.delete_outline, color: T.ink3, size: 18),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
