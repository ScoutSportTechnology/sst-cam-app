import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/app_data.dart';
import '../theme/tokens.dart';
import '../widgets/wf_button.dart';
import '../widgets/wf_card.dart';
import '../widgets/wf_chip.dart';
import 'team_detail_page.dart';
import 'team_form_sheet.dart';

class TeamsPage extends ConsumerWidget {
  const TeamsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final teamsAsync = ref.watch(teamsControllerProvider);
    final filtered = ref.watch(filteredTeamsProvider);
    final showHidden = ref.watch(teamsShowHiddenProvider);

    return Scaffold(
      backgroundColor: T.bg,
      appBar: AppBar(
        title: const Text('Teams'),
        actions: [
          PopupMenuButton<_TeamsMenuAction>(
            icon: const Icon(Icons.more_vert),
            onSelected: (a) => _onMenu(context, ref, a),
            itemBuilder: (_) => [
              CheckedPopupMenuItem(
                value: _TeamsMenuAction.toggleHidden,
                checked: showHidden,
                child: const Text('Show hidden'),
              ),
              const PopupMenuItem(
                value: _TeamsMenuAction.refresh,
                child: Text('Refresh'),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(14, 10, 14, 10),
            child: _SearchField(),
          ),
          const SizedBox(height: 32, child: _SportFilterChips()),
          teamsAsync.when(
            loading: () => const Expanded(
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Expanded(child: _TeamsErrorState(error: e)),
            data: (rawTeams) {
              if (rawTeams.isEmpty) {
                return Expanded(
                  child: _NoTeamsYet(
                    onAdd: () => _showAddTeamSheet(context, ref),
                  ),
                );
              }
              return Expanded(
                child: _TeamsList(teams: filtered, totalShown: filtered.length),
              );
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddTeamSheet(context, ref),
        backgroundColor: T.accent,
        foregroundColor: T.accentInk,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(4)),
        ),
        child: const Icon(Icons.add, size: 28),
      ),
    );
  }

  Future<void> _onMenu(
    BuildContext context,
    WidgetRef ref,
    _TeamsMenuAction action,
  ) async {
    switch (action) {
      case _TeamsMenuAction.toggleHidden:
        ref.read(teamsShowHiddenProvider.notifier).update((v) => !v);
      case _TeamsMenuAction.refresh:
        ref.invalidate(teamsControllerProvider);
    }
  }

  Future<void> _showAddTeamSheet(BuildContext context, WidgetRef ref) async {
    final draft = await showTeamFormSheet(context);
    if (draft == null) return;
    try {
      await ref.read(teamsControllerProvider.notifier).create(draft);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not create team: $e')));
    }
  }
}

enum _TeamsMenuAction { toggleHidden, refresh }

class _SearchField extends ConsumerStatefulWidget {
  const _SearchField();

  @override
  ConsumerState<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends ConsumerState<_SearchField> {
  late final TextEditingController _ctl;

  @override
  void initState() {
    super.initState();
    _ctl = TextEditingController(text: ref.read(teamsSearchQueryProvider));
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: T.fillSoft,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          const Icon(Icons.search, size: 16, color: T.ink3),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _ctl,
              onChanged: (v) =>
                  ref.read(teamsSearchQueryProvider.notifier).state = v,
              decoration: const InputDecoration(
                hintText: 'Search teams',
                hintStyle: TextStyle(color: T.ink3, fontSize: 13),
                border: InputBorder.none,
                isCollapsed: true,
                contentPadding: EdgeInsets.zero,
              ),
              style: const TextStyle(color: T.ink, fontSize: 13),
            ),
          ),
          if (_ctl.text.isNotEmpty)
            GestureDetector(
              onTap: () {
                _ctl.clear();
                ref.read(teamsSearchQueryProvider.notifier).state = '';
              },
              child: const Icon(Icons.close, size: 16, color: T.ink3),
            ),
        ],
      ),
    );
  }
}

class _SportFilterChips extends ConsumerWidget {
  const _SportFilterChips();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sports = ref.watch(availableSportsProvider);
    final selected = ref.watch(teamsSportFilterProvider);
    final entries = <String?>[null, ...sports]; // null = "All"

    return ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      itemCount: entries.length,
      separatorBuilder: (_, _) => const SizedBox(width: 6),
      itemBuilder: (_, i) {
        final s = entries[i];
        final active = s == selected;
        return GestureDetector(
          onTap: () => ref.read(teamsSportFilterProvider.notifier).state = s,
          child: WfChip(label: s ?? 'All', active: active),
        );
      },
    );
  }
}

