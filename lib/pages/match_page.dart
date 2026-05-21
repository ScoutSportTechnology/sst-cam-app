import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/command.dart';
import '../models/device.dart';
import '../state/app_data.dart';
import '../state/ble_providers.dart';
import '../theme/tokens.dart';
import '../widgets/indicators.dart';
import '../widgets/live_preview_view.dart';
import '../widgets/wf_button.dart';
import '../widgets/wf_card.dart';
import '../widgets/wf_chip.dart';
import 'team_match_form_sheet.dart';

/// The Match tab routes between Landing → Setup → Session based on user
/// selection. The Session screen unifies the old pre-match and live views
/// since the user can run pre-game / post-game recording independently of
/// the period timer. While the match is active it drives a 1 Hz tick into
/// the controller.
class MatchPage extends ConsumerStatefulWidget {
  const MatchPage({super.key});

  @override
  ConsumerState<MatchPage> createState() => _MatchPageState();
}

class _MatchPageState extends ConsumerState<MatchPage> {
  Timer? _tick;

  /// The upcoming match the user has chosen to set up / play. Null = on the
  /// landing screen. Cleared by `_leave()` when the user pops out of an
  /// ended match.
  UpcomingMatch? _selected;

  /// True once the user has tapped "Start match" on the setup screen.
  /// Drives the Setup → Session transition.
  bool _setupConfirmed = false;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      ref.read(liveMatchProvider.notifier).tick();
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  void _select(UpcomingMatch up) {
    ref.read(liveMatchProvider.notifier).loadFromUpcoming(up);
    setState(() {
      _selected = up;
      _setupConfirmed = false;
    });
  }

  /// Pop out of the live session back to landing. When the match ended
  /// naturally we also remove the upcoming entry from the camera so it
  /// no longer shows on the landing list.
  ///
  /// Order matters: we remove the camera-side entry FIRST and only then
  /// flip the local state. Otherwise the landing rebuild can race with
  /// the (mock-delayed) removal and briefly render the just-played match.
  Future<void> _leave({required bool wasEnded}) async {
    final selected = _selected;
    if (wasEnded && selected != null) {
      try {
        await ref
            .read(teamsControllerProvider.notifier)
            .removeMatch(selected.team.id, selected.match.id);
      } catch (_) {
        // Non-fatal: the match may already be gone or the camera may
        // have disconnected. We still want to leave the session.
      }
    }
    if (!mounted) return;
    ref.read(liveMatchProvider.notifier).reset();
    setState(() {
      _selected = null;
      _setupConfirmed = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selected;

    // Live state owns the truth about whether the user is mid-session.
    // If a match is loaded and we've passed setup, render the session
    // screen for any non-idle phase OR the pre-game (idle) phase too.
    if (selected != null && _setupConfirmed) {
      return _SessionScreen(
        match: selected,
        onLeave: () => _leave(
          wasEnded: ref.read(liveMatchProvider).phase == MatchPhase.ended,
        ),
      );
    }

    if (selected == null) {
      return _LandingScreen(onSelect: _select);
    }

    return _SetupScreen(
      match: selected,
      onBack: () => setState(() => _selected = null),
      onStart: () => setState(() => _setupConfirmed = true),
    );
  }
}

// ---------------------------------------------------------------------------
// LANDING — upcoming matches across all teams. Mirrors the visual language
// of the Teams page (avatar circle + name/sport sub).
// ---------------------------------------------------------------------------

class _LandingScreen extends ConsumerWidget {
  const _LandingScreen({required this.onSelect});
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
          const SizedBox(height: 32, child: _MatchSportFilterChips()),
          const SizedBox(height: 6),
          const SizedBox(height: 32, child: _MatchTeamFilterChips()),
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
      floatingActionButton: FloatingActionButton(heroTag: null,
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
// SEARCH FIELD — mirrors _SearchField from teams_page.dart
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
    _ctl = TextEditingController(
      text: ref.read(upcomingSearchQueryProvider),
    );
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
// SPORT FILTER CHIPS — mirrors _SportFilterChips from teams_page.dart
// ---------------------------------------------------------------------------

class _MatchSportFilterChips extends ConsumerWidget {
  const _MatchSportFilterChips();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final matches =
        ref.watch(upcomingMatchesProvider).valueOrNull ?? const [];
    final sports = matches.map((m) => m.team.sport).toSet().toList()..sort();
    final selected = ref.watch(upcomingMatchSportFilterProvider);
    final entries = <String?>[null, ...sports];

    return ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      itemCount: entries.length,
      separatorBuilder: (_, _) => const SizedBox(width: 6),
      itemBuilder: (_, i) {
        final s = entries[i];
        final active = s == selected;
        return GestureDetector(
          onTap: () {
            ref.read(upcomingMatchSportFilterProvider.notifier).state = s;
            ref.read(upcomingMatchTeamFilterProvider.notifier).state = null;
          },
          child: WfChip(label: s ?? 'All', active: active),
        );
      },
    );
  }
}

class _MatchTeamFilterChips extends ConsumerWidget {
  const _MatchTeamFilterChips();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final matches = ref.watch(upcomingMatchesProvider).valueOrNull ?? const [];
    final sport = ref.watch(upcomingMatchSportFilterProvider);
    final filtered = sport == null
        ? matches
        : matches.where((m) => m.team.sport == sport).toList();
    final teams = filtered.map((m) => m.team.name).toSet().toList()..sort();
    final selected = ref.watch(upcomingMatchTeamFilterProvider);
    final entries = <String?>[null, ...teams];

    return ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      itemCount: entries.length,
      separatorBuilder: (_, _) => const SizedBox(width: 6),
      itemBuilder: (_, i) {
        final t = entries[i];
        final active = t == selected;
        return GestureDetector(
          onTap: () =>
              ref.read(upcomingMatchTeamFilterProvider.notifier).state = t,
          child: WfChip(label: t ?? 'All teams', active: active),
        );
      },
    );
  }
}

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

