import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'video_state.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/wf_button.dart';
import '../../core/widgets/wf_chip.dart';
import '../../core/widgets/wf_filter_bar.dart';
import '../discovery/discovery_page.dart';
import 'playback/video_match_detail_page.dart';
import '../camera/camera_state.dart';
import '../../core/ble/ble_providers.dart';
import '../../core/models/device.dart';

class VideoPage extends ConsumerWidget {
  const VideoPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final libraryAsync = ref.watch(libraryProvider);
    final filteredMatches = ref.watch(filteredLibraryMatchesProvider);

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
            padding: EdgeInsets.fromLTRB(14, 10, 14, 6),
            child: _LibrarySearchField(),
          ),
          const SizedBox(height: 32, child: _LibraryFilterBar()),
          const SizedBox(height: 4),
          Expanded(
            child: libraryAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              // ignore: avoid_types_on_closure_parameters
              error: (Object err, StackTrace st) => const Center(
                child: Text(
                  'Could not load library',
                  style: TextStyle(color: T.ink2, fontSize: 13),
                ),
              ),
              data: (allMatches) {
                if (allMatches.isEmpty) {
                  return const _NoVideosEmptyState();
                }
                if (filteredMatches.isEmpty) {
                  return _EmptyFilterState(
                    onClear: () {
                      ref.read(librarySportFilterProvider.notifier).state =
                          null;
                      ref.read(libraryTeamFilterProvider.notifier).state = null;
                      ref.read(librarySearchQueryProvider.notifier).state = '';
                    },
                  );
                }
                return ListView.builder(
                  padding: EdgeInsets.zero,
                  itemCount: filteredMatches.length,
                  itemBuilder: (context, i) {
                    return _MatchCard(match: filteredMatches[i]);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Search field
// ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------
// Filter bar — horizontal row of picker buttons, one per filter type
// ---------------------------------------------------------------------------

class _LibraryFilterBar extends ConsumerWidget {
  const _LibraryFilterBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sport = ref.watch(librarySportFilterProvider);
    final sports = ref.watch(availableLibrarySportsProvider);
    final team = ref.watch(libraryTeamFilterProvider);
    final teams = ref.watch(filteredLibraryTeamsProvider);

    return WfFilterBar(
      filters: [
        FilterSpec(
          label: 'All sports',
          options: sports,
          selected: sport,
          onSelect: (v) =>
              ref.read(librarySportFilterProvider.notifier).state = v,
        ),
        FilterSpec(
          label: 'All teams',
          options: teams.map((t) => t.name).toList(),
          selected: team,
          onSelect: (v) =>
              ref.read(libraryTeamFilterProvider.notifier).state = v,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Match card
// ---------------------------------------------------------------------------

class _MatchCard extends ConsumerWidget {
  const _MatchCard({required this.match});
  final LibraryMatch match;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final onDeviceAsync = ref.watch(isOnDeviceProvider(match.id));

    return InkWell(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => VideoMatchDetailPage(matchId: match.id),
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
            // Left: circular avatar badge with team shortName
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: T.fillMid,
                borderRadius: BorderRadius.circular(20),
              ),
              alignment: Alignment.center,
              child: Text(
                match.teamShortName,
                style: const TextStyle(
                  fontFamily: T.mono,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  color: T.ink2,
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Title and subtitle
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${match.teamName} vs ${_stripVsPrefix(match.opponent)}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: T.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    match.result.isEmpty
                        ? '${match.date} · Upcoming'
                        : '${match.date} · ${match.result}',
                    style: const TextStyle(fontSize: 11, color: T.ink2),
                  ),
                ],
              ),
            ),
            // Right: on-device indicator
            onDeviceAsync.when(
              loading: () => const SizedBox(width: 48, height: 16),
              // ignore: avoid_types_on_closure_parameters
              error: (Object err, StackTrace st) =>
                  const SizedBox(width: 48, height: 16),
              data: (onDevice) => onDevice
                  ? const WfChip(label: 'On device', active: true)
                  : const SizedBox.shrink(),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, color: T.ink3, size: 18),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Empty states
// ---------------------------------------------------------------------------

class _EmptyFilterState extends StatelessWidget {
  const _EmptyFilterState({required this.onClear});
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'No matches for this filter',
              style: TextStyle(fontSize: 15, color: T.ink2),
            ),
            const SizedBox(height: 12),
            TextButton(onPressed: onClear, child: const Text('Clear filters')),
          ],
        ),
      ),
    );
  }
}

class _NoVideosEmptyState extends ConsumerWidget {
  const _NoVideosEmptyState();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeId = ref.watch(activeCameraIdProvider);
    final connected =
        activeId != null &&
        ref.watch(connectionStateProvider(activeId)).valueOrNull ==
            CameraConnectionState.connected;
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
            Text(
              connected
                  ? 'Record a match to start building your library.'
                  : 'Connect your camera, then record a match to build your library.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: T.ink2, height: 1.4),
            ),
            const SizedBox(height: 18),
            // The CTA reflects connection state: a connected camera shouldn't be
            // told to "Connect camera" (bug #9) — route it to record instead.
            if (connected)
              WfButton(
                label: 'Go to Match',
                variant: WfButtonVariant.primary,
                full: true,
                onPressed: () => ref.read(activeTabProvider.notifier).state = 2,
              )
            else
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

/// Strip a leading "vs " prefix from an opponent string so the card title
/// "${teamName} vs ${opponent}" never produces a double "vs vs".
/// Legacy DB rows may have the opponent stored as "vs Eastfield FC".
String _stripVsPrefix(String opponent) {
  if (opponent.startsWith('vs ')) return opponent.substring(3);
  if (opponent.startsWith('VS ')) return opponent.substring(3);
  return opponent;
}