class _NoTeamsYet extends StatelessWidget {
  const _NoTeamsYet({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
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
              child: const Icon(Icons.groups_outlined, color: T.ink2, size: 28),
            ),
            const SizedBox(height: 16),
            const Text(
              'No teams yet',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: T.ink,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Teams live on the camera. Add your first one to start '
              'recording matches.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: T.ink2, height: 1.4),
            ),
            const SizedBox(height: 18),
            WfButton(
              label: '+ Add a new team',
              variant: WfButtonVariant.primary,
              full: true,
              onPressed: onAdd,
            ),
          ],
        ),
      ),
    );
  }
}

class _TeamsErrorState extends StatelessWidget {
  const _TeamsErrorState({required this.error});
  final Object error;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, color: T.ink2, size: 32),
            const SizedBox(height: 12),
            const Text(
              'Could not reach the camera',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: T.ink,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '$error',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11, color: T.ink3),
            ),
          ],
        ),
      ),
    );
  }
}

class _TeamsList extends ConsumerWidget {
  const _TeamsList({required this.teams, required this.totalShown});
  final List<TeamRecord> teams;
  final int totalShown;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (teams.isEmpty) {
      return const Center(child: WfNote('No teams match your filters'));
    }
    return Column(
      children: [
        WfSection(
          'Your teams · $totalShown',
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
        ),
        Expanded(
          child: ListView.separated(
            padding: EdgeInsets.zero,
            itemCount: teams.length,
            separatorBuilder: (_, _) => const Divider(height: 1, color: T.rule),
            itemBuilder: (context, i) => _SwipeableTeamRow(team: teams[i]),
          ),
        ),
      ],
    );
  }
}

/// Wraps a team row with swipe-to-hide (left → right) and swipe-to-delete
/// (right → left). Delete prompts a confirmation; hide is reversible from
/// the snackbar action so it's safe to fire-and-forget.
class _SwipeableTeamRow extends ConsumerWidget {
  const _SwipeableTeamRow({required this.team});
  final TeamRecord team;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Dismissible(
      key: ValueKey('team-${team.id}'),
      background: _swipeBg(
        align: Alignment.centerLeft,
        color: T.fillMid,
        icon: team.hidden ? Icons.visibility : Icons.visibility_off,
        label: team.hidden ? 'Unhide' : 'Hide',
        textColor: T.ink,
      ),
      secondaryBackground: _swipeBg(
        align: Alignment.centerRight,
        color: T.danger,
        icon: Icons.delete_outline,
        label: 'Delete',
        textColor: T.dangerInk,
      ),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          // Hide / unhide — apply directly, no confirmation.
          await ref
              .read(teamsControllerProvider.notifier)
              .setHidden(team.id, hidden: !team.hidden);
          return false; // keep the row in place; the list will rebuild
        }
        // endToStart → delete with confirmation.
        return _confirmDelete(context, team);
      },
      onDismissed: (_) async {
        try {
          await ref.read(teamsControllerProvider.notifier).delete(team.id);
        } catch (e) {
          if (!context.mounted) return;
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Could not delete team: $e')));
        }
      },
      child: _TeamRow(team: team),
    );
  }

  static Widget _swipeBg({
    required AlignmentGeometry align,
    required Color color,
    required IconData icon,
    required String label,
    required Color textColor,
  }) {
    return Container(
      color: color,
      alignment: align,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: textColor, size: 18),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: textColor,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}

Future<bool> _confirmDelete(BuildContext context, TeamRecord team) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: T.surface,
      title: const Text('Delete team?'),
      content: Text(
        '${team.name} and its match history will be removed from the camera. '
        'Recordings on the camera storage are not affected.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text(
            'Delete',
            style: TextStyle(color: T.danger, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
  return ok ?? false;
}

class _TeamRow extends StatelessWidget {
  const _TeamRow({required this.team});
  final TeamRecord team;

  @override
  Widget build(BuildContext context) {
    final dim = team.hidden;
    return Material(
      color: T.bg,
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => TeamDetailPage(teamId: team.id)),
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Opacity(
            opacity: dim ? 0.55 : 1,
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: T.fillSoft,
                    shape: BoxShape.circle,
                    border: Border.all(color: T.hair),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    team.shortName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      color: T.ink2,
                    ),
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
                              team.name,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14,
                                color: T.ink,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          if (dim) ...[
                            const SizedBox(width: 8),
                            const WfChip(label: 'Hidden'),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${team.roster.length} players · ${team.sport}',
                        style: const TextStyle(fontSize: 11, color: T.ink2),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
