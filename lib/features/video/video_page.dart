import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'video_state.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/wf_button.dart';
import '../../core/widgets/wf_chip.dart';
import '../discovery/discovery_page.dart';
import 'playback/video_match_detail_page.dart';

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
          const SizedBox(height: 32, child: _SportFilterRow()),
          const SizedBox(height: 8),
          const SizedBox(height: 32, child: _TeamFilterRow()),
          const SizedBox(height: 4),
          Expanded(
            child: libraryAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
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
                      ref.read(libraryTeamFilterProvider.notifier).state =
                          null;
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
// Sport filter row — "All" chip + picker button
// ---------------------------------------------------------------------------

class _SportFilterRow extends ConsumerWidget {
  const _SportFilterRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sports = ref.watch(availableLibrarySportsProvider);
    final selected = ref.watch(librarySportFilterProvider);

    return Row(
      children: [
        const SizedBox(width: 14),
        GestureDetector(
          onTap: () =>
              ref.read(librarySportFilterProvider.notifier).state = null,
          child: WfChip(label: 'All', active: selected == null),
        ),
        const SizedBox(width: 6),
        _FilterPickerChip(
          label: selected ?? 'All sports',
          active: selected != null,
          onTap: () => showModalBottomSheet<void>(
            context: context,
            backgroundColor: T.panel,
            builder: (sheetCtx) => _OptionPickerSheet(
              options: sports,
              selected: selected,
              onSelect: (value) =>
                  ref.read(librarySportFilterProvider.notifier).state = value,
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Team filter row — "All" chip + picker button
// ---------------------------------------------------------------------------

class _TeamFilterRow extends ConsumerWidget {
  const _TeamFilterRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final teams = ref.watch(filteredLibraryTeamsProvider);
    final selected = ref.watch(libraryTeamFilterProvider);

    return Row(
      children: [
        const SizedBox(width: 14),
        GestureDetector(
          onTap: () =>
              ref.read(libraryTeamFilterProvider.notifier).state = null,
          child: WfChip(label: 'All', active: selected == null),
        ),
        const SizedBox(width: 6),
        _FilterPickerChip(
          label: selected ?? 'All teams',
          active: selected != null,
          onTap: () => showModalBottomSheet<void>(
            context: context,
            backgroundColor: T.panel,
            builder: (sheetCtx) => _OptionPickerSheet(
              options: teams.map((t) => t.name).toList(),
              selected: selected,
              onSelect: (value) =>
                  ref.read(libraryTeamFilterProvider.notifier).state = value,
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Shared: filter picker chip (label + chevron)
// ---------------------------------------------------------------------------

class _FilterPickerChip extends StatelessWidget {
  const _FilterPickerChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = active ? T.accentInk : T.ink2;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: active ? T.accent : T.fillSoft,
          border: Border.all(color: active ? T.accent : T.hair, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: fg,
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(width: 3),
            Icon(Icons.keyboard_arrow_down_rounded, size: 13, color: fg),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared: bottom sheet picker
// ---------------------------------------------------------------------------

class _OptionPickerSheet extends StatelessWidget {
  const _OptionPickerSheet({
    required this.options,
    this.selected,
    required this.onSelect,
  });

  final List<String> options;
  final String? selected;
  final ValueChanged<String?> onSelect;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      minimum: const EdgeInsets.only(bottom: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 10),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: T.fillDark,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          _SheetTile(
            label: 'All',
            checked: selected == null,
            onTap: () {
              onSelect(null);
              Navigator.of(context).pop();
            },
          ),
          ...options.map(
            (opt) => _SheetTile(
              label: opt,
              checked: opt == selected,
              onTap: () {
                onSelect(opt);
                Navigator.of(context).pop();
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SheetTile extends StatelessWidget {
  const _SheetTile({
    required this.label,
    required this.checked,
    required this.onTap,
  });

  final String label;
  final bool checked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  color: checked ? T.accent : T.ink,
                  fontWeight:
                      checked ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
            if (checked) const Icon(Icons.check, color: T.accent, size: 18),
          ],
        ),
      ),
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
            TextButton(
              onPressed: onClear,
              child: const Text('Clear filters'),
            ),
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

/// Strip a leading "vs " prefix from an opponent string so the card title
/// "${teamName} vs ${opponent}" never produces a double "vs vs".
/// Legacy DB rows may have the opponent stored as "vs Eastfield FC".
String _stripVsPrefix(String opponent) {
  if (opponent.startsWith('vs ')) return opponent.substring(3);
  if (opponent.startsWith('VS ')) return opponent.substring(3);
  return opponent;
}
