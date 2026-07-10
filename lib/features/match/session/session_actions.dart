// Session actions — the BLE send helpers plus the multi-step flows the
// session screen triggers (kickoff, end-of-match confirm, mid-match stream
// toggle, event capture, finalize). Split from session_screen.dart so the
// screen file stays layout-only; behavior is unchanged.

import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../../core/ble/ble_providers.dart';
import '../../../core/models/command.dart';
import '../../../core/models/device.dart';
import '../../../core/models/streaming.dart' show resolveWireStream, joinRtmp;
import '../../../core/services/log_service.dart';
import '../../../core/state/db_providers.dart' show teamsDaoProvider;
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/notify.dart';
import '../../camera/camera_state.dart' show activeCameraIdProvider;
import '../../settings/streaming/streaming_destination_form_sheet.dart'
    show showStreamingDestinationFormSheet;
import 'event_sheet.dart';
import 'session_modals.dart';
import 'session_state.dart';

final _log = Logger('SessionActions');

/// Sends [cmd] only when a camera is connected. Returns true when the command
/// was dispatched, false when skipped (no device / not connected) — callers that
/// mutate UI state on the back of a send (e.g. streaming on/off) gate on this so
/// app and camera don't diverge.
bool sendIfConnected(WidgetRef ref, BleCommand cmd) {
  final id = ref.read(activeCameraIdProvider);
  if (id == null) {
    _log.debug('skip ${cmd.runtimeType}: no active camera');
    return false;
  }
  final connState = ref.read(connectionStateProvider(id)).valueOrNull;
  if (connState != CameraConnectionState.connected) {
    _log.warn('skip ${cmd.runtimeType}: camera not connected ($connState)');
    return false;
  }
  _log.debug('send ${cmd.runtimeType} → $id');
  unawaited(ref.read(bleServiceProvider).sendCommand<void>(id, cmd));
  return true;
}

/// [sendIfConnected] for capture START commands (record/stream/resume): the
/// firmware health-gates these with the typed DEVICE_INOPERABLE refusal (the
/// backstop behind the app-side gate — a camera can die in the gap between
/// health flipping and the UI reacting). That refusal surfaces as a clear
/// snackbar, never a silent failure (U3).
bool sendStartIfConnected(BuildContext context, WidgetRef ref, BleCommand cmd) {
  final id = ref.read(activeCameraIdProvider);
  if (id == null) {
    _log.debug('skip START ${cmd.runtimeType}: no active camera');
    return false;
  }
  final connState = ref.read(connectionStateProvider(id)).valueOrNull;
  if (connState != CameraConnectionState.connected) {
    _log.warn('skip START ${cmd.runtimeType}: not connected ($connState)');
    return false;
  }
  _log.info('start-capture ${cmd.runtimeType} → $id');
  unawaited(
    ref.read(bleServiceProvider).sendCommand<void>(id, cmd).then((resp) {
      if (resp.isDeviceInoperable) {
        // Log fires regardless of mount state (that is the point); the helper
        // guards the actual snackbar on context.mounted internally.
        showErrorSnack(
          // ignore: use_build_context_synchronously
          context,
          'Camera inoperable — could not start. See Diagnostics for details.',
          source: 'SessionActions',
        );
      }
    }),
  );
  return true;
}

/// Persist the just-ended match into the Library via the SINGLE finalize path
/// (shared with the away-ended reconcile): flips its team_match row to 'past'
/// with the final score + events, then clears the persisted live-match store
/// last. No-op for an ad-hoc session with no library row (matchId == null).
void finalizeMatchToLibrary(WidgetRef ref) {
  unawaited(ref.read(liveMatchProvider.notifier).finalizeToLibrary());
}

