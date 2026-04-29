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

/// The Match tab routes between Setup, Pre-match, Live and Final based on
/// the live match phase. Drives a 1 Hz tick into the controller while the
/// match is running.
class MatchPage extends ConsumerStatefulWidget {
  const MatchPage({super.key});

  @override
  ConsumerState<MatchPage> createState() => _MatchPageState();
}

class _MatchPageState extends ConsumerState<MatchPage> {
  Timer? _tick;

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

  @override
  Widget build(BuildContext context) {
    final activeId = ref.watch(activeCameraIdProvider);
    final connected =
        activeId != null &&
        ref.watch(connectionStateProvider(activeId)).valueOrNull ==
            CameraConnectionState.connected;
    if (!connected) return const _ConnectCameraScreen();

    final phase = ref.watch(liveMatchProvider).phase;
    return switch (phase) {
      MatchPhase.idle => const _SetupOrPreMatchSwitcher(),
      MatchPhase.firstHalf ||
      MatchPhase.halftime ||
      MatchPhase.secondHalf ||
      MatchPhase.ended => const _LiveScreen(),
    };
  }
}

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
                'Connect a camera to set up a match, record, and stream.',
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

class _SetupOrPreMatchSwitcher extends ConsumerStatefulWidget {
  const _SetupOrPreMatchSwitcher();

  @override
  ConsumerState<_SetupOrPreMatchSwitcher> createState() =>
      _SetupOrPreMatchSwitcherState();
}

class _SetupOrPreMatchSwitcherState
    extends ConsumerState<_SetupOrPreMatchSwitcher> {
  bool _setupConfirmed = false;

  @override
  Widget build(BuildContext context) {
    if (!_setupConfirmed) {
      return _SetupScreen(
        onStart: () => setState(() => _setupConfirmed = true),
      );
    }
    return _PreMatchScreen(
      onBack: () => setState(() => _setupConfirmed = false),
    );
  }
}

// ---------------------------------------------------------------------------
// SETUP
// ---------------------------------------------------------------------------

class _SetupScreen extends ConsumerStatefulWidget {
  const _SetupScreen({required this.onStart});
  final VoidCallback onStart;

  @override
  ConsumerState<_SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<_SetupScreen> {
  bool _autoStart = true;
  bool _pauseOnHt = true;
  bool _resolution = false;
  bool _streamYoutube = true;
  bool _streamRtmp = false;
  bool _streamLocal = false;

  @override
  Widget build(BuildContext context) {
    final live = ref.watch(liveMatchProvider);
    final ctl = ref.read(liveMatchProvider.notifier);

    return Scaffold(
      backgroundColor: T.bg,
      appBar: AppBar(
        title: const Text('New match'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.maybePop(context),
        ),
        actions: [TextButton(onPressed: () {}, child: const Text('Save'))],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          const WfSection('Teams'),
          _RowItem(
            leading: const Icon(Icons.shield_outlined),
            title: live.homeName,
            subtitle: 'Home',
            trailing: const Text(
              'Change',
              style: TextStyle(color: T.ink2, fontSize: 12),
            ),
          ),
          const Divider(height: 1, color: T.rule),
          _RowItem(
            leading: const Icon(Icons.shield_outlined),
            title: live.awayName,
            subtitle: 'Away',
            trailing: const Text(
              'Change',
              style: TextStyle(color: T.ink2, fontSize: 12),
            ),
          ),
          const WfSection('Format'),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
            child: Wrap(
              spacing: 6,
              children: const [
                WfChip(label: 'Soccer', active: true),
                WfChip(label: 'Basketball'),
                WfChip(label: 'Hockey'),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
            child: Row(
              children: [
                Expanded(
                  child: WfCard(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        WfNote('Halves'),
                        SizedBox(height: 4),
                        Text(
                          '2 × 35 min',
                          style: TextStyle(
                            color: T.ink,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: WfCard(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        WfNote('Stoppage'),
                        SizedBox(height: 4),
                        Text(
                          'Manual',
                          style: TextStyle(
                            color: T.ink,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const WfSection('Camera'),
          _RowItem(
            leading: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: T.accent,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            title: 'sst-cam-01',
            subtitle: 'Connected · 78% battery · 142 GB free',
            trailing: const Icon(Icons.chevron_right, color: T.ink3, size: 18),
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
                  _ToggleRow(
                    label: '1080p / 30 fps',
                    value: _resolution,
                    onChanged: (v) => setState(() => _resolution = v),
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
                  const Divider(height: 1, color: T.rule),
                  _ToggleRow(
                    label: 'YouTube Live',
                    sub: 'NR U14 channel · 1080p',
                    value: _streamYoutube,
                    onChanged: (v) => setState(() => _streamYoutube = v),
                  ),
                  const Divider(height: 1, color: T.rule),
                  _ToggleRow(
                    label: 'Custom RTMP',
                    sub: 'rtmp://stream.team.club/...',
                    value: _streamRtmp,
                    onChanged: (v) => setState(() => _streamRtmp = v),
                  ),
                  const Divider(height: 1, color: T.rule),
                  _ToggleRow(
                    label: 'Local network',
                    sub: 'mDNS · for parents on WiFi',
                    value: _streamLocal,
                    onChanged: (v) => setState(() => _streamLocal = v),
                  ),
                ],
              ),
            ),
          ),
          _RowItem(
            leading: const Icon(Icons.add),
            title: 'Add destination',
            trailing: const Text(
              '+',
              style: TextStyle(color: T.ink2, fontSize: 18),
            ),
            dense: true,
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
              homeLabel: 'NR',
              awayLabel: 'EFC',
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
  const _LiveScreen();

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
        onPressed: ctl.reset,
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
  const _RowItem({
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.dense = false,
  });
  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 14, vertical: dense ? 10 : 12),
      child: Row(
        children: [
          if (leading != null) ...[
            SizedBox(width: 24, child: Center(child: leading)),
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
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

extension on Border {
  BoxDecoration toBoxDecoration() => BoxDecoration(border: this);
}
