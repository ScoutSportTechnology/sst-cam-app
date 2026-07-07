// Session screen — covers pre-game, period-active, period-break and ended
// phases. Recording / streaming controls are independent of the period timer
// so the user can record before kickoff or after the final whistle.
//
// Layout only: the BLE flows live in session_actions.dart, the bottom-sheet
// prompts in session_modals.dart, and the display/control widgets in
// session_widgets.dart / session_controls.dart.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/ble/ble_providers.dart';
import '../../../core/models/command.dart';
import '../../../core/models/device.dart';
import '../../../core/state/device_health.dart' show captureBlockedProvider;
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/device_health_banner.dart';
import '../../../core/widgets/output_camera_toggle.dart';
import '../../../core/widgets/preview_controls_row.dart';
import '../../../core/widgets/wf_card.dart';
import '../../../core/wifi/wifi_providers.dart' show livePreviewEnabledProvider;
import '../../camera/camera_state.dart' show activeCameraIdProvider;
import '../match_state.dart' show UpcomingMatch;
import 'session_actions.dart';
import 'session_controls.dart';
import 'session_state.dart';
import 'session_widgets.dart';

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
    // U3 health gate: preview / recording START / streaming START are blocked
    // while the device is inoperable (or health unknown while connected).
    // Pause/resume-of-clock, stop actions and the event log stay usable.
    final captureBlocked = ref.watch(captureBlockedProvider);

    return Scaffold(
      backgroundColor: T.bg,
      body: SafeArea(
        child: Column(
          children: [
            SessionTopBar(
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
              child: SessionLiveThumb(
                matchState: state,
                isLive: isPeriodActive,
              ),
            ),
            // Preview controls — below the feed (not overlaid), via the shared
            // PreviewControlsRow (same widget as the main camera card). Two
            // columns mirroring the Mark event / phase action row below, so the
            // Preview button's width and right edge line up with the Mark event
            // button. Only shown when a camera is connected.
            if (activeId != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
                child: PreviewControlsRow(deviceId: activeId),
              ),
            // Manual tracking — pick the output camera mid-match while watching
            // the live preview.
            if (activeId != null && previewOn)
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
                child: OutputCameraToggle(deviceId: activeId, full: true),
              ),
            // U3 health surface — inoperable banner / recovering note, shared
            // with the main page + setup screen (one widget, no divergence).
            const DeviceHealthNotice(margin: EdgeInsets.fromLTRB(10, 6, 10, 0)),
            const SessionNoticeBanner(),
            SessionPrimaryActionRow(
              state: state,
              onMarkEvent: isPeriodActive
                  ? () => showSessionEventSheet(
                      context,
                      ref,
                      homeTeamId: match.team.id,
                    )
                  : null,
              onKickoff: () => sessionKickoff(context, ref, ctl, state),
              onEndPeriod: () {
                sendIfConnected(
                  ref,
                  MatchControlCommand(
                    action: BleMatchControlAction.periodEnd,
                    period: state.currentPeriod,
                  ),
                );
                ctl.endPeriod();
              },
              onStartNextPeriod: () {
                sendIfConnected(
                  ref,
                  MatchControlCommand(
                    action: BleMatchControlAction.periodStart,
                    period: state.currentPeriod + 1,
                  ),
                );
                ctl.startPeriod();
              },
              onEndMatch: () => confirmSessionEnd(context, ref, ctl, state),
            ),
            if (isEnded) const SessionEndedBanner(),
            const Divider(height: 1, color: T.rule),
            const WfSection(
              'Event log',
              padding: EdgeInsets.fromLTRB(14, 10, 14, 4),
            ),
            Expanded(child: _buildEventLog(state)),
            SessionBottomControls(
              state: state,
              onTimerTap: () {
                final isRunning = state.timer == MatchTimer.running;
                sendIfConnected(
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
              // Recording START is health-gated; pause/resume of a running
              // recording stays available (the firmware refuses a resume with
              // DEVICE_INOPERABLE if the camera died meanwhile — surfaced by
              // the snackbar backstop in sendStartIfConnected).
              onRecToggle:
                  (connected && !(captureBlocked && state.rec == RecState.idle))
                  ? () {
                      final currentRec = state.rec;
                      ctl.toggleRecPause();
                      if (currentRec == RecState.idle) {
                        sendStartIfConnected(
                          context,
                          ref,
                          RecordingControlCommand(
                            action: RecordingControlAction.start,
                            quality: state.recordQuality,
                            captureGroupId:
                                ref.read(liveMatchProvider.notifier).matchId ??
                                const Uuid().v4(),
                          ),
                        );
                      } else if (currentRec == RecState.recording) {
                        sendIfConnected(
                          ref,
                          RecordingControlCommand(
                            action: RecordingControlAction.pause,
                          ),
                        );
                      } else if (currentRec == RecState.paused) {
                        sendStartIfConnected(
                          context,
                          ref,
                          RecordingControlCommand(
                            action: RecordingControlAction.resume,
                          ),
                        );
                      }
                    }
                  : null,
              // Streaming START is health-gated; stopping a running stream is
              // always allowed.
              onStreamToggle:
                  (connected && !(captureBlocked && !state.streaming))
                  ? () => toggleSessionStream(context, ref, ctl, state)
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
      itemBuilder: (_, i) => SessionEventLogRow(e: visible[i]),
    );
  }
}