/// Resolves the per-match RTMP wire URL for a streaming START: the credential
/// stored on the match at setup, or — if none — a one-off prompt (stored on the
/// match). Returns null to mean "start nothing" (prompt cancelled, unresolvable,
/// or a DB/resolution error — the error case shows a snack).
///
/// Shared by the mid-match toggle AND the kickoff prompt so BOTH dispatch a
/// START that carries the destination: a START with no rtmpUrl is rejected by
/// the firmware ("no destination provided or configured") and streams nothing.
Future<String?> resolveStreamWireUrl(BuildContext context, WidgetRef ref) async {
  final matchId = ref.read(liveMatchProvider.notifier).matchId;
  try {
    if (matchId != null) {
      final m = await ref.read(teamsDaoProvider).getMatchById(matchId);
      final url = m?.rtmpUrl;
      if (url != null && url.isNotEmpty) {
        final key = m!.streamKey;
        return (key == null || key.isEmpty) ? url : joinRtmp(url, key);
      }
    }
    if (!context.mounted) return null;
    // Same URL+key (and RTSP) form as setup — entered fresh for this match.
    final draft = await showStreamingDestinationFormSheet(context);
    if (draft == null) return null; // cancelled — start nothing
    final resolved = resolveWireStream(draft.config);
    if (resolved == null) return null;
    if (matchId != null) {
      await ref
          .read(teamsDaoProvider)
          .setMatchStreamingCredential(
            matchId,
            rtmpUrl: resolved.storeUrl,
            streamKey: resolved.storeKey,
          );
    }
    return resolved.wireUrl;
  } catch (e, st) {
    // Log fires regardless of mount state; helper guards the snackbar itself.
    showErrorSnack(
      // ignore: use_build_context_synchronously
      context,
      'Could not start streaming.',
      source: 'SessionActions',
      error: e,
      stackTrace: st,
    );
    return null;
  }
}

/// Toggle streaming mid-match. Stopping is unconditional. Starting resolves
/// the per-match credential: use the one stored at setup, or — if none — prompt
/// for a one-off, store it on the match, then start. Cancelling the prompt
/// starts nothing and leaves the session unchanged.
Future<void> toggleSessionStream(
  BuildContext context,
  WidgetRef ref,
  LiveMatchController ctl,
  LiveMatchState state,
) async {
  if (state.streaming) {
    _log.info('stream toggle → stop');
    sendIfConnected(
      ref,
      StreamingControlCommand(action: StreamingControlAction.stop),
    );
    ctl.setStreaming(false);
    return;
  }
  _log.info('stream toggle → start (resolving destination)');

  final wireUrl = await resolveStreamWireUrl(context, ref);
  if (wireUrl == null) return; // cancelled / unresolvable — start nothing

  if (!context.mounted) return;
  final sent = sendStartIfConnected(
    context,
    ref,
    StreamingControlCommand(
      action: StreamingControlAction.start,
      rtmpUrl: wireUrl,
      quality: state.streamQuality,
    ),
  );
  // Only reflect streaming in the UI when the start actually dispatched — a
  // mid-await disconnect would otherwise show "streaming" while the camera
  // never received the command.
  if (sent) {
    ctl.setStreaming(true);
  } else {
    showWarnSnack(
      context,
      'Camera disconnected — streaming not started.',
      source: 'SessionActions',
    );
  }
}

