import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'teams_state.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/borders.dart';
import '../../core/widgets/wf_button.dart';
import '../../core/widgets/wf_card.dart';
import '../../core/widgets/wf_chip.dart';
import 'roster/player_form_sheet.dart';
import 'team_form_sheet.dart';
import 'matches/team_match_form_sheet.dart';
import 'roster/roster_tab.dart';
import 'matches/team_matches_tab.dart';
import 'stats/stats_tab.dart';

class TeamDetailPage extends ConsumerStatefulWidget {
  const TeamDetailPage({super.key, required this.teamId});
  final String teamId;

  @override
  ConsumerState<TeamDetailPage> createState() => _TeamDetailPageState();
}

class _TeamDetailPageState extends ConsumerState<TeamDetailPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this)
      ..addListener(() {
        if (!_tabs.indexIsChanging) setState(() {});
      });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final teams = ref.watch(teamsControllerProvider).valueOrNull ?? const [];
    final team = teams.where((t) => t.id == widget.teamId).firstOrNull;
    if (team == null) {
      return const Scaffold(body: Center(child: Text('Team not found')));
    }
    final matches =
        ref.watch(teamMatchesProvider(widget.teamId)).valueOrNull ?? const [];
    final stats = TeamStats.fromMatches(matches);

    return Scaffold(
      backgroundColor: T.bg,
      appBar: AppBar(
        title: Text(team.name, overflow: TextOverflow.ellipsis),
        actions: [
          PopupMenuButton<_DetailMenuAction>(
            icon: const Icon(Icons.more_vert),
            onSelected: (a) => _onMenu(context, ref, team, a),
            itemBuilder: (_) => [
              PopupMenuItem(
                value: _DetailMenuAction.toggleHidden,
                child: Text(team.hidden ? 'Unhide team' : 'Hide team'),
              ),
              const PopupMenuItem(
                value: _DetailMenuAction.delete,
                child: Text('Delete team', style: TextStyle(color: T.danger)),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          _TeamHeader(
            team: team,
            stats: stats,
            onEdit: () => _onEdit(context, ref, team),
          ),
          TabBar(
            controller: _tabs,
            tabs: const [
              Tab(text: 'Roster'),
              Tab(text: 'Matches'),
              Tab(text: 'Stats'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                RosterTab(team: team),
                TeamMatchesTab(teamId: team.id, matches: matches),
                StatsTab(team: team, matches: matches, stats: stats),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: switch (_tabs.index) {
        0 => _AddFab(
          tooltip: 'Add player',
          onPressed: () => _addPlayer(context, ref, team),
        ),
        1 => _AddFab(
          tooltip: 'Add match',
          onPressed: () => _addMatch(context, ref, team),
        ),
        _ => null,
      },
    );
  }

  Future<void> _onMenu(
    BuildContext context,
    WidgetRef ref,
    TeamRecord team,
    _DetailMenuAction action,
  ) async {
    final notifier = ref.read(teamsControllerProvider.notifier);
    switch (action) {
      case _DetailMenuAction.toggleHidden:
        try {
          await notifier.setHidden(team.id, hidden: !team.hidden);
        } catch (e) {
          if (!context.mounted) return;
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Could not update: $e')));
        }
      case _DetailMenuAction.delete:
        final ok = await _confirmDelete(context, team);
        if (!ok) return;
        if (!context.mounted) return;
        try {
          await notifier.delete(team.id);
          if (!context.mounted) return;
          Navigator.of(context).pop();
        } catch (e) {
          if (!context.mounted) return;
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Could not delete: $e')));
        }
    }
  }

  Future<void> _onEdit(
    BuildContext context,
    WidgetRef ref,
    TeamRecord team,
  ) async {
    final draft = await showTeamFormSheet(context, existing: team);
    if (draft == null) return;
    try {
      await ref.read(teamsControllerProvider.notifier).edit(draft);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not save changes: $e')));
    }
  }

  Future<void> _addPlayer(
    BuildContext context,
    WidgetRef ref,
    TeamRecord team,
  ) async {
    final draft = await showPlayerFormSheet(
      context,
      takenNumbers: team.roster.map((p) => p.number).toSet(),
    );
    if (draft == null) return;
    try {
      await ref
          .read(teamsControllerProvider.notifier)
          .addPlayer(team.id, draft);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not add player: $e')));
    }
  }

  Future<void> _addMatch(
    BuildContext context,
    WidgetRef ref,
    TeamRecord team,
  ) async {
    final draft = await showTeamMatchFormSheet(context, team: team);
    if (draft == null) return;
    try {
      await ref.read(teamsControllerProvider.notifier).addMatch(team.id, draft);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not add match: $e')));
    }
  }
}

enum _DetailMenuAction { toggleHidden, delete }

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

class _AddFab extends StatelessWidget {
  const _AddFab({required this.tooltip, required this.onPressed});
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      heroTag: null,
      onPressed: onPressed,
      tooltip: tooltip,
      backgroundColor: T.accent,
      foregroundColor: T.accentInk,
      elevation: 0,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(4)),
      ),
      child: const Icon(Icons.add, size: 28),
    );
  }
}

class _TeamHeader extends StatelessWidget {
  const _TeamHeader({
    required this.team,
    required this.stats,
    required this.onEdit,
  });
  final TeamRecord team;
  final TeamStats stats;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: const Border(
        bottom: BorderSide(color: T.rule),
      ).toBoxDecoration(),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
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
                fontSize: 16,
                color: T.ink,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const WfNote('This season'),
                    if (team.hidden) ...[
                      const SizedBox(width: 8),
                      const WfChip(label: 'Hidden'),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  stats.played == 0
                      ? 'No matches yet'
                      : '${stats.played} played · ${stats.wins}W ${stats.draws}D ${stats.losses}L',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: T.ink,
                  ),
                ),
              ],
            ),
          ),
          WfButton(label: 'Edit', size: WfButtonSize.sm, onPressed: onEdit),
        ],
      ),
    );
  }
}
