// Download-sheet sub-views — the in-flight progress surface, the shared
// busy (rendering / reconnecting) surface and the sheet's radio/check
// primitives. Split from download_sheet.dart; behavior is unchanged.

import 'package:flutter/material.dart';

import '../../../core/models/wifi.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/wf_button.dart';

/// The bottom-sheet drag handle shared by every download-sheet surface.
class SheetHandle extends StatelessWidget {
  const SheetHandle({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 36,
        height: 4,
        decoration: BoxDecoration(
          color: T.fillMid,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

/// In-flight download surface: status headline, progress bar, byte/rate/percent
/// row and the Cancel/Close (+ Done when completed) actions.
class DownloadProgressView extends StatelessWidget {
  const DownloadProgressView({
    super.key,
    required this.subtitle,
    required this.progress,
    required this.error,
    required this.onCancel,
    required this.onClose,
  });

  /// "date · opponent" line under the status headline.
  final String subtitle;
  final VideoDownloadProgress? progress;
  final String? error;

  /// Cancel a running download, then dismiss. Only called while non-terminal.
  final VoidCallback onCancel;

  /// Dismiss the sheet (terminal states).
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final p = progress;
    final fraction = p?.fraction ?? 0;
    final received = ((p?.bytesReceived ?? 0) / 1024 / 1024).toStringAsFixed(1);
    final total = ((p?.bytesTotal ?? 0) / 1024 / 1024).toStringAsFixed(1);
    final kbps = (p?.kbps ?? 0).toStringAsFixed(0);
    final status = switch (p?.status) {
      DownloadStatus.queued => 'Queued',
      DownloadStatus.running => 'Downloading',
      DownloadStatus.paused => 'Paused',
      DownloadStatus.completed => 'Completed',
      DownloadStatus.failed => 'Failed',
      DownloadStatus.cancelled => 'Cancelled',
      null => 'Starting',
    };
    final terminal = p?.isTerminal ?? false;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SheetHandle(),
          const SizedBox(height: 14),
          Text(
            status,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: T.ink,
            ),
          ),
          const SizedBox(height: 4),
          Text(subtitle, style: const TextStyle(fontSize: 12, color: T.ink2)),
          const SizedBox(height: 18),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 6,
              backgroundColor: T.fillMid,
              valueColor: const AlwaysStoppedAnimation<Color>(T.accent),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$received / $total MB',
                style: const TextStyle(
                  fontFamily: T.mono,
                  fontSize: 11,
                  color: T.ink2,
                ),
              ),
              Text(
                '$kbps KB/s',
                style: const TextStyle(
                  fontFamily: T.mono,
                  fontSize: 11,
                  color: T.ink2,
                ),
              ),
              Text(
                '${(fraction * 100).toStringAsFixed(0)}%',
                style: const TextStyle(
                  fontFamily: T.mono,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: T.ink,
                ),
              ),
            ],
          ),
          if (p?.errorMessage != null) ...[
            const SizedBox(height: 10),
            Text(
              p!.errorMessage!,
              style: const TextStyle(fontSize: 12, color: T.danger),
            ),
          ] else if (error != null) ...[
            const SizedBox(height: 10),
            Text(error!, style: const TextStyle(fontSize: 12, color: T.danger)),
          ],
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: WfButton(
                  label: terminal ? 'Close' : 'Cancel',
                  onPressed: terminal ? onClose : onCancel,
                ),
              ),
              if (terminal && p?.status == DownloadStatus.completed) ...[
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: WfButton(
                    label: 'Done',
                    variant: WfButtonVariant.primary,
                    onPressed: onClose,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// Shared spinner surface for the pre-download busy states (rendering an
/// overlay, or waiting for the WiFi link). [title] is the bold headline,
/// [subtitle] the muted explanation.
class DownloadBusyView extends StatelessWidget {
  const DownloadBusyView({
    super.key,
    required this.title,
    required this.subtitle,
    required this.error,
    required this.onCancel,
  });

  final String title;
  final String subtitle;
  final String? error;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SheetHandle(),
          const SizedBox(height: 18),
          Row(
            children: [
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  valueColor: AlwaysStoppedAnimation<Color>(T.accent),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: T.ink,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(subtitle, style: const TextStyle(fontSize: 12, color: T.ink2)),
          if (error != null) ...[
            const SizedBox(height: 10),
            Text(error!, style: const TextStyle(fontSize: 12, color: T.danger)),
          ],
          const SizedBox(height: 18),
          WfButton(label: 'Cancel', onPressed: onCancel),
        ],
      ),
    );
  }
}

/// Filled-circle radio indicator used by the download-option rows.
class SheetRadio extends StatelessWidget {
  const SheetRadio({super.key, required this.on});
  final bool on;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: on ? T.accent : Colors.transparent,
        border: Border.all(color: on ? T.accent : T.hair, width: 2),
      ),
      alignment: Alignment.center,
      child: on
          ? Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: T.accentInk,
                shape: BoxShape.circle,
              ),
            )
          : null,
    );
  }
}

/// Checkbox indicator used by the overlay toggle row.
class SheetCheckBox extends StatelessWidget {
  const SheetCheckBox({super.key, required this.on});
  final bool on;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        color: on ? T.accent : Colors.transparent,
        border: Border.all(color: on ? T.accent : T.hair, width: 2),
      ),
      alignment: Alignment.center,
      child: on
          ? const Icon(Icons.check_rounded, size: 13, color: T.accentInk)
          : null,
    );
  }
}
