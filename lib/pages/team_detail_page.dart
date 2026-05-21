import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/app_data.dart';
import '../core/theme/tokens.dart';
import '../core/widgets/wf_button.dart';
import '../core/widgets/wf_card.dart';
import '../core/widgets/wf_chip.dart';
import 'player_form_sheet.dart';
import 'team_form_sheet.dart';
import 'team_match_form_sheet.dart';

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
                _RosterTab(team: team),
                _MatchesTab(teamId: team.id, matches: matches),
                _StatsTab(team: team, matches: matches, stats: stats),
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

extension on Border {
  BoxDecoration toBoxDecoration() => BoxDecoration(border: this);
}

class _RosterTab extends ConsumerWidget {
  const _RosterTab({required this.team});
  final TeamRecord team;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (team.roster.isEmpty) {
      return const Center(child: WfNote('No players yet — tap + to add one'));
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: team.roster.length,
      separatorBuilder: (_, _) => const Divider(height: 1, color: T.rule),
      itemBuilder: (context, i) {
        final p = team.roster[i];
        return Dismissible(
          key: ValueKey('player-${team.id}-${p.number}'),
          direction: DismissDirection.endToStart,
          background: Container(
            color: T.danger,
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.delete_outline, color: T.dangerInk, size: 18),
                SizedBox(width: 8),
                Text(
                  'Remove',
                  style: TextStyle(
                    color: T.dangerInk,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                  ),
                ),
              ],
            ),
          ),
          onDismissed: (_) async {
            try {
              await ref
                  .read(teamsControllerProvider.notifier)
                  .removePlayer(team.id, p.number);
            } catch (e) {
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Could not remove player: $e')),
              );
            }
          },
          child: InkWell(
            onTap: () => _editPlayer(context, ref, p),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      border: Border.all(color: T.ring, width: 1.4),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      p.number.toString().padLeft(2, '0'),
                      style: const TextStyle(
                        fontFamily: T.mono,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: T.ink,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          p.name,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: T.ink,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          p.position,
                          style: const TextStyle(fontSize: 11, color: T.ink2),
                        ),
                      ],
                    ),
                  ),
                  if (p.captain) const WfChip(label: 'C', active: true),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _editPlayer(
    BuildContext context,
    WidgetRef ref,
    Player player,
  ) async {
    final draft = await showPlayerFormSheet(
      context,
      existing: player,
      takenNumbers: team.roster.map((p) => p.number).toSet(),
    );
    if (draft == null) return;
    try {
      await ref
          .read(teamsControllerProvider.notifier)
          .updatePlayer(team.id, player.number, draft);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not update player: $e')));
    }
  }
}

class _MatchesTab extends ConsumerWidget {
  const _MatchesTab({required this.teamId, required this.matches});
  final String teamId;
  final List<TeamMatch> matches;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (matches.isEmpty) {
      return const Center(child: WfNote('No matches yet — tap + to add one'));
    }
    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: matches.length,
      separatorBuilder: (_, _) => const Divider(height: 1, color: T.rule),
      itemBuilder: (context, i) => _MatchRow(
        match: matches[i],
        onDelete: () => ref
            .read(teamsControllerProvider.notifier)
            .removeMatch(teamId, matches[i].id),
        onTap: matches[i].kind == MatchKind.upcoming
            ? () {
                Navigator.of(context).pop();
                ref.read(activeTabProvider.notifier).state = AppTab.match;
              }
            : null,
      ),
    );
  }
}

class _MatchRow extends StatelessWidget {
  const _MatchRow({required this.match, required this.onDelete, this.onTap});
  final TeamMatch match;
  final Future<void> Function() onDelete;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final outcome = match.outcome;
    final color = outcome == 'W'
        ? T.accent
        : outcome == 'L'
        ? T.ink2
        : T.ink;
    final isUpcoming = match.kind == MatchKind.upcoming;
    return Dismissible(
      key: ValueKey('match-${match.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        color: T.danger,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: const Icon(Icons.delete_outline, color: T.dangerInk, size: 18),
      ),
      onDismissed: (_) async {
        try {
          await onDelete();
        } catch (e) {
          if (!context.mounted) return;
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Could not delete match: $e')));
        }
      },
      child: Material(
        color: T.bg,
        child: InkWell(
          onTap: onTap,
          child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                border: Border.all(
                  color: isUpcoming ? T.accent : T.hair,
                  width: 1.4,
                ),
              ),
              alignment: Alignment.center,
              child: isUpcoming
                  ? const Icon(Icons.event_outlined, color: T.accent, size: 18)
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          outcome,
                          style: TextStyle(
                            fontFamily: T.mono,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: color,
                            height: 1,
                          ),
                        ),
                        const SizedBox(height: 2),
                        if (match.result.length > 2)
                          Text(
                            match.result.substring(2),
                            style: const TextStyle(
                              fontFamily: T.mono,
                              fontSize: 9,
                              color: T.ink2,
                              height: 1,
                            ),
                          ),
                      ],
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
                          match.opponent,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: T.ink,
                          ),
                        ),
                      ),
                      if (isUpcoming) ...[
                        const SizedBox(width: 8),
                        const WfChip(label: 'Upcoming', active: true),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isUpcoming
                        ? match.date
                        : '${match.date} · ${match.clips} clips · ${match.sizeMb} MB',
                    style: const TextStyle(fontSize: 11, color: T.ink2),
                  ),
                ],
              ),
            ),
            if (onTap != null)
              const Icon(Icons.chevron_right, color: T.ink3, size: 18),
          ],
        ),
      ),
        ),
      ),
    );
  }
}

