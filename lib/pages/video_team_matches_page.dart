import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/app_data.dart';
import '../theme/tokens.dart';
import '../widgets/wf_card.dart';
import '../widgets/wf_chip.dart';
import 'video_match_detail_page.dart';

class VideoTeamMatchesPage extends ConsumerWidget {
  const VideoTeamMatchesPage({super.key, required this.teamId});
  final String teamId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final teams = ref.watch(teamsControllerProvider).valueOrNull ?? const [];
    final team = teams.where((t) => t.id == teamId).firstOrNull;
    final matches = (ref.watch(libraryProvider).valueOrNull ?? const [])
        .where((m) => m.teamId == teamId)
        .toList();

    if (team == null) {
      return const Scaffold(body: Center(child: Text('Team not found')));
    }

    final totalSizeGb =
        matches.fold<int>(0, (a, m) => a + m.fullSizeMb) /
        1024;

    return Scaffold(
      backgroundColor: T.bg,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(team.shortName),
            Text(
              '${matches.length} matches · ${totalSizeGb.toStringAsFixed(1)} GB',
              style: const TextStyle(fontSize: 11, color: T.ink2),
            ),
          ],
        ),
      ),
      body: ListView.builder(
        padding: EdgeInsets.zero,
        itemCount: matches.length,
        itemBuilder: (_, i) => _MatchGroup(match: matches[i]),
      ),
    );
  }
}

class _MatchGroup extends StatelessWidget {
  const _MatchGroup({required this.match});
  final LibraryMatch match;

  @override
  Widget build(BuildContext context) {
    final state = match.downloadState;
    final chip = state == 'all-local'
        ? const WfChip(label: '✓ on phone', active: true)
        : state == 'partial'
        ? const WfChip(label: '1 of 2')
        : const WfChip(label: 'on camera');

    return Container(
      decoration: const Border(
        top: BorderSide(color: T.rule),
      ).toBoxDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'vs ${match.opponent}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: T.ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${match.date} · ${match.result}',
                        style: const TextStyle(fontSize: 11, color: T.ink2),
                      ),
                    ],
                  ),
                ),
                chip,
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
            child: Row(
              children: [
                Expanded(
                  child: _Tile(
                    match: match,
                    kind: 'full',
                    label: 'Full game',
                    duration: match.fullDuration,
                    sizeMb: match.fullSizeMb,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _Tile(
                    match: match,
                    kind: 'hi',
                    label: 'Highlights',
                    duration: '${match.events.length} events',
                    sizeMb: 0,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.match,
    required this.kind,
    required this.label,
    required this.duration,
    required this.sizeMb,
  });
  final LibraryMatch match;
  final String kind;
  final String label;
  final String duration;
  final int sizeMb;

  @override
  Widget build(BuildContext context) {
    final isHi = kind == 'hi';
    final sizeStr = sizeMb >= 1024
        ? '${(sizeMb / 1024).toStringAsFixed(1)} GB'
        : '$sizeMb MB';

    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => VideoMatchDetailPage(matchId: match.id),
          ),
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(
              fit: StackFit.expand,
              children: [
                const ThumbPlaceholder(),
                if (isHi) CustomPaint(painter: _HighlightStripePainter()),
                Positioned(
                  top: 4,
                  left: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    color: isHi ? T.accent : T.bg.withValues(alpha: 0.82),
                    child: Text(
                      isHi ? '★ HI' : 'FULL',
                      style: TextStyle(
                        fontFamily: T.mono,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                        color: isHi ? T.accentInk : T.ink,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 4,
                  right: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: T.bg.withValues(alpha: 0.82),
                      border: Border.all(color: T.hair),
                    ),
                    child: Text(
                      duration,
                      style: const TextStyle(
                        fontFamily: T.mono,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: T.ink,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: T.ink,
            ),
          ),
          WfNote(sizeStr),
        ],
      ),
    );
  }
}

class _HighlightStripePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = T.accentSoft
      ..strokeWidth = 6;
    for (double x = -size.height; x < size.width; x += 14) {
      canvas.drawLine(Offset(x, 0), Offset(x + size.height, size.height), p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

extension on Border {
  BoxDecoration toBoxDecoration() => BoxDecoration(border: this);
}
