// Session screen — covers pre-game, period-active, period-break and ended
// phases. Recording / streaming controls are independent of the period timer
// so the user can record before kickoff or after the final whistle.

import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ble/ble_providers.dart';
import '../../../core/models/command.dart';
import '../../../core/models/device.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/indicators.dart';
import '../../../core/widgets/live_preview_view.dart';
import '../../../core/widgets/preview_layout_toggle.dart';
import '../../../core/widgets/wf_button.dart';
import '../../../core/widgets/wf_card.dart';
import '../../../core/models/wifi.dart' show WifiDirectState;
import '../../../core/wifi/wifi_providers.dart'
    show livePreviewEnabledProvider, wifiConnectionStateProvider;
import '../../camera/camera_state.dart'
    show activeCameraIdProvider, activeTabProvider, AppTab;
import '../../../core/state/db_providers.dart' show teamsDaoProvider;
import '../match_state.dart' show UpcomingMatch;
import 'event_sheet.dart';
import 'session_state.dart';

class SessionScreen extends ConsumerWidget {
  const SessionScreen({super.key, required this.match, required this.onLeave});
  final UpcomingMatch match;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(liveMatchProvider);
    final ctl = ref.read(liveMatchProvider.notifier);

    final activeId = ref.watch(activeCameraIdProvider);
    final connected =
        activeId != null &&
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
    final indicatorColor = state.rec == RecState.recording ? T.accent : T.ink2;

    final previewOn = ref.watch(livePreviewEnabledProvider(activeId));