class _StatsTab extends StatelessWidget {
  const _StatsTab({
    required this.team,
    required this.matches,
    required this.stats,
  });
  final TeamRecord team;
  final List<TeamMatch> matches;
  final TeamStats stats;

  @override
  Widget build(BuildContext context) {
    if (stats.played == 0) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 32),
          child: WfNote(
            'No played matches yet. Add a past match in the Matches tab '
            'to start collecting stats.',
          ),
        ),
      );
    }

    final totals = <(String, String)>[
      ('Played', '${stats.played}'),
      ('Record', '${stats.wins}–${stats.draws}–${stats.losses}'),
      ('Goals for', '${stats.goalsFor}'),
      ('Goals against', '${stats.goalsAgainst}'),
      ('Clean sheets', '${stats.cleanSheets}'),
      ('Goal diff', '${stats.goalsFor - stats.goalsAgainst}'),
    ];

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        const WfSection('Season totals'),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          child: GridView.count(
            crossAxisCount: 3,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 1.4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: totals
                .map(
                  (e) => WfCard(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        WfNote(e.$1),
                        const SizedBox(height: 4),
                        Text(
                          e.$2,
                          style: const TextStyle(
                            fontFamily: T.mono,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: T.ink,
                            letterSpacing: -0.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        const WfSection('Player leaderboard'),
        if (team.roster.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: WfNote('Add players to see stats')),
          )
        else
          _LeaderboardTable(roster: team.roster),
      ],
    );
  }
}

class _LeaderboardTable extends StatelessWidget {
  const _LeaderboardTable({required this.roster});
  final List<Player> roster;

  @override
  Widget build(BuildContext context) {
    int goals(int n) => (n * 3 % 7);
    int assists(int n) => (n * 2 % 5);
    int mins(int n) => 380 + (n * 17 % 160);

    final headerStyle = const TextStyle(
      fontSize: 10,
      fontWeight: FontWeight.w700,
      color: T.ink2,
      fontFamily: T.mono,
      letterSpacing: 0.5,
    );

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: const Border(
            bottom: BorderSide(color: T.rule),
          ).toBoxDecoration(),
          child: Row(
            children: [
              SizedBox(width: 32, child: Text('#', style: headerStyle)),
              const SizedBox(width: 8),
              Expanded(child: Text('PLAYER', style: headerStyle)),
              SizedBox(
                width: 28,
                child: Text(
                  'G',
                  style: headerStyle,
                  textAlign: TextAlign.right,
                ),
              ),
              SizedBox(
                width: 28,
                child: Text(
                  'A',
                  style: headerStyle,
                  textAlign: TextAlign.right,
                ),
              ),
              SizedBox(
                width: 44,
                child: Text(
                  'MIN',
                  style: headerStyle,
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
        ),
        ...roster.map(
          (p) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: const Border(
              bottom: BorderSide(color: T.rule),
            ).toBoxDecoration(),
            child: Row(
              children: [
                SizedBox(
                  width: 28,
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: T.ring, width: 1.4),
                    ),
                    height: 28,
                    alignment: Alignment.center,
                    child: Text(
                      p.number.toString().padLeft(2, '0'),
                      style: const TextStyle(
                        fontFamily: T.mono,
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                        color: T.ink,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.name,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: T.ink,
                        ),
                      ),
                      WfNote(p.position),
                    ],
                  ),
                ),
                SizedBox(
                  width: 28,
                  child: Text(
                    '${goals(p.number)}',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontFamily: T.mono,
                      fontWeight: FontWeight.w700,
                      color: goals(p.number) > 0 ? T.accent : T.ink2,
                    ),
                  ),
                ),
                SizedBox(
                  width: 28,
                  child: Text(
                    '${assists(p.number)}',
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontFamily: T.mono, color: T.ink2),
                  ),
                ),
                SizedBox(
                  width: 44,
                  child: Text(
                    '${mins(p.number)}',
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontFamily: T.mono, color: T.ink2),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
