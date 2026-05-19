import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/app_data.dart';
import '../theme/tokens.dart';
import '../widgets/wf_button.dart';
import '../widgets/wf_card.dart';
import '../widgets/wf_chip.dart';
import 'discovery_page.dart';
import 'video_team_matches_page.dart';

class VideoPage extends ConsumerWidget {
  const VideoPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Phone-side only: the app cannot enumerate camera storage when the
    // device isn't connected, so the library shows only matches with at
    // least one clip already on the phone (`all-local` or `partial`).
    final library = (ref.watch(libraryProvider).valueOrNull ?? const [])
        .where((m) => m.downloadState != 'remote')
        .toList();

    // Build stats map — same as before, used for row rendering.
    final byTeam =
        <String, ({int matches, int clips, int sizeMb, String date})>{};
    for (final m in library) {
      final cur =
          byTeam[m.teamId] ?? (matches: 0, clips: 0, sizeMb: 0, date: m.date);
      byTeam[m.teamId] = (
        matches: cur.matches + 1,
        clips: cur.clips + m.events.length + 1,
        sizeMb: cur.sizeMb + m.fullSizeMb,
        date: m.date,
      );
    }

    // Use filtered provider instead of computing tiles manually.
    final filteredTiles = ref.watch(filteredLibraryTeamsProvider);

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
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(14, 10, 14, 10),
            child: _LibrarySearchField(),
          ),
          const SizedBox(height: 32, child: _LibrarySportFilterChips()),
          if (filteredTiles.isNotEmpty)
            WfSection(
              'Library · ${filteredTiles.length}',
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
            ),
          Expanded(
            child: filteredTiles.isEmpty
                ? const _NoVideosEmptyState()
                : ListView.builder(
                    itemCount: filteredTiles.length,
                    itemBuilder: (context, i) {
                      final t = filteredTiles[i];
                      final stats = byTeam[t.id];
                      if (stats == null) return const SizedBox.shrink();
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

class _LibrarySearchField extends ConsumerStatefulWidget {
  const _LibrarySearchField();

  @override
  ConsumerState<_LibrarySearchField> createState() =>
      _LibrarySearchFieldState();
}

class _LibrarySearchFieldState extends ConsumerState<_LibrarySearchField> {
  late final TextEditingController _ctl;

  @override
  void initState() {
    super.initState();
    _ctl = TextEditingController(text: ref.read(librarySearchQueryProvider));
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
                  ref.read(librarySearchQueryProvider.notifier).state = v,
              decoration: const InputDecoration(
                hintText: 'Search library',
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
                ref.read(librarySearchQueryProvider.notifier).state = '';
              },
              child: const Icon(Icons.close, size: 16, color: T.ink3),
            ),
        ],
      ),
    );
  }
}

class _LibrarySportFilterChips extends ConsumerWidget {
  const _LibrarySportFilterChips();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sports = ref.watch(availableLibrarySportsProvider);
    final selected = ref.watch(librarySportFilterProvider);
    final entries = <String?>[null, ...sports];

    return ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      itemCount: entries.length,
      separatorBuilder: (context, index) => const SizedBox(width: 6),
      itemBuilder: (_, i) {
        final s = entries[i];
        final active = s == selected;
        return GestureDetector(
          onTap: () => ref.read(librarySportFilterProvider.notifier).state = s,
          child: WfChip(label: s ?? 'All', active: active),
        );
      },
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
                team.shortName,
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

class _NoVideosEmptyState extends StatelessWidget {
  const _NoVideosEmptyState();

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
              child: const Icon(
                Icons.video_library_outlined,
                color: T.ink2,
                size: 28,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'No videos on this phone',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: T.ink,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Record a match to start building your library.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: T.ink2, height: 1.4),
            ),
            const SizedBox(height: 18),
            WfButton(
              label: 'Connect camera',
              variant: WfButtonVariant.primary,
              full: true,
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const DiscoveryPage()),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

extension on Border {
  BoxDecoration toBoxDecoration() => BoxDecoration(border: this);
}
