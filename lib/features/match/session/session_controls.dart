// Session control surfaces — the Mark-event / phase action row and the
// bottom timer / recording / streaming control panel. Split from
// session_screen.dart; behavior is unchanged.

import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/wf_button.dart';
import 'session_state.dart';

// ---------------------------------------------------------------------------
// PRIMARY ACTION ROW
// ---------------------------------------------------------------------------

class SessionPrimaryActionRow extends StatelessWidget {
  const SessionPrimaryActionRow({
    super.key,
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
          size: WfButtonSize.sm,
          full: true,
          onPressed: onKickoff,
        );
      case MatchPhase.period:
        phaseButton = WfButton(
          label: 'End period ${state.currentPeriod}',
          variant: WfButtonVariant.danger,
          size: WfButtonSize.sm,
          full: true,
          onPressed: onEndPeriod,
        );
      case MatchPhase.periodBreak:
        phaseButton = state.awaitingEndOfMatch
            ? WfButton(
                label: 'End match',
                variant: WfButtonVariant.danger,
                size: WfButtonSize.sm,
                full: true,
                onPressed: onEndMatch,
              )
            : WfButton(
                label: 'Start period ${state.currentPeriod + 1}',
                variant: WfButtonVariant.primary,
                size: WfButtonSize.sm,
                full: true,
                onPressed: onStartNextPeriod,
              );
      case MatchPhase.ended:
        phaseButton = const WfButton(
          label: 'Match ended',
          variant: WfButtonVariant.outline,
          size: WfButtonSize.sm,
          full: true,
        );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      child: Row(
        children: [
          Expanded(
            child: WfButton(
              label: 'Mark event',
              variant: onMarkEvent != null
                  ? WfButtonVariant.primary
                  : WfButtonVariant.outline,
              size: WfButtonSize.sm,
              full: true,
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

// ---------------------------------------------------------------------------
// BOTTOM CONTROLS
// ---------------------------------------------------------------------------

class SessionBottomControls extends StatelessWidget {
  const SessionBottomControls({
    super.key,
    required this.state,
    required this.onTimerTap,
    required this.onRecToggle,
    required this.onStreamToggle,
  });

  final LiveMatchState state;
  final VoidCallback onTimerTap;
  final VoidCallback? onRecToggle;
  final VoidCallback? onStreamToggle;

  @override
  Widget build(BuildContext context) {
    final timerEnabled = state.phase == MatchPhase.period;

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: T.rule)),
      ),
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
                    size: WfButtonSize.sm,
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
                  // One continuous file per match: Record → Pause/Resume.
                  // There is no mid-match "stop" — finalizing mid-match then
                  // recording again re-opened the SAME <matchId>.mp4 and
                  // overwrote the earlier footage. The recording is finalized
                  // once, at match end ("Also stop recording"). Pause through
                  // anything you don't want recorded.
                  body: WfButton(
                    label: state.rec == RecState.recording
                        ? 'Pause'
                        : state.rec == RecState.paused
                        ? 'Resume'
                        : 'Record',
                    size: WfButtonSize.sm,
                    leading: state.rec == RecState.recording
                        ? const _PauseGlyph()
                        : const _Dot(color: T.danger),
                    onPressed: onRecToggle,
                    full: true,
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
              size: WfButtonSize.sm,
              full: true,
              onPressed: onStreamToggle,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// CONTROL GROUP
// ---------------------------------------------------------------------------

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
      padding: const EdgeInsets.fromLTRB(10, 5, 10, 7),
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
          const SizedBox(height: 5),
          body,
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// DOT / SQUARE / PAUSE GLYPH / PLAY GLYPH
// ---------------------------------------------------------------------------

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