// ---------------------------------------------------------------------------
// SETUP — review a scheduled match before going live
// ---------------------------------------------------------------------------

enum _Quality {
  hd720p30('720p · 30 fps'),
  fhd1080p30('1080p · 30 fps'),
  fhd1080p60('1080p · 60 fps'),
  uhd4k30('4K · 30 fps');

  const _Quality(this.label);
  final String label;
}

enum _StreamMethod {
  youtube('YouTube Live', 'NR U14 channel · 1080p'),
  instagram('Instagram Live', 'Connected account · 720p'),
  local('Local network', 'mDNS · for parents on WiFi'),
  custom('Custom RTMP', '');

  const _StreamMethod(this.label, this.defaultSub);
  final String label;
  final String defaultSub;
}

class _SetupScreen extends ConsumerStatefulWidget {
  const _SetupScreen({
    required this.match,
    required this.onBack,
    required this.onStart,
  });
  final UpcomingMatch match;
  final VoidCallback onBack;
  final VoidCallback onStart;

  @override
  ConsumerState<_SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<_SetupScreen> {
  _Quality _quality = _Quality.fhd1080p30;
  // null = Custom (use _customPeriods + _customMinutes from match init).
  SportPreset? _preset;
  int _customPeriods = 2;
  int _customPeriodSeconds = 35 * 60;
  bool _initialized = false;

  // Streaming destinations.
  final Set<_StreamMethod> _streamMethods = {};
  String _customRtmpUrl = '';

  // Session push state (U9).
  bool _pushing = false;
  String? _pushError;
  // Stable match UUID for the current setup session. Generated on first tap
  // and reused on retry so the camera always sees the same UUID.
  String? _matchUuid;

  static const _uuid = Uuid();

  @override
  Widget build(BuildContext context) {
    final team = widget.match.team;
    final m = widget.match.match;
    final presets = ref.watch(sportPresetsForSportProvider(team.sport));
    final activeId = ref.watch(activeCameraIdProvider);
    final connected =
        activeId != null &&
        ref.watch(connectionStateProvider(activeId)).valueOrNull ==
            CameraConnectionState.connected;

    if (!_initialized) {
      _customPeriods = m.numPeriods > 0 ? m.numPeriods : 2;
      _customPeriodSeconds = m.periodLengthSeconds > 0
          ? m.periodLengthSeconds
          : 35 * 60;
      // Preselect a preset that matches the scheduled time config, if any.
      _preset = presets
          .where(
            (p) =>
                p.numPeriods == _customPeriods &&
                p.periodLengthSeconds == _customPeriodSeconds,
          )
          .firstOrNull;
      _initialized = true;
    }

    final periods = _preset?.numPeriods ?? _customPeriods;
    final periodMinutes =
        (_preset?.periodLengthSeconds ?? _customPeriodSeconds) ~/ 60;
    final formatLabel = _preset != null
        ? _stripSportPrefix(_preset!.name, team.sport)
        : 'Custom';

    return Scaffold(
      backgroundColor: T.bg,
      appBar: AppBar(
        title: const Text('Match setup'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: widget.onBack,
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          const WfSection('Match'),
          _RowItem(
            leading: _AvatarCircle(label: team.shortName),
            title: team.name,
            subtitle: 'Home',
          ),
          const Divider(height: 1, color: T.rule),
          _RowItem(
            leading: const Icon(Icons.shield_outlined),
            title: m.opponent,
            subtitle: 'Away · ${m.date}',
          ),
          const WfSection('Format'),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
            child: WfCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  _ValueRow(label: 'Sport', value: team.sport),
                  const Divider(height: 1, color: T.rule),
                  _ValueRow(
                    label: 'Format',
                    value: '$formatLabel · $periods × $periodMinutes min',
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final p in presets)
                  GestureDetector(
                    onTap: () => setState(() => _preset = p),
                    child: WfChip(
                      label: _stripSportPrefix(p.name, team.sport),
                      active: _preset?.id == p.id,
                    ),
                  ),
                GestureDetector(
                  onTap: () => _editCustom(context),
                  child: WfChip(label: 'Custom…', active: _preset == null),
                ),
              ],
            ),
          ),
          const WfSection('Recording'),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
            child: WfCard(
              padding: EdgeInsets.zero,
              child: _DropdownRow<_Quality>(
                label: 'Quality',
                value: _quality,
                items: _Quality.values,
                labelOf: (q) => q.label,
                onChanged: (v) => setState(() => _quality = v),
              ),
            ),
          ),
          const WfSection('Streaming'),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
            child: WfCard(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const WfNote('DESTINATIONS'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final m in _StreamMethod.values)
                        GestureDetector(
                          onTap: () => _toggleStreamMethod(m),
                          child: WfChip(
                            label:
                                m == _StreamMethod.custom &&
                                    _customRtmpUrl.isNotEmpty
                                ? 'Custom RTMP · configured'
                                : m.label,
                            active: _streamMethods.contains(m),
                          ),
                        ),
                    ],
                  ),
                  if (_streamMethods.isEmpty) ...[
                    const SizedBox(height: 8),
                    const WfNote(
                      'Pick one or more destinations to stream to. You can '
                      'still record without streaming.',
                    ),
                  ],
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 4),
            child: WfButton(
              label: _pushing ? 'Configuring camera…' : 'Start match',
              variant: WfButtonVariant.primary,
              size: WfButtonSize.lg,
              full: true,
              onPressed: (_pushing || !connected)
                  ? null
                  : () => _startMatch(
                      periods,
                      _preset?.periodLengthSeconds ?? _customPeriodSeconds,
                    ),
            ),
          ),
          if (!connected)
            const Padding(
              padding: EdgeInsets.fromLTRB(14, 0, 14, 8),
              child: Text(
                'Connect a camera to start the match.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: T.ink2),
              ),
            ),
          if (_pushing)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Center(child: LinearProgressIndicator()),
            ),
          if (_pushError != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _pushError!,
                    style: const TextStyle(color: T.danger, fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  WfButton(
                    label: 'Retry',
                    variant: WfButtonVariant.outline,
                    full: true,
                    onPressed: connected
                        ? () => _startMatch(
                            periods,
                            _preset?.periodLengthSeconds ?? _customPeriodSeconds,
                          )
                        : null,
                  ),
                ],
              ),
            )
          else
            const SizedBox(height: 14),
        ],
      ),
    );
  }

  // Fix 17: UUID v4 format regex used to validate UUIDs before interpolating
  // them into output paths.
  static final _uuidRegex = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  );

  void _validateUuid(String uuid, String name) {
    if (!_uuidRegex.hasMatch(uuid)) {
      throw ArgumentError('$name is not a valid UUID: $uuid');
    }
  }

  Future<void> _startMatch(int periods, int periodLengthSeconds) async {
    final deviceId = ref.read(activeCameraIdProvider);
    if (deviceId == null) return;

    final userUuid = ref.read(activeUserProvider);
    if (userUuid == null) return;

    // Generate a stable match UUID on first tap; reuse on retry.
    _matchUuid ??= _uuid.v4();
    final matchUuid = _matchUuid!;

    final rtmpUrl =
        _streamMethods.contains(_StreamMethod.custom) &&
            _customRtmpUrl.isNotEmpty
        ? _customRtmpUrl
        : null;

    final config = PushSessionConfig(
      matchUuid: matchUuid,
      userUuid: userUuid,
      sport: widget.match.team.sport.toLowerCase(),
      numPeriods: periods,
      periodLengthSeconds: periodLengthSeconds,
      rtmpUrl: rtmpUrl,
      videoOutputPath: '/data/video/$userUuid/$matchUuid/',
      thumbnailOutputPath: '/data/thumbnail/$userUuid/$matchUuid/',
    );

    setState(() {
      _pushing = true;
      _pushError = null;
    });

    try {
      // Fix 17: Validate matchUuid against the UUID v4 format before
      // interpolating it into the camera filesystem path. matchUuid is
      // generated above via Uuid().v4(), so this guard should never fire in
      // practice — it defends against accidental code changes that replace the
      // UUID generator with unvalidated input.
      _validateUuid(matchUuid, 'matchUuid');

      final ble = ref.read(bleServiceProvider);
      await ble.pushSessionConfig(deviceId, config);
      if (!mounted) return;
      setState(() {
        _pushing = false;
      });
      widget.onStart();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _pushing = false;
        _pushError = 'Failed to configure camera. Check connection and retry.';
      });
    }
  }

  Future<void> _toggleStreamMethod(_StreamMethod method) async {
    final isOn = _streamMethods.contains(method);
    if (method == _StreamMethod.custom) {
      final url = await _showCustomRtmpModal(context, initial: _customRtmpUrl);
      if (url == null) return;
      setState(() {
        if (url.isEmpty) {
          _streamMethods.remove(_StreamMethod.custom);
          _customRtmpUrl = '';
        } else {
          _streamMethods.add(_StreamMethod.custom);
          _customRtmpUrl = url;
        }
      });
      return;
    }
    setState(() {
      if (isOn) {
        _streamMethods.remove(method);
      } else {
        _streamMethods.add(method);
      }
    });
  }

  Future<void> _editCustom(BuildContext context) async {
    final result = await showDialog<(int, int)>(
      context: context,
      builder: (ctx) => _CustomFormatDialog(
        initialPeriods: _customPeriods,
        initialMinutes: _customPeriodSeconds ~/ 60,
      ),
    );
    if (result == null) return;
    setState(() {
      _preset = null;
      _customPeriods = result.$1;
      _customPeriodSeconds = result.$2 * 60;
    });
  }
}

