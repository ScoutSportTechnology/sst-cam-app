import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/wifi.dart';
import '../../../core/services/clip_service.dart';
import '../../../core/services/gallery_service.dart';
import '../../../core/wifi/wifi_providers.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/wf_button.dart';
import '../../../core/state/db_providers.dart'
    show clipServiceProvider, videoPathServiceProvider;
import '../../camera/camera_state.dart' show activeCameraIdProvider;
import '../video_state.dart' show isOnDeviceProvider, LibraryMatch, LibraryEvent;

class DownloadSheet extends ConsumerStatefulWidget {
  const DownloadSheet({
    super.key,
    required this.match,
    required this.selectedEvents,
    required this.allEvents,
  });
  final LibraryMatch match;
  /// Events the user has checked (for "Selected highlights" option).
  final List<LibraryEvent> selectedEvents;
  /// All events in the match (for "All highlights" option).
  final List<LibraryEvent> allEvents;

  @override
  ConsumerState<DownloadSheet> createState() => _DownloadSheetState();
}

class _DownloadSheetState extends ConsumerState<DownloadSheet> {
  VideoDownloadHandle? _handle;
  VideoDownloadProgress? _progress;
  String? _error;
  // 'full' | 'all' | 'selected'
  String _mode = 'full';

  @override
  void dispose() {
    // Sheet is closing — if a download is mid-flight, leave it running.
    super.dispose();
  }

  Future<void> _start() async {
    setState(() => _error = null);

    if (_mode == 'full') {
      await _startFullDownload();
    } else {
      await _startClips(
        _mode == 'all' ? widget.allEvents : widget.selectedEvents,
      );
    }
  }

  Future<void> _startFullDownload() async {
    final deviceId = ref.read(activeCameraIdProvider);
    if (deviceId == null) {
      setState(() => _error = 'Connect a camera first');
      return;
    }

    // Capture references before the async call so the onDone callback can
    // run correctly even if the sheet has already been dismissed (mounted=false).
    final matchId = widget.match.id;
    final pathSvc = ref.read(videoPathServiceProvider);
    final container = ProviderScope.containerOf(context);

    try {
      final handle = await ref.read(wifiServiceProvider).downloadRecording(
        deviceId,
        matchId,
      );
      _handle = handle;
      handle.progress.listen(
        (p) {
          if (mounted) setState(() => _progress = p);
        },
        onDone: () async {
          // The file is now on device (MockWifiService publishes completed
          // only after _writePlaceholder finishes). Invalidate the provider
          // and save to gallery regardless of whether the sheet is still open.
          container.invalidate(isOnDeviceProvider(matchId));
          final path = await pathSvc.recordingPath(matchId);
          await GalleryService.saveVideo(
            sourcePath: path,
            displayName: '$matchId.mp4',
          );
        },
        onError: (e) {
          if (mounted) setState(() => _error = e.toString());
        },
        cancelOnError: true,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  Future<void> _startClips(List<LibraryEvent> events) async {
    if (events.isEmpty) {
      setState(() => _error = 'No events selected');
      return;
    }
    final onDevice = await ref.read(isOnDeviceProvider(widget.match.id).future);
    if (!onDevice) {
      if (mounted) setState(() => _error = 'Download the full game first');
      return;
    }
    final clipSvc = ref.read(clipServiceProvider);
    final videoPathSvc = ref.read(videoPathServiceProvider);
    final sourcePath = await videoPathSvc.recordingPath(widget.match.id);
    int created = 0;
    for (final event in events) {
      try {
        final startSeconds = (event.timeSeconds - 15).clamp(0, double.infinity).toInt();
        await clipSvc.trim(
          matchId: widget.match.id,
          sourcePath: sourcePath,
          startSeconds: startSeconds,
          durationSeconds: 30,
          label: event.label,
        );
        created++;
      } on ClipTrimException catch (e) {
        if (mounted) setState(() => _error = 'Clip failed: ${e.message}');
        return;
      }
    }
    if (mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$created clip${created == 1 ? '' : 's'} saved')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final running = _handle != null;
    if (running) return _buildProgress();
    final fullSize = '${widget.match.fullSizeMb} MB';
    final selectedCount = widget.selectedEvents.length;
    final allCount = widget.allEvents.length;
    final opts = <_Opt>[
      _Opt(key: 'full', label: 'Full game',
          sub: '${widget.match.fullDuration} · $fullSize · ~12 min @ WiFi'),
      if (allCount > 0)
        _Opt(key: 'all', label: 'All highlights',
            sub: '$allCount event${allCount == 1 ? '' : 's'} · requires full game on device'),
      if (selectedCount > 0)
        _Opt(key: 'selected', label: 'Selected highlights',
            sub: '$selectedCount event${selectedCount == 1 ? '' : 's'} selected · requires full game on device'),
    ];

    return Padding(
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
          const Text(
            'Download',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: T.ink,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${widget.match.date} · ${widget.match.opponent}',
            style: const TextStyle(fontSize: 12, color: T.ink2),
          ),
          const SizedBox(height: 14),
          ...opts.map(
            (o) {
              final selected = _mode == o.key;
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: GestureDetector(
                  onTap: () => setState(() => _mode = o.key),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: selected ? T.accentSoft : T.fillSoft,
                      border: Border.all(
                        color: selected ? T.accent : T.hair,
                        width: selected ? 1.4 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        _Radio(on: selected),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                o.label,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: T.ink,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                o.sub,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: T.ink2,
                                  fontFamily: T.mono,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: WfButton(
                  label: 'Cancel',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: WfButton(
                  label: 'Start download',
                  variant: WfButtonVariant.primary,
                  onPressed: _start,
                ),
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(
              _error!,
              style: const TextStyle(fontSize: 12, color: T.danger),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildProgress() {
    final p = _progress;
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
          Text(
            status,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: T.ink,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${widget.match.date} · ${widget.match.opponent}',
            style: const TextStyle(fontSize: 12, color: T.ink2),
          ),
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
          ] else if (_error != null) ...[
            const SizedBox(height: 10),
            Text(
              _error!,
              style: const TextStyle(fontSize: 12, color: T.danger),
            ),
          ],
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: WfButton(
                  label: terminal ? 'Close' : 'Cancel',
                  onPressed: () async {
                    if (!terminal) await _handle?.cancel();
                    if (mounted) Navigator.of(context).pop();
                  },
                ),
              ),
              if (terminal && p?.status == DownloadStatus.completed) ...[
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: WfButton(
                    label: 'Done',
                    variant: WfButtonVariant.primary,
                    onPressed: () => Navigator.of(context).pop(),
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

class _Opt {
  const _Opt({
    required this.key,
    required this.label,
    required this.sub,
  });
  final String key;
  final String label;
  final String sub;
}

class _Radio extends StatelessWidget {
  const _Radio({required this.on});
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
