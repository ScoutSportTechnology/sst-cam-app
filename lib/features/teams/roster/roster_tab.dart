import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../teams_state.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/wf_card.dart';
import '../../../core/widgets/wf_chip.dart';
import 'player_form_sheet.dart';

class RosterTab extends ConsumerWidget {
  const RosterTab({super.key, required this.team});
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