/// Kickoff flow: on the very first period, prompt for what to start with the
/// match timer (recording / streaming) unless both already run; subsequent
/// periods continue with whatever capture state is active.
Future<void> sessionKickoff(
  BuildContext context,
  WidgetRef ref,
  LiveMatchController ctl,
  LiveMatchState state,
) async {
  _log.info(
    'kickoff period=${state.currentPeriod + 1} '
    'rec=${state.rec} streaming=${state.streaming}',
  );
  // Kickoff prompt — only on the very first period. Subsequent periods
  // continue with whatever recording / streaming state is active.
  if (state.currentPeriod != 0) {
    sendIfConnected(
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
    sendIfConnected(
      ref,
      MatchControlCommand(
        action: BleMatchControlAction.kickoff,
        period: state.currentPeriod + 1,
      ),
    );
    ctl.startPeriod();
    return;
  }
  final choice = await showSessionStartPrompt(
    context,
    askRecord: !recAlreadyOn,
    askStream: !streamAlreadyOn,
  );
  if (choice == null) return;
  sendIfConnected(
    ref,
    MatchControlCommand(
      action: BleMatchControlAction.kickoff,
      period: state.currentPeriod + 1,
    ),
  );
  // Honor the start-prompt choices on the camera. startPeriod only flips the
  // local UI state; without these explicit control commands the firmware
  // records/streams nothing (the match dir stays empty).
  if (!context.mounted) return;
  if (choice.$1 == true) {
    sendStartIfConnected(
      context,
      ref,
      RecordingControlCommand(
        action: RecordingControlAction.start,
        quality: state.recordQuality,
      ),
    );
  }
  var streamingStarted = false;
  if (choice.$2 == true) {
    // Resolve the destination exactly like the mid-match toggle — a START with
    // no rtmpUrl is rejected by the firmware ("no destination provided"), which
    // is the bug where kickoff-streaming silently did nothing.
    final wireUrl = await resolveStreamWireUrl(context, ref);
    if (wireUrl != null && context.mounted) {
      streamingStarted = sendStartIfConnected(
        context,
        ref,
        StreamingControlCommand(
          action: StreamingControlAction.start,
          rtmpUrl: wireUrl,
          quality: state.streamQuality,
        ),
      );
    }
  }
  // Reflect the ACTUAL started state, not the prompt choice — a cancelled or
  // failed destination resolution must not leave the UI showing "streaming".
  ctl.startPeriod(startRecording: choice.$1, startStreaming: streamingStarted);
}

/// End-of-match flow: confirm via the end prompt (when anything is running),
/// push the final whistle + chosen stop commands, then finalize to the
/// Library through the single finalize path.
Future<void> confirmSessionEnd(
  BuildContext context,
  WidgetRef ref,
  LiveMatchController ctl,
  LiveMatchState state,
) async {
  final recOn = state.rec != RecState.idle;
  final streamOn = state.streaming;
  _log.info('end-match confirm rec=$recOn stream=$streamOn');
  if (!recOn && !streamOn) {
    // Nothing is running — no toggles to ask about, just end.
    sendIfConnected(
      ref,
      MatchControlCommand(
        action: BleMatchControlAction.finalWhistle,
        period: state.currentPeriod,
      ),
    );
    ctl.endMatch(stopRecording: false, stopStreaming: false);
    finalizeMatchToLibrary(ref);
    return;
  }
  final choice = await showSessionEndPrompt(
    context,
    askStopRec: recOn,
    askStopStream: streamOn,
  );
  if (choice == null) return;
  sendIfConnected(
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
    sendIfConnected(
      ref,
      RecordingControlCommand(action: RecordingControlAction.stop),
    );
  }
  if (choice.$2 == true) {
    sendIfConnected(
      ref,
      StreamingControlCommand(action: StreamingControlAction.stop),
    );
  }
  ctl.endMatch(
    stopRecording: choice.$1 ?? false,
    stopStreaming: choice.$2 ?? false,
  );
  finalizeMatchToLibrary(ref);
}

/// Open the Mark-event sheet and wire its save through to the live-match
/// controller + the firmware (score routing, banner events).
void showSessionEventSheet(
  BuildContext context,
  WidgetRef ref, {
  required String homeTeamId,
}) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: T.bg,
    isScrollControlled: true,
    barrierColor: T.barrierColor,
    builder: (_) => EventSheet(
      homeTeamId: homeTeamId,
      onSave: (type, team, jersey) {
        _log.info('event "$type" team=$team jersey=${jersey ?? "-"}');
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
          final teamId = team == live.homeName ? homeTeamId : live.awayName;
          sendIfConnected(ref, ScoreUpdateCommand(teamId: teamId, delta: 1));
          sendIfConnected(
            ref,
            BannerEventCommand(
              templateId: 'goal',
              durationSeconds: 5,
              params: params,
              playerId: playerId,
            ),
          );
        } else if (type == 'Yellow Card') {
          sendIfConnected(
            ref,
            BannerEventCommand(
              templateId: 'yellow_card',
              durationSeconds: 4,
              params: params,
              playerId: playerId,
            ),
          );
        } else if (type == 'Red Card') {
          sendIfConnected(
            ref,
            BannerEventCommand(
              templateId: 'red_card',
              durationSeconds: 4,
              params: params,
              playerId: playerId,
            ),
          );
        } else if (type == 'Sub') {
          sendIfConnected(
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