/// Drop a leading `<sport> · ` from a preset display name when shown in
/// a context where the sport is already obvious.
String _stripSportPrefix(String name, String sport) {
  final pref = '$sport · ';
  return name.startsWith(pref) ? name.substring(pref.length) : name;
}

class _ValueRow extends StatelessWidget {
  const _ValueRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: T.ink,
              ),
            ),
          ),
          Text(value, style: const TextStyle(fontSize: 12, color: T.ink2)),
        ],
      ),
    );
  }
}

class _DropdownRow<V> extends StatelessWidget {
  const _DropdownRow({
    required this.label,
    required this.value,
    required this.items,
    required this.labelOf,
    required this.onChanged,
  });
  final String label;
  final V value;
  final List<V> items;
  final String Function(V) labelOf;
  final ValueChanged<V> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                color: T.ink,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          DropdownButtonHideUnderline(
            child: DropdownButton<V>(
              value: value,
              isDense: true,
              dropdownColor: T.surface,
              style: const TextStyle(fontSize: 13, color: T.ink),
              icon: const Icon(Icons.expand_more, size: 16, color: T.ink2),
              items: [
                for (final item in items)
                  DropdownMenuItem(value: item, child: Text(labelOf(item))),
              ],
              onChanged: (v) {
                if (v != null) onChanged(v);
              },
            ),
          ),
        ],
      ),
    );
  }
}