    return Scaffold(
      backgroundColor: T.bg,
      body: SafeArea(
        child: Column(
          children: [
            _TopBar(
              indicator: indicator,
              indicatorColor: indicatorColor,
              clock: state.clockText,
              onBack: (isEnded || state.phase == MatchPhase.idle)
                  ? onLeave
                  : null,
            ),
            // Inset the preview to the same horizontal margin as the controls
            // below, so its edges line up with the Mark event / phase buttons.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: _LiveThumb(matchState: state, isLive: isPeriodActive),
            ),
            // Preview controls — below the feed (not overlaid). The Single|Both
            // mode toggle sits next to the Preview button, matching the main
            // camera card's layout. Only shown when a camera is connected.
            if (activeId != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
                // Two columns mirroring the Mark event / phase action row below,
                // so the Preview button's width and right edge line up with the
                // Mark event button. The Single|Both toggle sits in the right
                // column (right-aligned), empty when preview is off.
                child: Row(
                  children: [
                    Expanded(
                      child: WfButton(
                        label: previewOn ? 'Stop preview' : 'Preview',
                        variant: WfButtonVariant.outline,
                        size: WfButtonSize.sm,
                        full: true,
                        leading: previewOn
                            ? null
                            : const Icon(
                                Icons.play_arrow_rounded,
                                size: 13,
                                color: T.ink,
                              ),
                        onPressed: () {
                          ref
                                  .read(
                                    livePreviewEnabledProvider(
                                      activeId,
                                    ).notifier,
                                  )
                                  .state =
                              !previewOn;
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: previewOn
                          ? PreviewLayoutToggle(deviceId: activeId, full: true)
                          : const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
            _PrimaryActionRow(
              state: state,
              onMarkEvent: isPeriodActive
                  ? () => _showEventSheet(context, ref)
                  : null,
              onKickoff: () => _kickoff(context, ref, ctl, state),
              onEndPeriod: () {
                _sendIfConnected(
                  ref,
                  MatchControlCommand(
                    action: BleMatchControlAction.periodEnd,
                    period: state.currentPeriod,
                  ),
                );
                ctl.endPeriod();
              },
              onStartNextPeriod: () {
                _sendIfConnected(
                  ref,
                  MatchControlCommand(
                    action: BleMatchControlAction.periodStart,
                    period: state.currentPeriod + 1,
                  ),
                );
                ctl.startPeriod();
              },
              onEndMatch: () => _confirmEnd(context, ref, ctl, state),
            ),
            if (isEnded) const _EndedBanner(),
            const Divider(height: 1, color: T.rule),
            const WfSection(
              'Event log',
              padding: EdgeInsets.fromLTRB(14, 10, 14, 4),
            ),
            Expanded(child: _buildEventLog(state)),
            _BottomControls(
              state: state,
              onTimerTap: () {
                final isRunning = state.timer == MatchTimer.running;
                _sendIfConnected(
                  ref,
                  MatchControlCommand(
                    action: isRunning
                        ? BleMatchControlAction.clockPause
                        : BleMatchControlAction.clockResume,
                    period: state.currentPeriod,
                  ),
                );
                ctl.toggleTimer();
              },
              onRecToggle: connected
                  ? () {
                      final currentRec = state.rec;
                      ctl.toggleRecPause();
                      if (currentRec == RecState.idle) {
                        _sendIfConnected(
                          ref,
                          RecordingControlCommand(
                            action: RecordingControlAction.start,
                          ),
                        );
                      } else if (currentRec == RecState.recording) {
                        _sendIfConnected(
                          ref,
                          RecordingControlCommand(
                            action: RecordingControlAction.pause,
                          ),
                        );
                      } else if (currentRec == RecState.paused) {
                        _sendIfConnected(
                          ref,
                          RecordingControlCommand(
                            action: RecordingControlAction.resume,
                          ),
                        );
                      }
                    }
                  : null,
              onStreamToggle: connected
                  ? () => _toggleStream(context, ref, ctl, state)
                  : null,
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

  /// Toggle streaming mid-match. Stopping is unconditional. Starting resolves
  /// the per-match credential: use the one stored at setup, or — if none — prompt
  /// for a one-off, store it on the match, then start. Cancelling the prompt
  /// starts nothing and leaves the session unchanged.
  Future<void> _toggleStream(
    BuildContext context,
    WidgetRef ref,
    LiveMatchController ctl,
    LiveMatchState state,
  ) async {
    if (state.streaming) {
      _sendIfConnected(
        ref,
        StreamingControlCommand(
          action: StreamingControlAction.stop,
          rtmpUrl: null,
        ),
      );
      ctl.setStreaming(false);
      return;
    }

    final matchId = ref.read(liveMatchProvider.notifier).matchId;
    String? wireUrl;
    if (matchId != null) {
      final m = await ref.read(teamsDaoProvider).getMatchById(matchId);
      final url = m?.rtmpUrl;
      if (url != null && url.isNotEmpty) {
        final key = m!.streamKey;
        wireUrl = (key == null || key.isEmpty) ? url : _joinRtmp(url, key);
      }
    }

    if (wireUrl == null) {
      if (!context.mounted) return;
      final entered = await _promptStreamCredential(context);
      if (entered == null) return; // cancelled — start nothing
      if (matchId != null) {
        await ref
            .read(teamsDaoProvider)
            .setMatchStreamingCredential(
              matchId,
              rtmpUrl: entered,
              streamKey: null,
            );
      }
      wireUrl = entered;
    }

    _sendIfConnected(
      ref,
      StreamingControlCommand(
        action: StreamingControlAction.start,
        rtmpUrl: wireUrl,
      ),
    );
    ctl.setStreaming(true);
  }

  Future<void> _kickoff(
    BuildContext context,
    WidgetRef ref,
    LiveMatchController ctl,
    LiveMatchState state,
  ) async {
    // Kickoff prompt — only on the very first period. Subsequent periods
    // continue with whatever recording / streaming state is active.
    if (state.currentPeriod != 0) {
      _sendIfConnected(
        ref,
        MatchControlCommand(
          action: BleMatchControlAction.kickoff,
          period: state.currentPeriod + 1,
        ),
      );
      ctl.startPeriod();
      return;
    }
    final recAlreadyOn = state.rec != RecState.idle;
    final streamAlreadyOn = state.streaming;
    if (recAlreadyOn && streamAlreadyOn) {
      // Both are already running — nothing to ask, just start the period.
      _sendIfConnected(
        ref,
        MatchControlCommand(
          action: BleMatchControlAction.kickoff,
          period: state.currentPeriod + 1,
        ),
      );
      ctl.startPeriod();
      return;
    }
    final choice = await _showStartPrompt(
      context,
      askRecord: !recAlreadyOn,
      askStream: !streamAlreadyOn,
    );
    if (choice == null) return;
    _sendIfConnected(
      ref,
      MatchControlCommand(
        action: BleMatchControlAction.kickoff,
        period: state.currentPeriod + 1,
      ),
    );
    // Honor the start-prompt choices on the camera. startPeriod only flips the
    // local UI state; without these explicit control commands the firmware
    // records/streams nothing (the match dir stays empty).
    if (choice.$1 == true) {
      _sendIfConnected(
        ref,
        RecordingControlCommand(action: RecordingControlAction.start),
      );
    }
    if (choice.$2 == true) {
      _sendIfConnected(
        ref,
        StreamingControlCommand(action: StreamingControlAction.start),
      );
    }
    ctl.startPeriod(startRecording: choice.$1, startStreaming: choice.$2);
  }

  Future<void> _confirmEnd(
    BuildContext context,
    WidgetRef ref,
    LiveMatchController ctl,
    LiveMatchState state,
  ) async {
    final recOn = state.rec != RecState.idle;
    final streamOn = state.streaming;
    if (!recOn && !streamOn) {
      // Nothing is running — no toggles to ask about, just end.
      _sendIfConnected(
        ref,
        MatchControlCommand(
          action: BleMatchControlAction.finalWhistle,
          period: state.currentPeriod,
        ),
      );
      ctl.endMatch(stopRecording: false, stopStreaming: false);
      _finalizeMatchToLibrary(ref);
      return;
    }
    final choice = await _showEndPrompt(
      context,
      askStopRec: recOn,
      askStopStream: streamOn,
    );
    if (choice == null) return;
    _sendIfConnected(
      ref,
      MatchControlCommand(
        action: BleMatchControlAction.finalWhistle,
        period: state.currentPeriod,
      ),
    );
    // Stop recording/streaming on the camera per the prompt. endMatch only flips
    // local state; without these the firmware keeps recording and the mp4 never
    // finalizes (no moov atom → unplayable, file grows unbounded).
    if (choice.$1 == true) {
      _sendIfConnected(
        ref,
        RecordingControlCommand(action: RecordingControlAction.stop),
      );
    }
    if (choice.$2 == true) {
      _sendIfConnected(
        ref,
        StreamingControlCommand(action: StreamingControlAction.stop),
      );
    }
    ctl.endMatch(
      stopRecording: choice.$1 ?? false,
      stopStreaming: choice.$2 ?? false,
    );
    _finalizeMatchToLibrary(ref);
  }

  void _showEventSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: T.bg,
      isScrollControlled: true,
      barrierColor: T.barrierColor,
      builder: (_) => EventSheet(
        homeTeamId: match.team.id,
        onSave: (type, team, jersey) {
          // Build the param map the firmware uses for {{param}} substitution in
          // the event-banner templates (e.g. "{{player}}"). The firmware is the
          // sole overlay renderer now (A6a), so these keys must match the
          // template static_text placeholders in defaultScoreboardLayout.
          final params = <String, String>{
            if (jersey != null && jersey.isNotEmpty) 'jersey': jersey,
            // Always present (blank when no jersey) so the banner's "{{player}}"
            // subtitle resolves to a clean string, never a literal placeholder.
            'player': jersey != null && jersey.isNotEmpty ? '#$jersey' : '',
          };
          // player_id carries the jersey number as the player identifier
          // available on the wire (no roster id is selected in this flow).
          final playerId = jersey != null && jersey.isNotEmpty ? jersey : null;

          ref
              .read(liveMatchProvider.notifier)
              .addEvent(
                type: type,
                teamLabel: team,
                jersey: jersey,
                params: params,
              );
          if (type == 'Goal') {
            // Firmware routes score by the session-config team_a_id (home UUID)
            // / team_b_id (away display name), NOT the display label — sending
            // the label makes the camera drop the goal as an unknown team.
            final live = ref.read(liveMatchProvider);
            final teamId = team == live.homeName
                ? match.team.id
                : live.awayName;
            _sendIfConnected(ref, ScoreUpdateCommand(teamId: teamId, delta: 1));
            _sendIfConnected(
              ref,
              BannerEventCommand(
                templateId: 'goal',
                durationSeconds: 5,
                params: params,
                playerId: playerId,
              ),
            );
          } else if (type == 'Yellow Card') {
            _sendIfConnected(
              ref,
              BannerEventCommand(
                templateId: 'yellow_card',
                durationSeconds: 4,
                params: params,
                playerId: playerId,
              ),
            );
          } else if (type == 'Red Card') {
            _sendIfConnected(
              ref,
              BannerEventCommand(
                templateId: 'red_card',
                durationSeconds: 4,
                params: params,
                playerId: playerId,
              ),
            );
          } else if (type == 'Sub') {
            _sendIfConnected(
              ref,
              BannerEventCommand(
                templateId: 'substitution',
                durationSeconds: 4,
                params: params,
                playerId: playerId,
              ),
            );
          }
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// START PROMPT — kickoff bottom sheet
// ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------
// END PROMPT — confirm end-of-match bottom sheet
// ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------
// PRIMARY ACTION ROW
// ---------------------------------------------------------------------------

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
          size: WfButtonSize.md,
          full: true,
          onPressed: onKickoff,
        );
      case MatchPhase.period:
        phaseButton = WfButton(
          label: 'End period ${state.currentPeriod}',
          variant: WfButtonVariant.danger,
          size: WfButtonSize.md,
          full: true,
          onPressed: onEndPeriod,
        );
      case MatchPhase.periodBreak:
        phaseButton = state.awaitingEndOfMatch
            ? WfButton(
                label: 'End match',
                variant: WfButtonVariant.danger,
                size: WfButtonSize.md,
                full: true,
                onPressed: onEndMatch,
              )
            : WfButton(
                label: 'Start period ${state.currentPeriod + 1}',
                variant: WfButtonVariant.primary,
                size: WfButtonSize.md,
                full: true,
                onPressed: onStartNextPeriod,
              );
      case MatchPhase.ended:
        phaseButton = const WfButton(
          label: 'Match ended',
          variant: WfButtonVariant.outline,
          size: WfButtonSize.md,
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
              size: WfButtonSize.md,
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
// ENDED BANNER
// ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------
// BOTTOM CONTROLS
// ---------------------------------------------------------------------------

class _BottomControls extends StatelessWidget {
  const _BottomControls({
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
// TOP BAR
// ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------
// LIVE THUMB
// ---------------------------------------------------------------------------

class _LiveThumb extends ConsumerWidget {
  const _LiveThumb({required this.matchState, required this.isLive});
  final LiveMatchState matchState;
  final bool isLive;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeId = ref.watch(activeCameraIdProvider);
    // Only the visible tab holds a VLC client (home + match preview cards both
    // stay mounted in the shell's IndexedStack; two clients on the single-stream
    // RTSP server stall the second — the match preview was the loser).
    final onMatchTab = ref.watch(activeTabProvider) == AppTab.match;

    // When WiFi Direct fails (e.g. iOS does not support local preview),
    // show a static placeholder instead of the live preview surface.
    final wifiState = activeId == null
        ? null
        : ref.watch(wifiConnectionStateProvider(activeId)).valueOrNull;
    final wifiFailed = wifiState == WifiDirectState.failed;

    return Stack(
      children: [
        if (wifiFailed)
          _PreviewUnavailablePlaceholder(matchState: matchState, isLive: isLive)
        else
          // The firmware composites the scoreboard onto the RTSP stream itself
          // (overlay is firmware-unilateral, #6), so the app must NOT draw its
          // own overlay here — doing both showed a doubled scoreboard. The app
          // only authors + pushes the layout (PushOverlayLayout); the preview
          // shows the firmware-baked stream as-is.
          // No buttons inside the surface — Preview/Stop is in the parent layout.
          LivePreviewView(
            deviceId: activeId,
            label: isLive ? 'LIVE PREVIEW' : 'PREVIEW',
            showButtons: false,
            paused: !onMatchTab,
            isStreaming: matchState.streaming,
          ),
        // The Single|Both toggle now lives below the feed next to the Preview
        // button (see the parent layout), not overlaid on the feed.
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// PREVIEW UNAVAILABLE PLACEHOLDER
// ---------------------------------------------------------------------------

/// Shown in [_LiveThumb] when the WiFi Direct connection has failed
/// (e.g. iOS does not support WiFi Direct local preview). Displays a
/// static scoreboard so the session UI stays fully functional.
class _PreviewUnavailablePlaceholder extends StatelessWidget {
  const _PreviewUnavailablePlaceholder({
    required this.matchState,
    required this.isLive,
  });

  final LiveMatchState matchState;
  final bool isLive;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(color: T.panel),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.videocam_off, size: 28, color: T.ink3),
                const SizedBox(height: 8),
                const Text(
                  'Preview not available',
                  style: TextStyle(
                    fontSize: 11,
                    color: T.ink2,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
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
                    child: _ScoreBlock(
                      label: matchState.homeName,
                      score: matchState.scoreHome,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      '${matchState.phaseLabel} · ${matchState.clockText}',
                      style: const TextStyle(
                        fontFamily: T.mono,
                        fontSize: 10,
                        color: T.ink2,
                      ),
                    ),
                  ),
                  Expanded(
                    child: _ScoreBlock(
                      label: matchState.awayName,
                      score: matchState.scoreAway,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// SCORE BLOCK
// ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------
// EVENT LOG ROW
// ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------
// TOGGLE ROW (used by start/end prompts)
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

// ---------------------------------------------------------------------------
// BORDER EXTENSION
// ---------------------------------------------------------------------------

extension on Border {
  BoxDecoration toBoxDecoration() => BoxDecoration(border: this);
}

// ---------------------------------------------------------------------------
// BLE HELPER — fire-and-forget command when a camera is connected
// ---------------------------------------------------------------------------

void _sendIfConnected(WidgetRef ref, BleCommand cmd) {
  final id = ref.read(activeCameraIdProvider);
  if (id == null) return;
  final connState = ref.read(connectionStateProvider(id)).valueOrNull;
  if (connState != CameraConnectionState.connected) return;
  unawaited(ref.read(bleServiceProvider).sendCommand<void>(id, cmd));
}

/// Persist the just-ended match into the Library: flips its team_match row to
/// 'past' with the final score + events so it appears on the Video/Library page.
/// No-op for an ad-hoc session with no library row (matchId == null).
void _finalizeMatchToLibrary(WidgetRef ref) {
  final ctl = ref.read(liveMatchProvider.notifier);
  final matchId = ctl.matchId;
  final result = ctl.resultString();
  if (matchId == null) {
    debugPrint('[finalize] SKIP — no matchId (ad-hoc session, no library row)');
    return;
  }
  debugPrint('[finalize] writing matchId=$matchId result=$result');
  unawaited(
    ref
        .read(teamsDaoProvider)
        .finalizeMatch(matchId, result: result, eventsJson: ctl.eventsJson())
        .then(
          (ok) => debugPrint('[finalize] done updated=$ok matchId=$matchId'),
        )
        .catchError((Object e) {
          debugPrint('[finalize] ERROR $e');
        }),
  );
}

String _joinRtmp(String base, String key) {
  if (key.isEmpty) return base;
  return base.endsWith('/') ? '$base$key' : '$base/$key';
}

/// Non-dismissible mid-match streaming credential prompt. Returns the full RTMP
/// ingest URL, or null when cancelled (start nothing). `isDismissible` and
/// `enableDrag` are false so an accidental tap-outside can't leave streaming
/// half-started; only an explicit Cancel/Start resolves it.
Future<String?> _promptStreamCredential(BuildContext context) {
  final controller = TextEditingController();
  String? error;
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: T.bg,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSt) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Start streaming',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: T.ink,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'No streaming destination set for this match. Paste a full '
                  'RTMP URL (including the stream key) to start now.',
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
                    Expanded(
                      child: WfButton(
                        label: 'Cancel',
                        onPressed: () => Navigator.of(ctx).pop(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: WfButton(
                        label: 'Start streaming',
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
    ),
  );
}
