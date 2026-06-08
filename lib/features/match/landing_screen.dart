// Landing screen — upcoming matches across all teams. Mirrors the visual
// language of the Teams page (avatar circle + name/sport sub).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/wf_button.dart';
import '../../core/widgets/wf_card.dart';
import '../../core/widgets/wf_filter_bar.dart';
import '../teams/matches/team_match_form_sheet.dart';
import '../teams/teams_state.dart' show teamsControllerProvider, TeamRecord;
import 'match_state.dart';

class LandingScreen extends ConsumerWidget {
  const LandingScreen({super.key, required this.onSelect});
  final ValueChanged<UpcomingMatch> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(upcomingMatchesProvider);
    return Scaffold(
      backgroundColor: T.bg,
      appBar: AppBar(title: const Text('Match')),
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(14, 10, 14, 10),
            child: _MatchSearchField(),
          ),
          const SizedBox(height: 32, child: _MatchFilterBar()),
          Expanded(
            child: async.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Could not load matches: $e',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: T.ink2, fontSize: 12),
                  ),
                ),
              ),
              data: (matches) {
                final filtered = ref.watch(filteredUpcomingMatchesProvider);
                if (matches.isEmpty) {
                  return _NoUpcomingState(
                    onSchedule: () => _schedule(context, ref),
                  );
                }
                if (filtered.isEmpty) {
                  return const Center(
                    child: WfNote('No matches match your filters'),
                  );
                }
                return Column(
                  children: [
                    WfSection(
                      'Upcoming · ${filtered.length}',
                      padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
                    ),
                    Expanded(
                      child: ListView.separated(
                        padding: EdgeInsets.zero,
                        itemCount: filtered.length,
                        separatorBuilder: (_, _) =>
                            const Divider(height: 1, color: T.rule),
                        itemBuilder: (_, i) => _UpcomingRow(
                          match: filtered[i],
                          onTap: () => onSelect(filtered[i]),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: null,
        onPressed: () => _schedule(context, ref),
        backgroundColor: T.accent,
        foregroundColor: T.accentInk,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(4)),
        ),
        child: const Icon(Icons.add, size: 28),
      ),
    );
  }

  Future<void> _schedule(BuildContext context, WidgetRef ref) async {
    final teams =
        ref.read(teamsControllerProvider).valueOrNull ?? const <TeamRecord>[];
    final visible = teams.where((t) => !t.hidden).toList();
    if (visible.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add a team in the Teams tab before scheduling.'),
        ),
      );
      return;
    }
    final team = await _pickTeam(context, visible);
    if (team == null || !context.mounted) return;
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

// ---------------------------------------------------------------------------
// SEARCH FIELD
// ---------------------------------------------------------------------------

class _MatchSearchField extends ConsumerStatefulWidget {
  const _MatchSearchField();

  @override
  ConsumerState<_MatchSearchField> createState() => _MatchSearchFieldState();
}

class _MatchSearchFieldState extends ConsumerState<_MatchSearchField> {
  late final TextEditingController _ctl;

  @override
  void initState() {
    super.initState();
    _ctl = TextEditingController(text: ref.read(upcomingSearchQueryProvider));
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
                  ref.read(upcomingSearchQueryProvider.notifier).state = v,
              decoration: const InputDecoration(
                hintText: 'Search matches',
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
                ref.read(upcomingSearchQueryProvider.notifier).state = '';
              },
              child: const Icon(Icons.close, size: 16, color: T.ink3),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// FILTER BAR
// ---------------------------------------------------------------------------

class _MatchFilterBar extends ConsumerWidget {
  const _MatchFilterBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final matches = ref.watch(upcomingMatchesProvider).valueOrNull ?? const [];
    final sport = ref.watch(upcomingMatchSportFilterProvider);
    final team = ref.watch(upcomingMatchTeamFilterProvider);

    final sports = matches.map((m) => m.team.sport).toSet().toList()..sort();
    final sportFiltered = sport == null
        ? matches
        : matches.where((m) => m.team.sport == sport).toList();
    final teams = sportFiltered.map((m) => m.team.name).toSet().toList()
      ..sort();

    return WfFilterBar(
      filters: [
        FilterSpec(
          label: 'All sports',
          options: sports,
          selected: sport,
          onSelect: (v) {
            ref.read(upcomingMatchSportFilterProvider.notifier).state = v;
            ref.read(upcomingMatchTeamFilterProvider.notifier).state = null;
          },
        ),
        FilterSpec(
          label: 'All teams',
          options: teams,
          selected: team,
          onSelect: (v) =>
              ref.read(upcomingMatchTeamFilterProvider.notifier).state = v,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// PICK TEAM BOTTOM SHEET (top-level helper, landing only)
// ---------------------------------------------------------------------------

Future<TeamRecord?> _pickTeam(BuildContext context, List<TeamRecord> teams) {
  return showModalBottomSheet<TeamRecord>(
    context: context,
    backgroundColor: T.bg,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 12, 0, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: T.fillMid,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Pick a team',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: T.ink,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            for (final t in teams)
              InkWell(
                onTap: () => Navigator.of(ctx).pop(t),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      _AvatarCircle(label: t.shortName),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              t.name,
                              style: const TextStyle(
                                fontSize: 14,
                                color: T.ink,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              t.sport,
                              style: const TextStyle(
                                fontSize: 11,
                                color: T.ink2,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right, color: T.ink3, size: 18),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// AVATAR CIRCLE
// ---------------------------------------------------------------------------

class _AvatarCircle extends StatelessWidget {
  const _AvatarCircle({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: T.fillSoft,
        shape: BoxShape.circle,
        border: Border.all(color: T.hair),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: const TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 12,
          color: T.ink2,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// UPCOMING ROW
// ---------------------------------------------------------------------------

class _UpcomingRow extends StatelessWidget {
  const _UpcomingRow({required this.match, required this.onTap});
  final UpcomingMatch match;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final m = match.match;
    final t = match.team;
    final mins = m.periodLengthSeconds ~/ 60;
    final format = m.numPeriods > 0 && mins > 0
        ? '${m.numPeriods} × $mins min · ${t.sport}'
        : t.sport;
    return Material(
      color: T.bg,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              _AvatarCircle(label: t.shortName),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${t.name} ${m.opponent}',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        color: T.ink,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${m.date} · $format',
                      style: const TextStyle(fontSize: 11, color: T.ink2),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: T.ink3, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// NO UPCOMING STATE
// ---------------------------------------------------------------------------

class _NoUpcomingState extends StatelessWidget {
  const _NoUpcomingState({required this.onSchedule});
  final VoidCallback onSchedule;

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
                Icons.event_available_outlined,
                color: T.ink2,
                size: 28,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'No upcoming matches',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: T.ink,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Schedule a match to set it up and run it from this tab. '
              'Past matches are in the Video and Teams tabs.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: T.ink2, height: 1.4),
            ),
            const SizedBox(height: 18),
            WfButton(
              label: 'Schedule a match',
              variant: WfButtonVariant.primary,
              full: true,
              onPressed: onSchedule,
            ),
          ],
        ),
      ),
    );
  }
}
