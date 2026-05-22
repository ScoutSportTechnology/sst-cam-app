import 'package:flutter/material.dart';

import '../teams_state.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/wf_card.dart';

class StatsTab extends StatelessWidget {
  const StatsTab({
    super.key,
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

extension on Border {
  BoxDecoration toBoxDecoration() => BoxDecoration(border: this);
}
