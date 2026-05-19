import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/app_data.dart';
import '../theme/tokens.dart';
import '../widgets/wf_card.dart';
import '../widgets/wf_chip.dart';
import 'manage_users_page.dart';

class UsersSettingsPage extends ConsumerWidget {
  const UsersSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: T.bg,
      appBar: AppBar(title: const Text('Users')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
        children: const [
          _UserSection(),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// User section — moved from settings_page.dart
// ---------------------------------------------------------------------------

class _UserSection extends ConsumerWidget {
  const _UserSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usersAsync = ref.watch(usersControllerProvider);
    final activeId = ref.watch(activeUserProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        usersAsync.when(
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
            UserRecord? active;
            for (final u in users) {
              if (u.id == activeId) {
                active = u;
                break;
              }
            }
            return WfCard(
              padding: EdgeInsets.zero,
              child: Builder(
                builder: (ctx) => InkWell(
                  borderRadius: BorderRadius.circular(4),
                  onTap: () => _openPicker(ctx, ref, users, activeId),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 14,
                    ),
                    child: Row(
                      children: [
                        if (active != null) ...[
                          const WfChip(label: 'Active', active: true),
                          const SizedBox(width: 10),
                        ],
                        Expanded(
                          child: active != null
                              ? Text(
                                  active.name,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: T.ink,
                                    fontWeight: FontWeight.w500,
                                  ),
                                )
                              : const WfNote('Pick a user to get started'),
                        ),
                        const Icon(Icons.expand_more, color: T.ink3, size: 20),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 8),
        WfCard(
          padding: EdgeInsets.zero,
          child: _NavRow(
            leading: const Icon(Icons.manage_accounts_outlined),
            label: 'Manage users',
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const ManageUsersPage())),
          ),
        ),
      ],
    );
  }

  Future<void> _openPicker(
    BuildContext ctx,
    WidgetRef ref,
    List<UserRecord> users,
    String? activeId,
  ) async {
    final box = ctx.findRenderObject()! as RenderBox;
    final overlay =
        Navigator.of(ctx).overlay!.context.findRenderObject()! as RenderBox;
    final offset = box.localToGlobal(Offset.zero, ancestor: overlay);
    final selected = await showMenu<UserRecord>(
      context: ctx,
      position: RelativeRect.fromLTRB(
        offset.dx,
        offset.dy + box.size.height,
        overlay.size.width - offset.dx - box.size.width,
        0,
      ),
      constraints: BoxConstraints(minWidth: box.size.width),
      items: [
        for (final u in users)
          PopupMenuItem<UserRecord>(
            value: u,
            child: Row(
              children: [
                Flexible(child: Text(u.name)),
                if (u.id == activeId) ...[
                  const SizedBox(width: 8),
                  const WfChip(label: 'Active', active: true),
                ],
              ],
            ),
          ),
      ],
    );
    if (selected == null || !ctx.mounted) return;
    _onSwitchTapped(ctx, ref, selected);
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
}

// ---------------------------------------------------------------------------
// Local nav-row primitive (mirrors _NavRow from settings_page.dart)
// ---------------------------------------------------------------------------

class _NavRow extends StatelessWidget {
  const _NavRow({
    required this.leading,
    required this.label,
    required this.onTap,
  });
  final Widget leading;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            SizedBox(width: 24, child: Center(child: leading)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: T.ink,
                ),
              ),
            ),
            const Icon(Icons.chevron_right, color: T.ink3, size: 18),
          ],
        ),
      ),
    );
  }
}

