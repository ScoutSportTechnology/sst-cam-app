import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/device.dart';
import '../state/app_data.dart';
import '../state/ble_providers.dart';
import '../theme/tokens.dart';
import '../widgets/indicators.dart';
import '../widgets/live_preview_view.dart';
import '../widgets/wf_button.dart';
import '../widgets/wf_card.dart';
import '../widgets/wf_chip.dart';
import 'discovery_page.dart';
import 'team_match_form_sheet.dart';

/// The Match tab routes between Landing, Setup, Pre-match, Live and Final
/// based on user selection and the live match phase. While the match is
/// running it drives a 1 Hz tick into the controller.
class MatchPage extends ConsumerStatefulWidget {
  const MatchPage({super.key});

  @override
  ConsumerState<MatchPage> createState() => _MatchPageState();
}

class _MatchPageState extends ConsumerState<MatchPage> {
  Timer? _tick;

  /// The upcoming match the user has chosen to set up / play. Null = on the
  /// landing screen. Cleared when the user navigates back or the match ends.
  UpcomingMatch? _selected;

  /// True once the user has tapped "Start match" on the setup screen.
  /// Drives transition Setup → Pre-match. Reset by `_reset()` when leaving
  /// the match.
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

  void _reset() {
    ref.read(liveMatchProvider.notifier).reset();
    setState(() {
      _selected = null;
      _setupConfirmed = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final activeId = ref.watch(activeCameraIdProvider);
    final connected =
        activeId != null &&
        ref.watch(connectionStateProvider(activeId)).valueOrNull ==
            CameraConnectionState.connected;
    if (!connected) return const _ConnectCameraScreen();

    final phase = ref.watch(liveMatchProvider).phase;
    if (phase != MatchPhase.idle) {
      return _LiveScreen(onLeave: _reset);
    }

    final selected = _selected;
    if (selected == null) {
      return _UpcomingListScreen(onSelect: _select);
    }

    if (!_setupConfirmed) {
      return _SetupScreen(
        match: selected,
        onBack: () => setState(() => _selected = null),
        onStart: () => setState(() => _setupConfirmed = true),
      );
    }

    return _PreMatchScreen(
      onBack: () => setState(() => _setupConfirmed = false),
    );
  }
}

// ---------------------------------------------------------------------------
// Connect-camera empty state
// ---------------------------------------------------------------------------

class _ConnectCameraScreen extends StatelessWidget {
  const _ConnectCameraScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: T.bg,
      appBar: AppBar(title: const Text('Match')),
      body: Center(
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
                  Icons.videocam_off_outlined,
                  color: T.ink2,
                  size: 28,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'No camera connected',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: T.ink,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Connect a camera to schedule and run matches.',
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
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// LANDING — upcoming matches list across all teams
// ---------------------------------------------------------------------------

class _UpcomingListScreen extends ConsumerWidget {
  const _UpcomingListScreen({required this.onSelect});
  final ValueChanged<UpcomingMatch> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(upcomingMatchesProvider);
    return Scaffold(
      backgroundColor: T.bg,
      appBar: AppBar(title: const Text('Match')),
      body: async.when(
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
          if (matches.isEmpty) {
            return _NoUpcomingState(onSchedule: () => _schedule(context, ref));
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(0, 8, 0, 80),
            itemCount: matches.length,
            separatorBuilder: (_, _) => const Divider(height: 1, color: T.rule),
            itemBuilder: (_, i) => _UpcomingRow(
              match: matches[i],
              onTap: () => onSelect(matches[i]),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _schedule(context, ref),
        backgroundColor: T.accent,
        foregroundColor: T.accentInk,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(4)),
        ),
        icon: const Icon(Icons.add),
        label: const Text('Schedule match'),
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
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: T.fillSoft,
                          shape: BoxShape.circle,
                          border: Border.all(color: T.hair),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          t.shortName,
                          style: const TextStyle(
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

class _UpcomingRow extends StatelessWidget {
  const _UpcomingRow({required this.match, required this.onTap});
  final UpcomingMatch match;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final m = match.match;
    final t = match.team;
    final mins = m.periodLengthSeconds ~/ 60;
    final summary = m.numPeriods > 0 && mins > 0
        ? '${m.numPeriods} × $mins min · ${t.sport}'
        : t.sport;
    return Material(
      color: T.bg,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  border: Border.all(color: T.accent, width: 1.4),
                ),
                child: const Icon(Icons.event_outlined, color: T.accent),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            '${t.shortName} ${m.opponent}',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              color: T.ink,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${m.date} · $summary',
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
              'Past matches live in the Video and Teams tabs.',
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
  bool _autoStart = true;
  bool _pauseOnHt = true;
  _Quality _quality = _Quality.fhd1080p30;
  // null = Custom (use _customPeriods + _customMinutes from match init).
  SportPreset? _preset;
  int _customPeriods = 2;
  int _customPeriodSeconds = 35 * 60;
  bool _initialized = false;

  // Streaming destinations.
  final Set<_StreamMethod> _streamMethods = {};
  String _customRtmpUrl = '';

  @override
  Widget build(BuildContext context) {
    final live = ref.watch(liveMatchProvider);
    final ctl = ref.read(liveMatchProvider.notifier);
    final team = widget.match.team;
    final m = widget.match.match;
    final presets = ref.watch(sportPresetsForSportProvider(team.sport));

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
            leading: Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: T.fillSoft,
                shape: BoxShape.circle,
                border: Border.all(color: T.hair),
              ),
              child: Text(
                team.shortName,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                  color: T.ink2,
                ),
              ),
            ),
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
            child: Wrap(
              spacing: 6,
              children: [WfChip(label: team.sport, active: true)],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
            child: WfCard(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const WfNote('Sport setup'),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final p in presets)
                        GestureDetector(
                          onTap: () => setState(() => _preset = p),
                          child: WfChip(
                            label: p.name,
                            active: _preset?.id == p.id,
                          ),
                        ),
                      GestureDetector(
                        onTap: () => _editCustom(context),
                        child: WfChip(
                          label: 'Custom…',
                          active: _preset == null,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '$periods × $periodMinutes min',
                    style: const TextStyle(
                      color: T.ink,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const WfSection('Recording'),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
            child: WfCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  _ToggleRow(
                    label: 'Record this match',
                    value: live.recordingEnabled,
                    onChanged: ctl.setRecordingEnabled,
                  ),
                  const Divider(height: 1, color: T.rule),
                  _ToggleRow(
                    label: 'Auto-start at kickoff',
                    value: _autoStart,
                    onChanged: (v) => setState(() => _autoStart = v),
                  ),
                  const Divider(height: 1, color: T.rule),
                  _ToggleRow(
                    label: 'Pause on halftime',
                    value: _pauseOnHt,
                    onChanged: (v) => setState(() => _pauseOnHt = v),
                  ),
                  const Divider(height: 1, color: T.rule),
                  _DropdownRow<_Quality>(
                    label: 'Quality',
                    value: _quality,
                    items: _Quality.values,
                    labelOf: (q) => q.label,
                    onChanged: (v) => setState(() => _quality = v),
                  ),
                ],
              ),
            ),
          ),
          const WfSection('Streaming'),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
            child: WfCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  _ToggleRow(
                    label: 'Stream this match',
                    sub: 'Live to one or more destinations',
                    value: live.streamingEnabled,
                    onChanged: ctl.setStreamingEnabled,
                  ),
                  if (live.streamingEnabled) ...[
                    const Divider(height: 1, color: T.rule),
                    _StreamMethodPicker(
                      selected: _streamMethods,
                      customRtmpUrl: _customRtmpUrl,
                      onSelect: _toggleStreamMethod,
                    ),
                  ],
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: WfButton(
              label: 'Start match',
              variant: WfButtonVariant.primary,
              size: WfButtonSize.lg,
              full: true,
              onPressed: widget.onStart,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleStreamMethod(_StreamMethod method) async {
    final isOn = _streamMethods.contains(method);
    if (method == _StreamMethod.custom) {
      // Custom requires a URL — open the config modal whether enabling or
      // editing an existing entry.
      final url = await _showCustomRtmpModal(context, initial: _customRtmpUrl);
      if (url == null) return; // cancelled
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

class _StreamMethodPicker extends StatelessWidget {
  const _StreamMethodPicker({
    required this.selected,
    required this.customRtmpUrl,
    required this.onSelect,
  });
  final Set<_StreamMethod> selected;
  final String customRtmpUrl;
  final void Function(_StreamMethod) onSelect;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
                  onTap: () => onSelect(m),
                  child: WfChip(
                    label: m == _StreamMethod.custom && customRtmpUrl.isNotEmpty
                        ? 'Custom RTMP · configured'
                        : m.label,
                    active: selected.contains(m),
                  ),
                ),
            ],
          ),
          if (selected.isEmpty) ...[
            const SizedBox(height: 8),
            const WfNote('Pick one or more destinations to stream to.'),
          ],
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
// PRE-MATCH (clock 00:00, "Start 1st half" in accent, mark-event disabled)
// ---------------------------------------------------------------------------

class _PreMatchScreen extends ConsumerWidget {
  const _PreMatchScreen({required this.onBack});
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctl = ref.read(liveMatchProvider.notifier);
    final live = ref.watch(liveMatchProvider);

    return Scaffold(
      backgroundColor: T.bg,
      body: SafeArea(
        child: Column(
          children: [
            _TopBar(
              indicator: 'READY',
              indicatorColor: T.ink2,
              clock: '00:00',
              onBack: onBack,
            ),
            _LiveThumb(
              homeLabel: live.homeName,
              awayLabel: live.awayName,
              homeScore: 0,
              awayScore: 0,
              phaseLabel: 'PRE',
              clock: '00:00',
              isLive: false,
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  const Expanded(
                    child: WfButton(
                      label: 'Mark event',
                      size: WfButtonSize.lg,
                      // disabled
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: WfButton(
                      label: 'Start 1st half',
                      variant: WfButtonVariant.primary,
                      size: WfButtonSize.lg,
                      onPressed: ctl.startFirstHalf,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: T.rule),
            const WfSection(
              'Event log',
              padding: EdgeInsets.fromLTRB(14, 10, 14, 4),
            ),
            const Expanded(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: WfNote(
                    'No events yet. Tap Start 1st half to begin the clock.',
                  ),
                ),
              ),
            ),
            const _IdleControlGroup(),
          ],
        ),
      ),
    );
  }
}

class _IdleControlGroup extends StatelessWidget {
  const _IdleControlGroup();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: const Border(
        top: BorderSide(color: T.rule),
      ).toBoxDecoration(),
      child: Row(
        children: const [
          Expanded(
            child: _ControlGroup(
              label: 'TIMER',
              value: '00:00',
              body: WfButton(label: 'Idle'),
            ),
          ),
          SizedBox(width: 8),
          Expanded(
            child: _ControlGroup(
              label: 'RECORDING',
              value: '',
              body: WfButton(
                label: 'Record',
                leading: _Dot(color: T.danger),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// LIVE (also covers halftime + ended)
// ---------------------------------------------------------------------------

class _LiveScreen extends ConsumerWidget {
  const _LiveScreen({required this.onLeave});
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(liveMatchProvider);
    final ctl = ref.read(liveMatchProvider.notifier);

    final isHalftime = state.phase == MatchPhase.halftime;
    final isEnded = state.phase == MatchPhase.ended;
    final isLive = state.isLive;

    final halfButton = switch (state.phase) {
      MatchPhase.firstHalf => _HalfButton(
        label: 'End 1st half',
        variant: WfButtonVariant.danger,
        onPressed: ctl.endFirstHalf,
      ),
      MatchPhase.halftime => _HalfButton(
        label: 'Start 2nd half',
        variant: WfButtonVariant.primary,
        onPressed: ctl.startSecondHalf,
      ),
      MatchPhase.secondHalf => _HalfButton(
        label: 'End match',
        variant: WfButtonVariant.danger,
        onPressed: ctl.endMatch,
      ),
      _ => _HalfButton(
        label: 'Match ended',
        variant: WfButtonVariant.outline,
        onPressed: onLeave,
      ),
    };

    return Scaffold(
      backgroundColor: T.bg,
      body: SafeArea(
        child: Column(
          children: [
            _TopBar(
              indicator: state.rec == RecState.recording ? 'REC' : 'PAUSED',
              indicatorColor: state.rec == RecState.recording
                  ? T.accent
                  : T.ink2,
              clock: state.clockText,
            ),
            _LiveThumb(
              homeLabel: state.homeName,
              awayLabel: state.awayName,
              homeScore: state.scoreHome,
              awayScore: state.scoreAway,
              phaseLabel: state.phaseLabel,
              clock: state.clockText,
              isLive: isLive,
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  Expanded(
                    child: WfButton(
                      label: 'Mark event',
                      variant: WfButtonVariant.primary,
                      size: WfButtonSize.lg,
                      leading: const _Square(color: T.accentInk),
                      onPressed: isLive
                          ? () => _showEventSheet(context, ref)
                          : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: halfButton),
                ],
              ),
            ),
            const Divider(height: 1, color: T.rule),
            const WfSection(
              'Event log',
              padding: EdgeInsets.fromLTRB(14, 10, 14, 4),
            ),
            Expanded(
              child: state.events.isEmpty
                  ? const Center(child: WfNote('No events yet'))
                  : ListView.separated(
                      padding: EdgeInsets.zero,
                      itemCount: state.events.length,
                      separatorBuilder: (_, _) =>
                          const Divider(height: 1, color: T.rule),
                      itemBuilder: (_, i) => _EventLogRow(e: state.events[i]),
                    ),
            ),
            _LiveControls(
              state: state,
              onTimerTap: ctl.toggleTimer,
              onRecPause: ctl.toggleRecPause,
              onRecStop: ctl.stopRecording,
              showHalftimeBanner: isHalftime,
              showEndedBanner: isEnded,
            ),
          ],
        ),
      ),
    );
  }

  void _showEventSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: T.bg,
      isScrollControlled: true,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (_) => _EventSheet(
        onSave: (type, team, jersey) {
          ref
              .read(liveMatchProvider.notifier)
              .addEvent(type: type, teamLabel: team, jersey: jersey);
        },
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
              color: indicator == 'READY' ? Colors.transparent : indicatorColor,
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

class _HalfButton extends StatelessWidget {
  const _HalfButton({
    required this.label,
    required this.variant,
    required this.onPressed,
  });
  final String label;
  final WfButtonVariant variant;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return WfButton(
      label: label,
      variant: variant,
      size: WfButtonSize.lg,
      full: true,
      onPressed: onPressed,
    );
  }
}

class _EventLogRow extends StatelessWidget {
  const _EventLogRow({required this.e});
  final LiveEvent e;

  @override
  Widget build(BuildContext context) {
    final isPhase = e.kind == 'phase';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            child: Text(
              e.clock,
              style: TextStyle(
                fontFamily: T.mono,
                fontWeight: isPhase ? FontWeight.w700 : FontWeight.w400,
                color: isPhase ? T.accent : T.ink2,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              e.label,
              style: TextStyle(
                fontSize: 12,
                color: T.ink,
                fontWeight: isPhase ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
          if (isPhase)
            const Text(
              'PHASE',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: T.accent,
                letterSpacing: 0.5,
              ),
            )
          else
            const Text('edit', style: TextStyle(fontSize: 11, color: T.ink2)),
        ],
      ),
    );
  }
}

class _LiveControls extends StatelessWidget {
  const _LiveControls({
    required this.state,
    required this.onTimerTap,
    required this.onRecPause,
    required this.onRecStop,
    required this.showHalftimeBanner,
    required this.showEndedBanner,
  });

  final LiveMatchState state;
  final VoidCallback onTimerTap;
  final VoidCallback onRecPause;
  final VoidCallback onRecStop;
  final bool showHalftimeBanner;
  final bool showEndedBanner;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: const Border(
        top: BorderSide(color: T.rule),
      ).toBoxDecoration(),
      child: Column(
        children: [
          if (showHalftimeBanner)
            const _PhaseBanner(text: 'Halftime · clock paused'),
          if (showEndedBanner) const _PhaseBanner(text: 'Match ended'),
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
                    onPressed: state.isLive ? onTimerTap : null,
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
                              : 'Idle',
                          leading: state.rec == RecState.recording
                              ? const _PauseGlyph()
                              : const _PlayGlyph(),
                          onPressed: state.rec == RecState.idle
                              ? null
                              : onRecPause,
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
        ],
      ),
    );
  }
}

class _PhaseBanner extends StatelessWidget {
  const _PhaseBanner({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: T.accentSoft,
        border: Border.all(color: T.accent, width: 1),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: T.accent,
          letterSpacing: 0.5,
        ),
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
  const _EventSheet({required this.onSave});
  final void Function(String type, String team, String? jersey) onSave;

  @override
  ConsumerState<_EventSheet> createState() => _EventSheetState();
}

class _EventSheetState extends ConsumerState<_EventSheet> {
  static const _types = ['Goal', 'Foul', 'Card', 'Sub', 'Save', 'Other'];

  int _step = 0;
  String _type = 'Goal';
  String? _team;
  final _jersey = StringBuffer();

  @override
  Widget build(BuildContext context) {
    final live = ref.watch(liveMatchProvider);
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
            if (_step == 0) _typePicker() else _teamAndJersey(live),
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
                        ? () => setState(() => _step = 1)
                        : (_team == null
                              ? null
                              : () {
                                  widget.onSave(
                                    _type,
                                    _team!,
                                    _jersey.toString(),
                                  );
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

  Widget _teamAndJersey(LiveMatchState live) {
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
            Expanded(child: _teamCard('HOME', live.homeName)),
            const SizedBox(width: 8),
            Expanded(child: _teamCard('AWAY', live.awayName)),
          ],
        ),
        const SizedBox(height: 18),
        const Text(
          'Jersey #',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: T.ink,
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(height: 10),
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
              const Spacer(),
              const WfNote('Optional'),
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
    );
  }

  Widget _teamCard(String header, String name) {
    final on = _team == name;
    return GestureDetector(
      onTap: () => setState(() => _team = name),
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
// Helpers shared with setup
// ---------------------------------------------------------------------------

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.label,
    this.sub,
    required this.value,
    required this.onChanged,
  });
  final String label;
  final String? sub;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13,
                    color: T.ink,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (sub != null) ...[const SizedBox(height: 2), WfNote(sub!)],
              ],
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
