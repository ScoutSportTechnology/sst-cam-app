import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/app_data.dart';
import '../theme/tokens.dart';
import '../widgets/wf_card.dart';
import 'video_team_matches_page.dart';

class VideoPage extends ConsumerWidget {
  const VideoPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(libraryProvider);
    final teams = ref.watch(teamsControllerProvider).valueOrNull ?? const [];

    final byTeam =
        <String, ({int matches, int clips, int sizeMb, String date})>{};
    for (final m in library) {
      final cur =
          byTeam[m.teamId] ?? (matches: 0, clips: 0, sizeMb: 0, date: m.date);
      byTeam[m.teamId] = (
        matches: cur.matches + 1,
        clips: cur.clips + m.events.length + 1,
        sizeMb: cur.sizeMb + m.fullSizeMb + m.highlightSizeMb,
        date: m.date,
      );
    }

    final tiles = teams.where((t) => byTeam.containsKey(t.id)).toList();

    return Scaffold(
      backgroundColor: T.bg,
      appBar: AppBar(
        title: const Text('Library'),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 8),
            child: Icon(Icons.more_vert),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(14, 12, 14, 6),
            child: WfNote('Pick a team'),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: tiles.length,
              itemBuilder: (context, i) {
                final t = tiles[i];
                final stats = byTeam[t.id]!;
                return _TeamLibraryRow(
                  team: t,
                  matches: stats.matches,
                  clips: stats.clips,
                  sizeGb: stats.sizeMb / 1024,
                  recent: stats.date,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _TeamLibraryRow extends StatelessWidget {
  const _TeamLibraryRow({
    required this.team,
    required this.matches,
    required this.clips,
    required this.sizeGb,
    required this.recent,
  });
  final TeamRecord team;
  final int matches;
  final int clips;
  final double sizeGb;
  final String recent;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => VideoTeamMatchesPage(teamId: team.id),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: const Border(
          bottom: BorderSide(color: T.rule),
        ).toBoxDecoration(),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: T.fillMid,
                borderRadius: BorderRadius.circular(20),
              ),
              alignment: Alignment.center,
              child: Text(
                team.initials,
                style: const TextStyle(
                  fontFamily: T.mono,
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
                  Text(
                    team.shortName,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: T.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$matches matches · $clips clips',
                    style: const TextStyle(fontSize: 11, color: T.ink2),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${sizeGb.toStringAsFixed(1)} GB',
                  style: const TextStyle(
                    fontFamily: T.mono,
                    fontSize: 11,
                    color: T.ink2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  recent,
                  style: const TextStyle(fontSize: 10, color: T.ink3),
                ),
              ],
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right, color: T.ink3, size: 18),
          ],
        ),
      ),
    );
  }
}

extension on Border {
  BoxDecoration toBoxDecoration() => BoxDecoration(border: this);
}