Future<String?> _showCustomRtmpModal(
  BuildContext context, {
  required String initial,
}) {
  final controller = TextEditingController(text: initial);
  String? error;
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: T.bg,
    isScrollControlled: true,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setSt) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
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
                  const SizedBox(height: 16),
                  const Text(
                    'Custom RTMP',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: T.ink,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Full RTMP URL including stream key. Stored on the camera, '
                    'never logged by the app.',
                    style: TextStyle(fontSize: 11, color: T.ink2, height: 1.4),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    decoration: BoxDecoration(
                      color: T.fillSoft,
                      border: Border.all(color: T.hair),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: TextField(
                      controller: controller,
                      autofocus: true,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        hintText: 'rtmp://stream.example.com/app/key',
                        hintStyle: TextStyle(color: T.ink3, fontSize: 13),
                        border: InputBorder.none,
                        isCollapsed: true,
                        contentPadding: EdgeInsets.symmetric(vertical: 12),
                      ),
                      style: const TextStyle(color: T.ink, fontSize: 13),
                    ),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      error!,
                      style: const TextStyle(color: T.danger, fontSize: 12),
                    ),
                  ],
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      if (initial.isNotEmpty)
                        Expanded(
                          child: WfButton(
                            label: 'Remove',
                            variant: WfButtonVariant.danger,
                            onPressed: () => Navigator.of(ctx).pop(''),
                          ),
                        )
                      else
                        Expanded(
                          child: WfButton(
                            label: 'Cancel',
                            onPressed: () => Navigator.of(ctx).pop(),
                          ),
                        ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: WfButton(
                          label: 'Save',
                          variant: WfButtonVariant.primary,
                          onPressed: () {
                            final url = controller.text.trim();
                            if (!url.startsWith('rtmp://') &&
                                !url.startsWith('rtmps://')) {
                              setSt(
                                () => error =
                                    'URL must start with rtmp:// or rtmps://',
                              );
                              return;
                            }
                            Navigator.of(ctx).pop(url);
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _CustomFormatDialog extends StatefulWidget {
  const _CustomFormatDialog({
    required this.initialPeriods,
    required this.initialMinutes,
  });
  final int initialPeriods;
  final int initialMinutes;

  @override
  State<_CustomFormatDialog> createState() => _CustomFormatDialogState();
}

class _CustomFormatDialogState extends State<_CustomFormatDialog> {
  late final TextEditingController _periods = TextEditingController(
    text: '${widget.initialPeriods}',
  );
  late final TextEditingController _minutes = TextEditingController(
    text: '${widget.initialMinutes}',
  );
  String? _error;

  @override
  void dispose() {
    _periods.dispose();
    _minutes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: T.surface,
      title: const Text('Custom format'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _periods,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Periods'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _minutes,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Period length (min)',
                  ),
                ),
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: const TextStyle(color: T.danger, fontSize: 12),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () {
            final p = int.tryParse(_periods.text.trim());
            final m = int.tryParse(_minutes.text.trim());
            if (p == null || p < 1 || p > 9) {
              setState(() => _error = 'Periods must be 1–9');
              return;
            }
            if (m == null || m < 1 || m > 120) {
              setState(() => _error = 'Period length must be 1–120 min');
              return;
            }
            Navigator.of(context).pop((p, m));
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// SESSION — covers pre-game, period-active, period-break and ended phases.
// Recording / streaming controls are independent of the period timer so the
// user can record before kickoff or after the final whistle.
// ---------------------------------------------------------------------------

class _SessionScreen extends ConsumerWidget {
  const _SessionScreen({required this.match, required this.onLeave});
  final UpcomingMatch match;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(liveMatchProvider);
    final ctl = ref.read(liveMatchProvider.notifier);

    final activeId = ref.watch(activeCameraIdProvider);
    final connected = activeId != null &&
        ref.watch(connectionStateProvider(activeId)).valueOrNull ==
            CameraConnectionState.connected;

    final isEnded = state.phase == MatchPhase.ended;
    final isPeriodActive = state.phase == MatchPhase.period;

    final indicator = switch (state.rec) {
      RecState.recording => 'REC',
      RecState.paused => 'REC PAUSE',
      RecState.idle =>
        isEnded
            ? 'FT'
            : isPeriodActive
            ? 'LIVE'
            : 'READY',
    };
    final indicatorColor = state.rec == RecState.recording
        ? T.accent
        : (isEnded ? T.ink2 : T.ink2);

    return Scaffold(
      backgroundColor: T.bg,
      body: SafeArea(
        child: Column(
          children: [
            _TopBar(
              indicator: indicator,
              indicatorColor: indicatorColor,
              clock: state.clockText,
              onBack: (isEnded || state.phase == MatchPhase.idle) ? onLeave : null,
            ),
            _LiveThumb(
              homeLabel: state.homeName,
              awayLabel: state.awayName,
              homeScore: state.scoreHome,
              awayScore: state.scoreAway,
              phaseLabel: state.phaseLabel,
              clock: state.clockText,
              isLive: isPeriodActive,
            ),
            _PrimaryActionRow(
              state: state,
              onMarkEvent: isPeriodActive
                  ? () => _showEventSheet(context, ref)
                  : null,
              onKickoff: () => _kickoff(context, ctl, state),
              onEndPeriod: ctl.endPeriod,
              onStartNextPeriod: () => ctl.startPeriod(),
              onEndMatch: () => _confirmEnd(context, ctl, state),
            ),
            if (isEnded) const _EndedBanner(),
            const Divider(height: 1, color: T.rule),
            const WfSection(
              'Event log',
              padding: EdgeInsets.fromLTRB(14, 10, 14, 4),
            ),
            Expanded(
              child: _buildEventLog(state),
            ),
            _BottomControls(
              state: state,
              onTimerTap: ctl.toggleTimer,
              onRecToggle: connected ? ctl.toggleRecPause : null,
              onRecStop: connected ? ctl.stopRecording : null,
              onStreamToggle:
                  connected ? () => ctl.setStreaming(!state.streaming) : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEventLog(LiveMatchState state) {
    final visible = state.events.where((e) => e.kind != 'phase').toList();
    if (visible.isEmpty) return const Center(child: WfNote('No events yet'));
    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: visible.length,
      separatorBuilder: (_, _) => const Divider(height: 1, color: T.rule),
      itemBuilder: (_, i) => _EventLogRow(e: visible[i]),
    );
  }

  Future<void> _kickoff(
    BuildContext context,
    LiveMatchController ctl,
    LiveMatchState state,
  ) async {
    // Kickoff prompt — only on the very first period. Subsequent periods
    // continue with whatever recording / streaming state is active.
    if (state.currentPeriod != 0) {
      ctl.startPeriod();
      return;
    }
    final recAlreadyOn = state.rec != RecState.idle;
    final streamAlreadyOn = state.streaming;
    if (recAlreadyOn && streamAlreadyOn) {
      // Both are already running — nothing to ask, just start the period.
      ctl.startPeriod();
      return;
    }
    final choice = await _showStartPrompt(
      context,
      askRecord: !recAlreadyOn,
      askStream: !streamAlreadyOn,
    );
    if (choice == null) return;
    ctl.startPeriod(startRecording: choice.$1, startStreaming: choice.$2);
  }

  Future<void> _confirmEnd(
    BuildContext context,
    LiveMatchController ctl,
    LiveMatchState state,
  ) async {
    final recOn = state.rec != RecState.idle;
    final streamOn = state.streaming;
    if (!recOn && !streamOn) {
      // Nothing is running — no toggles to ask about, just end.
      ctl.endMatch(stopRecording: false, stopStreaming: false);
      return;
    }
    final choice = await _showEndPrompt(
      context,
      askStopRec: recOn,
      askStopStream: streamOn,
    );
    if (choice == null) return;
    ctl.endMatch(
      stopRecording: choice.$1 ?? false,
      stopStreaming: choice.$2 ?? false,
    );
  }

  void _showEventSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: T.bg,
      isScrollControlled: true,
      barrierColor: T.barrierColor,
      builder: (_) => _EventSheet(
        homeTeamId: match.team.id,
        onSave: (type, team, jersey) {
          ref
              .read(liveMatchProvider.notifier)
              .addEvent(type: type, teamLabel: team, jersey: jersey);
        },
      ),
    );
  }
}

/// Returns `(startRecording?, startStreaming?)` or null on cancel. Each
/// element is null when the corresponding control wasn't shown (the thing
/// was already running before kickoff), so the caller can leave that
/// state untouched.
Future<(bool?, bool?)?> _showStartPrompt(
  BuildContext context, {
  required bool askRecord,
  required bool askStream,
}) {
  // Defaults when shown: recording opts in (the natural action at
  // kickoff), streaming stays opt-in.
  var record = true;
  var stream = false;
  final subtitle = askRecord && askStream
      ? 'Pick what to start with the match timer. Both can be paused or '
            'stopped independently while the match runs.'
      : askRecord
      ? 'Streaming is already running. Want to also start recording with '
            'the match timer?'
      : 'Recording is already running. Want to also start streaming with '
            'the match timer?';
  return showModalBottomSheet<(bool?, bool?)>(
    context: context,
    backgroundColor: T.bg,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSt) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
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
              const SizedBox(height: 16),
              const Text(
                'Kickoff',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: T.ink,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 11,
                  color: T.ink2,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 14),
              if (askRecord)
                _ToggleRow(
                  label: 'Start recording',
                  value: record,
                  onChanged: (v) => setSt(() => record = v),
                ),
              if (askRecord && askStream)
                const Divider(height: 1, color: T.rule),
              if (askStream)
                _ToggleRow(
                  label: 'Start streaming',
                  value: stream,
                  onChanged: (v) => setSt(() => stream = v),
                ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: WfButton(
                      label: 'Cancel',
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: WfButton(
                      label: 'Start match',
                      variant: WfButtonVariant.primary,
                      onPressed: () => Navigator.of(ctx).pop((
                        askRecord ? record : null,
                        askStream ? stream : null,
                      )),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Returns `(stopRecording?, stopStreaming?)` or null on cancel. Each
/// element is null when the corresponding control wasn't shown (the thing
/// wasn't running when the match ended), so the caller can leave that
/// state untouched.
Future<(bool?, bool?)?> _showEndPrompt(
  BuildContext context, {
  required bool askStopRec,
  required bool askStopStream,
}) {
  // Defaults when shown: stop everything that's running. The user can
  // untoggle to keep capturing post-game footage.
  var stopRec = true;
  var stopStream = true;
  final subtitle = askStopRec && askStopStream
      ? 'The match timer ends. Recording and streaming can keep running '
            'for post-game footage if you leave them on.'
      : askStopRec
      ? 'The match timer ends. Recording can keep running for post-game '
            'footage if you leave it on.'
      : 'The match timer ends. Streaming can keep running for post-game '
            'broadcast if you leave it on.';
  return showModalBottomSheet<(bool?, bool?)>(
    context: context,
    backgroundColor: T.bg,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSt) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
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
              const SizedBox(height: 16),
              const Text(
                'End match',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: T.ink,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 11,
                  color: T.ink2,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 14),
              if (askStopRec)
                _ToggleRow(
                  label: 'Also stop recording',
                  value: stopRec,
                  onChanged: (v) => setSt(() => stopRec = v),
                ),
              if (askStopRec && askStopStream)
                const Divider(height: 1, color: T.rule),
              if (askStopStream)
                _ToggleRow(
                  label: 'Also stop streaming',
                  value: stopStream,
                  onChanged: (v) => setSt(() => stopStream = v),
                ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: WfButton(
                      label: 'Cancel',
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: WfButton(
                      label: 'End match',
                      variant: WfButtonVariant.danger,
                      onPressed: () => Navigator.of(ctx).pop((
                        askStopRec ? stopRec : null,
                        askStopStream ? stopStream : null,
                      )),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _PrimaryActionRow extends StatelessWidget {
  const _PrimaryActionRow({
    required this.state,
    required this.onMarkEvent,
    required this.onKickoff,
    required this.onEndPeriod,
    required this.onStartNextPeriod,
    required this.onEndMatch,
  });
  final LiveMatchState state;
  final VoidCallback? onMarkEvent;
  final VoidCallback onKickoff;
  final VoidCallback onEndPeriod;
  final VoidCallback onStartNextPeriod;
  final VoidCallback onEndMatch;

  @override
  Widget build(BuildContext context) {
    // Right-side button changes by phase:
    //   idle              → "Kickoff"
    //   period            → "End period N"
    //   periodBreak (mid) → "Start period N+1"
    //   periodBreak (end) → "End match"
    //   ended             → no action button (left side becomes summary)
    final WfButton phaseButton;
    switch (state.phase) {
      case MatchPhase.idle:
        phaseButton = WfButton(
          label: 'Kickoff',
          variant: WfButtonVariant.primary,
          size: WfButtonSize.lg,
          full: true,
          onPressed: onKickoff,
        );
      case MatchPhase.period:
        phaseButton = WfButton(
          label: state.isLastPeriod
              ? 'End period ${state.currentPeriod}'
              : 'End period ${state.currentPeriod}',
          variant: WfButtonVariant.danger,
          size: WfButtonSize.lg,
          full: true,
          onPressed: onEndPeriod,
        );
      case MatchPhase.periodBreak:
        phaseButton = state.awaitingEndOfMatch
            ? WfButton(
                label: 'End match',
                variant: WfButtonVariant.danger,
                size: WfButtonSize.lg,
                full: true,
                onPressed: onEndMatch,
              )
            : WfButton(
                label: 'Start period ${state.currentPeriod + 1}',
                variant: WfButtonVariant.primary,
                size: WfButtonSize.lg,
                full: true,
                onPressed: onStartNextPeriod,
              );
      case MatchPhase.ended:
        phaseButton = const WfButton(
          label: 'Match ended',
          variant: WfButtonVariant.outline,
          size: WfButtonSize.lg,
          full: true,
        );
    }

    return Padding(
      padding: const EdgeInsets.all(10),
      child: Row(
        children: [
          Expanded(
            child: WfButton(
              label: 'Mark event',
              variant: onMarkEvent != null
                  ? WfButtonVariant.primary
                  : WfButtonVariant.outline,
              size: WfButtonSize.lg,
              leading: const _Square(color: T.accentInk),
              onPressed: onMarkEvent,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: phaseButton),
        ],
      ),
    );
  }
}

class _EndedBanner extends StatelessWidget {
  const _EndedBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: T.accentSoft,
        border: Border.all(color: T.accent, width: 1),
      ),
      child: const Text(
        'Match ended · tap back to return to upcoming',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: T.accent,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _BottomControls extends StatelessWidget {
  const _BottomControls({
    required this.state,
    required this.onTimerTap,
    required this.onRecToggle,
    required this.onRecStop,
    required this.onStreamToggle,
  });

  final LiveMatchState state;
  final VoidCallback onTimerTap;
  final VoidCallback? onRecToggle;
  final VoidCallback? onRecStop;
  final VoidCallback? onStreamToggle;

  @override
  Widget build(BuildContext context) {
    final timerEnabled = state.phase == MatchPhase.period;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: const Border(
        top: BorderSide(color: T.rule),
      ).toBoxDecoration(),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _ControlGroup(
                  label: 'TIMER',
                  value: state.clockText,
                  body: WfButton(
                    label: state.timer == MatchTimer.running
                        ? 'Pause'
                        : 'Resume',
                    leading: state.timer == MatchTimer.running
                        ? const _PauseGlyph()
                        : const _PlayGlyph(),
                    full: true,
                    onPressed: timerEnabled ? onTimerTap : null,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ControlGroup(
                  label: 'RECORDING',
                  labelColor: state.rec == RecState.recording
                      ? T.accent
                      : T.ink2,
                  dotColor: state.rec == RecState.recording ? T.accent : null,
                  body: Row(
                    children: [
                      Expanded(
                        child: WfButton(
                          label: state.rec == RecState.recording
                              ? 'Pause'
                              : state.rec == RecState.paused
                              ? 'Resume'
                              : 'Record',
                          leading: state.rec == RecState.recording
                              ? const _PauseGlyph()
                              : const _Dot(color: T.danger),
                          onPressed: onRecToggle,
                          full: true,
                        ),
                      ),
                      const SizedBox(width: 6),
                      WfButton(
                        label: 'Stop',
                        variant: WfButtonVariant.danger,
                        leading: const _Square(color: T.dangerInk),
                        onPressed: state.rec == RecState.idle
                            ? null
                            : onRecStop,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _ControlGroup(
            label: 'STREAMING',
            labelColor: state.streaming ? T.accent : T.ink2,
            dotColor: state.streaming ? T.accent : null,
            body: WfButton(
              label: state.streaming ? 'Stop streaming' : 'Start streaming',
              variant: state.streaming
                  ? WfButtonVariant.danger
                  : WfButtonVariant.outline,
              full: true,
              onPressed: onStreamToggle,
            ),
          ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.indicator,
    required this.indicatorColor,
    required this.clock,
    this.onBack,
  });
  final String indicator;
  final Color indicatorColor;
  final String clock;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const Border(
        bottom: BorderSide(color: T.rule),
      ).toBoxDecoration(),
      child: Row(
        children: [
          if (onBack != null)
            GestureDetector(
              onTap: onBack,
              child: const Padding(
                padding: EdgeInsets.only(right: 12),
                child: Icon(Icons.arrow_back, size: 20, color: T.ink),
              ),
            ),
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: indicator == 'READY' || indicator == 'FT'
                  ? Colors.transparent
                  : indicatorColor,
              border: Border.all(color: indicatorColor, width: 1.5),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            indicator,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: indicatorColor,
              letterSpacing: 0.6,
            ),
          ),
          const Spacer(),
          Text(
            clock,
            style: const TextStyle(
              fontFamily: T.mono,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: T.ink,
            ),
          ),
          const Spacer(),
          const BatteryIndicator(level: 0.78, size: 11),
          const SizedBox(width: 4),
          const Text('78%', style: TextStyle(fontSize: 10, color: T.ink2)),
        ],
      ),
    );
  }
}

class _LiveThumb extends ConsumerWidget {
  const _LiveThumb({
    required this.homeLabel,
    required this.awayLabel,
    required this.homeScore,
    required this.awayScore,
    required this.phaseLabel,
    required this.clock,
    required this.isLive,
  });
  final String homeLabel;
  final String awayLabel;
  final int homeScore;
  final int awayScore;
  final String phaseLabel;
  final String clock;
  final bool isLive;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeId = ref.watch(activeCameraIdProvider);
    return Stack(
      children: [
        LivePreviewView(
          deviceId: activeId,
          label: isLive ? 'LIVE PREVIEW' : 'PREVIEW',
        ),
        Positioned(
          left: 8,
          right: 8,
          bottom: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: T.bg.withValues(alpha: 0.85),
              border: Border.all(color: T.hair),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _ScoreBlock(label: homeLabel, score: homeScore),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    '$phaseLabel · $clock',
                    style: const TextStyle(
                      fontFamily: T.mono,
                      fontSize: 10,
                      color: T.ink2,
                    ),
                  ),
                ),
                Expanded(
                  child: _ScoreBlock(label: awayLabel, score: awayScore),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ScoreBlock extends StatelessWidget {
  const _ScoreBlock({required this.label, required this.score});
  final String label;
  final int score;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 9,
            color: T.ink2,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '$score',
          style: const TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w700,
            fontFamily: T.mono,
            color: T.ink,
            height: 1,
          ),
        ),
      ],
    );
  }
}

class _EventLogRow extends StatelessWidget {
  const _EventLogRow({required this.e});
  final LiveEvent e;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            child: Text(
              e.clock,
              style: const TextStyle(
                fontFamily: T.mono,
                fontWeight: FontWeight.w400,
                color: T.ink2,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              e.label,
              style: const TextStyle(fontSize: 12, color: T.ink),
            ),
          ),
          const Text('edit', style: TextStyle(fontSize: 11, color: T.ink2)),
        ],
      ),
    );
  }
}

class _ControlGroup extends StatelessWidget {
  const _ControlGroup({
    required this.label,
    this.value = '',
    required this.body,
    this.labelColor = T.ink2,
    this.dotColor,
  });

  final String label;
  final String value;
  final Widget body;
  final Color labelColor;
  final Color? dotColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      decoration: BoxDecoration(border: Border.all(color: T.rule)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (dotColor != null) ...[
                _Dot(color: dotColor!),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: labelColor,
                  letterSpacing: 0.6,
                ),
              ),
              if (value.isNotEmpty) ...[
                const SizedBox(width: 6),
                Text(
                  value,
                  style: const TextStyle(
                    fontFamily: T.mono,
                    fontSize: 11,
                    color: T.ink2,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          body,
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(5),
      ),
    );
  }
}

class _Square extends StatelessWidget {
  const _Square({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(width: 10, height: 10, color: color);
  }
}

class _PauseGlyph extends StatelessWidget {
  const _PauseGlyph();
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 3, height: 11, color: T.ink),
        const SizedBox(width: 2),
        Container(width: 3, height: 11, color: T.ink),
      ],
    );
  }
}

class _PlayGlyph extends StatelessWidget {
  const _PlayGlyph();
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 9,
      height: 12,
      child: CustomPaint(painter: _PlayPainter()),
    );
  }
}

class _PlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, size.height / 2)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(p, Paint()..color = T.ink);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ---------------------------------------------------------------------------
// Event sheet (2-step: type → team + jersey)
// ---------------------------------------------------------------------------

class _EventSheet extends ConsumerStatefulWidget {
  const _EventSheet({required this.homeTeamId, required this.onSave});
  final String homeTeamId;
  final void Function(String type, String team, String? jersey) onSave;

  @override
  ConsumerState<_EventSheet> createState() => _EventSheetState();
}

class _EventSheetState extends ConsumerState<_EventSheet> {
  static const _types = ['Goal', 'Foul', 'Card', 'Sub', 'Save', 'Other'];

  int _step = 0;
  String _type = '';
  String? _team;
  final _jersey = StringBuffer();
  String? _jerseyDropdownValue;
  bool _showNumberPad = false;

  @override
  Widget build(BuildContext context) {
    final live = ref.watch(liveMatchProvider);
    final allTeams = ref.watch(teamsControllerProvider).valueOrNull ?? const [];
    final homeTeam = allTeams.where((t) => t.id == widget.homeTeamId).firstOrNull;
    final homeRoster = homeTeam?.roster ?? const <Player>[];

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: const BoxDecoration(
          color: T.bg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
          border: Border(top: BorderSide(color: T.hair)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
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
            const SizedBox(height: 14),
            _StepHeader(step: _step, selectedType: _step == 1 ? _type : null),
            const SizedBox(height: 14),
            if (_step == 0) _typePicker() else _teamAndJersey(live, homeRoster),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: WfButton(
                    label: _step == 0 ? 'Cancel' : 'Back',
                    onPressed: _step == 0
                        ? () => Navigator.of(context).pop()
                        : () => setState(() => _step = 0),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: WfButton(
                    label: _step == 0 ? 'Next' : 'Save event',
                    variant: WfButtonVariant.primary,
                    onPressed: _step == 0
                        ? (_type.isEmpty
                              ? null
                              : () => setState(() => _step = 1))
                        : (_team == null ||
                              (_jerseyDropdownValue == 'other' &&
                                  _jersey.isEmpty)
                          ? null
                          : () {
                              final jersey =
                                  (_jerseyDropdownValue != null &&
                                          _jerseyDropdownValue != 'other')
                                      ? _jerseyDropdownValue!
                                      : _jersey.toString();
                              widget.onSave(_type, _team!, jersey);
                              Navigator.of(context).pop();
                            }),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _typePicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'What happened?',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: T.ink,
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(height: 14),
        GridView.count(
          crossAxisCount: 3,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          childAspectRatio: 1.4,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: _types.map((t) {
            final on = t == _type;
            return GestureDetector(
              onTap: () => setState(() => _type = t),
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: on ? T.accent : T.hair, width: 1.4),
                  color: on ? T.accentSoft : T.surface,
                ),
                alignment: Alignment.center,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.bolt_outlined, size: 18, color: T.ink),
                    const SizedBox(height: 4),
                    Text(
                      t,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: T.ink,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _teamAndJersey(LiveMatchState live, List<Player> homeRoster) {
    final isHomeSelected = _team == live.homeName;
    final activeRoster = isHomeSelected ? homeRoster : const <Player>[];
    final hasRoster = activeRoster.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Which team?',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: T.ink,
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _teamCard('HOME', live.homeName, homeRoster)),
            const SizedBox(width: 8),
            Expanded(child: _teamCard('AWAY', live.awayName, const [])),
          ],
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          child: _team == null
              ? const SizedBox.shrink()
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        const Text(
                          'Jersey #',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            color: T.ink,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const WfNote('Optional'),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (hasRoster) ...[
                      // Dropdown always visible when a roster exists.
                      // Selecting "Other…" adds the number pad below; picking
                      // a player back from the dropdown dismisses it.
                      Container(
                        height: 46,
                        decoration: BoxDecoration(
                          border: Border.all(color: T.hair),
                          color: T.surface,
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _jerseyDropdownValue,
                            isExpanded: true,
                            dropdownColor: T.surface,
                            hint: const Text(
                              '—',
                              style: TextStyle(
                                fontFamily: T.mono,
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: T.ink3,
                              ),
                            ),
                            icon: const Icon(
                              Icons.expand_more,
                              size: 18,
                              color: T.ink2,
                            ),
                            style: const TextStyle(
                              fontFamily: T.mono,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: T.ink,
                            ),
                            items: [
                              for (final p in activeRoster)
                                DropdownMenuItem(
                                  value: p.number.toString(),
                                  child: Text('#${p.number}  ${p.name}'),
                                ),
                              DropdownMenuItem(
                                value: 'other',
                                child: Text(
                                  'Other…',
                                  style: TextStyle(
                                    fontFamily: T.mono,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w400,
                                    color: T.ink2,
                                  ),
                                ),
                              ),
                            ],
                            onChanged: (v) => setState(() {
                              _jerseyDropdownValue = v;
                              _showNumberPad = v == 'other';
                              if (v != 'other') _jersey.clear();
                            }),
                          ),
                        ),
                      ),
                      if (_showNumberPad) ...[
                        const SizedBox(height: 8),
                        Container(
                          height: 46,
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          decoration: BoxDecoration(
                            border: Border.all(color: T.hair),
                            color: T.surface,
                          ),
                          child: Row(
                            children: [
                              Text(
                                _jersey.isEmpty ? '—' : _jersey.toString(),
                                style: const TextStyle(
                                  fontFamily: T.mono,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                  color: T.ink,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        _NumberPad(
                          onTap: (k) {
                            setState(() {
                              if (k == '⌫') {
                                if (_jersey.isNotEmpty) {
                                  final s = _jersey.toString();
                                  _jersey
                                    ..clear()
                                    ..write(s.substring(0, s.length - 1));
                                }
                              } else if (k != '—' && _jersey.length < 3) {
                                _jersey.write(k);
                              }
                            });
                          },
                        ),
                      ],
                    ] else ...[
                      // No roster — number pad only.
                      Container(
                        height: 46,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(
                          border: Border.all(color: T.hair),
                          color: T.surface,
                        ),
                        child: Row(
                          children: [
                            Text(
                              _jersey.isEmpty ? '—' : _jersey.toString(),
                              style: const TextStyle(
                                fontFamily: T.mono,
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: T.ink,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      _NumberPad(
                        onTap: (k) {
                          setState(() {
                            if (k == '⌫') {
                              if (_jersey.isNotEmpty) {
                                final s = _jersey.toString();
                                _jersey
                                  ..clear()
                                  ..write(s.substring(0, s.length - 1));
                              }
                            } else if (k != '—' && _jersey.length < 3) {
                              _jersey.write(k);
                            }
                          });
                        },
                      ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }

  Widget _teamCard(String header, String name, List<Player> roster) {
    final on = _team == name;
    return GestureDetector(
      onTap: () => setState(() {
        _team = name;
        _jersey.clear();
        _jerseyDropdownValue = null;
        _showNumberPad = false;
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          border: Border.all(color: on ? T.accent : T.hair, width: 1.4),
          color: on ? T.accentSoft : Colors.transparent,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              header,
              style: const TextStyle(
                fontSize: 11,
                color: T.ink2,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              name,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: T.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepHeader extends StatelessWidget {
  const _StepHeader({required this.step, required this.selectedType});
  final int step;
  final String? selectedType;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          'Step ${step + 1} of 2',
          style: const TextStyle(fontSize: 12, color: T.ink2),
        ),
        const SizedBox(width: 8),
        const Expanded(child: Divider(color: T.rule, height: 1)),
        if (selectedType != null) ...[
          const SizedBox(width: 8),
          WfChip(label: selectedType!, active: true),
        ],
      ],
    );
  }
}

class _NumberPad extends StatelessWidget {
  const _NumberPad({required this.onTap});
  final void Function(String) onTap;

  @override
  Widget build(BuildContext context) {
    const keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '—', '0', '⌫'];
    return GridView.count(
      crossAxisCount: 3,
      crossAxisSpacing: 4,
      mainAxisSpacing: 4,
      childAspectRatio: 2.4,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: keys.map((k) {
        return GestureDetector(
          onTap: () => onTap(k),
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: T.hair),
              color: T.surface,
            ),
            alignment: Alignment.center,
            child: Text(
              k,
              style: TextStyle(
                fontFamily: T.mono,
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: k == '—' ? T.ink3 : T.ink,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                color: T.ink,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          WfSwitch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _RowItem extends StatelessWidget {
  const _RowItem({required this.title, this.subtitle, this.leading});
  final String title;
  final String? subtitle;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          if (leading != null) ...[
            SizedBox(width: 36, child: Center(child: leading)),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    color: T.ink,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  WfNote(subtitle!),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

extension on Border {
  BoxDecoration toBoxDecoration() => BoxDecoration(border: this);
}
