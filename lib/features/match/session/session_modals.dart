// Session modals — the kickoff start prompt and the end-of-match confirm
// bottom sheets. Split from session_screen.dart; behavior is unchanged.

import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/indicators.dart' show WfSwitch;
import '../../../core/widgets/wf_button.dart';

// ---------------------------------------------------------------------------
// START PROMPT — kickoff bottom sheet
// ---------------------------------------------------------------------------

/// Returns `(startRecording?, startStreaming?)` or null on cancel. Each
/// element is null when the corresponding control wasn't shown (the thing
/// was already running before kickoff), so the caller can leave that
/// state untouched.
Future<(bool?, bool?)?> showSessionStartPrompt(
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
      builder: (ctx, setSt) => _PromptSheet(
        title: 'Kickoff',
        subtitle: subtitle,
        toggles: [
          if (askRecord)
            _ToggleRow(
              label: 'Start recording',
              value: record,
              onChanged: (v) => setSt(() => record = v),
            ),
          if (askRecord && askStream) const Divider(height: 1, color: T.rule),
          if (askStream)
            _ToggleRow(
              label: 'Start streaming',
              value: stream,
              onChanged: (v) => setSt(() => stream = v),
            ),
        ],
        confirmLabel: 'Start match',
        confirmVariant: WfButtonVariant.primary,
        onConfirm: () => Navigator.of(
          ctx,
        ).pop((askRecord ? record : null, askStream ? stream : null)),
        onCancel: () => Navigator.of(ctx).pop(),
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
Future<(bool?, bool?)?> showSessionEndPrompt(
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
      builder: (ctx, setSt) => _PromptSheet(
        title: 'End match',
        subtitle: subtitle,
        toggles: [
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
        ],
        confirmLabel: 'End match',
        confirmVariant: WfButtonVariant.danger,
        onConfirm: () => Navigator.of(
          ctx,
        ).pop((askStopRec ? stopRec : null, askStopStream ? stopStream : null)),
        onCancel: () => Navigator.of(ctx).pop(),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// PROMPT SHEET — shared scaffold for both prompts
// ---------------------------------------------------------------------------

/// The shared bottom-sheet scaffold both prompts render: drag handle, title,
/// subtitle, toggle rows, Cancel + confirm buttons. Layout is identical to the
/// two hand-rolled sheets it replaces.
class _PromptSheet extends StatelessWidget {
  const _PromptSheet({
    required this.title,
    required this.subtitle,
    required this.toggles,
    required this.confirmLabel,
    required this.confirmVariant,
    required this.onConfirm,
    required this.onCancel,
  });

  final String title;
  final String subtitle;
  final List<Widget> toggles;
  final String confirmLabel;
  final WfButtonVariant confirmVariant;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
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
            Text(
              title,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: T.ink,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(fontSize: 11, color: T.ink2, height: 1.4),
            ),
            const SizedBox(height: 14),
            ...toggles,
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: WfButton(label: 'Cancel', onPressed: onCancel),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: WfButton(
                    label: confirmLabel,
                    variant: confirmVariant,
                    onPressed: onConfirm,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
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
