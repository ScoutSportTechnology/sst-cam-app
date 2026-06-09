import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../teams_state.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/wf_card.dart';
import '../../../core/widgets/wf_chip.dart';
import '../../../features/camera/camera_state.dart'
    show activeTabProvider, AppTab;

class TeamMatchesTab extends ConsumerWidget {
  const TeamMatchesTab({
    super.key,
    required this.teamId,
    required this.matches,
  });
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
                      ? const Icon(
                          Icons.event_outlined,
                          color: T.accent,
                          size: 18,
                        )
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
