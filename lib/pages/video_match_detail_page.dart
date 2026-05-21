import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/wifi.dart';
import '../services/clip_service.dart';
import '../services/video_path_service.dart';
import '../state/app_data.dart';
import '../state/ble_providers.dart';
import '../state/db_providers.dart' show clipServiceProvider;
import '../state/wifi_providers.dart';
import '../core/theme/tokens.dart';
import '../core/widgets/indicators.dart';
import '../core/widgets/wf_button.dart';
import '../core/widgets/wf_card.dart';
import '../core/widgets/wf_chip.dart';

class VideoMatchDetailPage extends ConsumerStatefulWidget {
  const VideoMatchDetailPage({super.key, required this.matchId});
  final String matchId;

  @override
  ConsumerState<VideoMatchDetailPage> createState() =>
      _VideoMatchDetailPageState();
}

class _VideoMatchDetailPageState extends ConsumerState<VideoMatchDetailPage> {
  bool _overlaysOn = true;
  late Set<int> _selected;
  double _playheadFraction = 0.38;

  @override
  void initState() {
    super.initState();
    final m = _match();
    _selected = {
      for (int i = 0; i < (m?.events.length ?? 0); i++)
        if (i.isEven) i,
    };
  }

  LibraryMatch? _match() => ref.read(libraryMatchProvider(widget.matchId));

  @override
  Widget build(BuildContext context) {
    final match = ref.watch(libraryMatchProvider(widget.matchId));
    if (match == null) {
      return const Scaffold(body: Center(child: Text('Match not found')));
    }
    final selectedCount = _selected.length;

    return Scaffold(
      backgroundColor: T.bg,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(match.date),
            Text(
              '${match.opponent} · ${match.result}',
              style: const TextStyle(fontSize: 11, color: T.ink2),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          _Player(
            match: match,
            overlaysOn: _overlaysOn,
            playheadFraction: _playheadFraction,
          ),
          _Scrubber(
            match: match,
            value: _playheadFraction,
            onChanged: (v) => setState(() => _playheadFraction = v),
          ),
          _OverlayToggleRow(
            on: _overlaysOn,
            onChanged: (v) => setState(() => _overlaysOn = v),
          ),
          _EventsHeader(total: match.events.length, selected: selectedCount),
          Expanded(
            child: ListView.separated(
              padding: EdgeInsets.zero,
              itemCount: match.events.length,
              separatorBuilder: (_, _) =>
                  const Divider(height: 1, color: T.rule),
              itemBuilder: (_, i) {
                final e = match.events[i];
                final selected = _selected.contains(i);
                return _EventRow(
                  event: e,
                  selected: selected,
                  onTap: () {
                    setState(() {
                      if (selected) {
                        _selected.remove(i);
                      } else {
                        _selected.add(i);
                      }
                    });
                  },
                  onJump: () {
                    final maxSecs = _parseDuration(match.fullDuration);
                    if (maxSecs == 0) return;
                    setState(() => _playheadFraction = e.timeSeconds / maxSecs);
                  },
                );
              },
            ),
          ),
          _Footer(
            selectedCount: selectedCount,
            onDownload: () => _showDownloadSheet(context, match),
            onCreateClip: match.downloadState == 'all-local'
                ? () => _createClip(context, match)
                : null,
          ),
        ],
      ),
    );
  }

  void _showDownloadSheet(BuildContext context, LibraryMatch match) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: T.bg,
      isScrollControlled: true,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (_) =>
          _DownloadSheet(match: match, selectedCount: _selected.length),
    );
  }

  Future<void> _createClip(BuildContext context, LibraryMatch match) async {
    final clipSvc = ref.read(clipServiceProvider);
    final maxSecs = _parseDuration(match.fullDuration);
    if (maxSecs == 0) return;
    final startSeconds = (_playheadFraction * maxSecs).round();
    final durationSeconds = 30; // default 30-second clip

    // Source path: the local recording file in the app-private videos/ dir.
    // In mock mode this file may not exist — the error is surfaced below.
    final sourcePath = await VideoPathService().recordingPath(match.id);
    try {
      final clipPath = await clipSvc.trim(
        matchId: match.id,
        sourcePath: sourcePath,
        startSeconds: startSeconds,
        durationSeconds: durationSeconds,
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Clip saved: ${clipPath.split('/').last}'),
          action: SnackBarAction(
            label: 'Share',
            onPressed: () {/* share action wired in follow-up */},
          ),
        ),
      );
    } on ClipTrimException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Clip failed: $e')),
      );
    }
  }
}

int _parseDuration(String hms) {
  final parts = hms.split(':').map(int.parse).toList();
  if (parts.length == 3) return parts[0] * 3600 + parts[1] * 60 + parts[2];
  return parts[0] * 60 + parts[1];
}

class _Player extends StatelessWidget {
  const _Player({
    required this.match,
    required this.overlaysOn,
    required this.playheadFraction,
  });
  final LibraryMatch match;
  final bool overlaysOn;
  final double playheadFraction;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const ThumbPlaceholder(label: 'PLAYER'),
        Positioned.fill(
          child: Center(
            child: Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.4),
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.85),
                  width: 2,
                ),
              ),
              child: const Icon(Icons.play_arrow, color: Colors.white),
            ),
          ),
        ),
        if (overlaysOn) ...[
          Positioned(
            top: 8,
            left: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: T.bg.withValues(alpha: 0.85),
                border: Border.all(color: T.hair),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Text(
                    'NR',
                    style: TextStyle(
                      fontSize: 9,
                      color: T.ink2,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(width: 6),
                  Text(
                    '2',
                    style: TextStyle(
                      fontFamily: T.mono,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: T.ink,
                    ),
                  ),
                  SizedBox(width: 6),
                  Text(
                    '1H',
                    style: TextStyle(
                      fontFamily: T.mono,
                      fontSize: 9,
                      color: T.ink3,
                    ),
                  ),
                  SizedBox(width: 6),
                  Text(
                    '1',
                    style: TextStyle(
                      fontFamily: T.mono,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: T.ink,
                    ),
                  ),
                  SizedBox(width: 6),
                  Text(
                    'EFC',
                    style: TextStyle(
                      fontSize: 9,
                      color: T.ink2,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              color: T.accent,
              child: const Text(
                'GOAL · #07',
                style: TextStyle(
                  fontFamily: T.mono,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: T.accentInk,
                  letterSpacing: 0.4,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _Scrubber extends StatelessWidget {
  const _Scrubber({
    required this.match,
    required this.value,
    required this.onChanged,
  });
  final LibraryMatch match;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final maxSecs = _parseDuration(match.fullDuration);
    if (maxSecs == 0) return const SizedBox.shrink();
    final ticks = match.events.map((e) => e.timeSeconds / maxSecs).toList();
    final currentSec = (value * maxSecs).round();
    final m = (currentSec ~/ 60).toString().padLeft(2, '0');
    final s = (currentSec % 60).toString().padLeft(2, '0');

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
      child: Column(
        children: [
          SizedBox(
            height: 16,
            child: LayoutBuilder(
              builder: (_, c) {
                return GestureDetector(
                  onHorizontalDragUpdate: (d) {
                    final newVal = (d.localPosition.dx / c.maxWidth).clamp(
                      0.0,
                      1.0,
                    );
                    onChanged(newVal);
                  },
                  onTapDown: (d) {
                    final newVal = (d.localPosition.dx / c.maxWidth).clamp(
                      0.0,
                      1.0,
                    );
                    onChanged(newVal);
                  },
                  child: Stack(
                    children: [
                      Positioned(
                        left: 0,
                        right: 0,
                        top: 7,
                        child: Container(height: 2, color: T.fillSoft),
                      ),
                      Positioned(
                        left: 0,
                        top: 7,
                        child: Container(
                          height: 2,
                          width: c.maxWidth * value,
                          color: T.ink,
                        ),
                      ),
                      ...ticks.map(
                        (p) => Positioned(
                          left: c.maxWidth * p - 1,
                          top: 2,
                          child: Container(
                            width: 2,
                            height: 12,
                            color: T.accent,
                          ),
                        ),
                      ),
                      Positioned(
                        left: c.maxWidth * value - 6,
                        top: 2,
                        child: Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: T.ink,
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '$m:$s',
                  style: const TextStyle(
                    fontFamily: T.mono,
                    fontSize: 11,
                    color: T.ink,
                  ),
                ),
                Text(
                  match.fullDuration,
                  style: const TextStyle(
                    fontFamily: T.mono,
                    fontSize: 11,
                    color: T.ink2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OverlayToggleRow extends StatelessWidget {
  const _OverlayToggleRow({required this.on, required this.onChanged});
  final bool on;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
      decoration: const Border(
        bottom: BorderSide(color: T.rule),
      ).toBoxDecoration(),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'Overlays',
              style: TextStyle(fontSize: 11, color: T.ink2),
            ),
          ),
          WfChip(label: 'Score', active: on),
          const SizedBox(width: 6),
          WfChip(label: 'Events', active: on),
          const SizedBox(width: 8),
          WfSwitch(value: on, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _EventsHeader extends StatelessWidget {
  const _EventsHeader({required this.total, required this.selected});
  final int total;
  final int selected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            'Events · $total',
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: T.ink2,
              letterSpacing: 0.6,
            ),
          ),
          const Spacer(),
          WfNote('$selected selected'),
        ],
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({
    required this.event,
    required this.selected,
    required this.onTap,
    required this.onJump,
  });
  final LibraryEvent event;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onJump;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      onLongPress: onJump,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        color: selected ? T.accentSoft : Colors.transparent,
        child: Row(
          children: [
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: selected ? T.accent : Colors.transparent,
                border: Border.all(
                  color: selected ? T.accent : T.hair,
                  width: 1.6,
                ),
              ),
              alignment: Alignment.center,
              child: selected
                  ? const Icon(Icons.check, size: 12, color: T.accentInk)
                  : null,
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 44,
              child: GestureDetector(
                onTap: onJump,
                child: Text(
                  event.clock,
                  style: TextStyle(
                    fontFamily: T.mono,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: selected ? T.accent : T.ink,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                event.label,
                style: const TextStyle(fontSize: 13, color: T.ink),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.selectedCount,
    required this.onDownload,
    this.onCreateClip,
  });
  final int selectedCount;
  final VoidCallback onDownload;
  final VoidCallback? onCreateClip;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: const Border(
        top: BorderSide(color: T.rule),
      ).toBoxDecoration(),
      child: Row(
        children: [
          Expanded(
            child: WfButton(
              label: 'Clip',
              onPressed: onCreateClip,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: WfButton(
              label: selectedCount > 0
                  ? 'Download · $selectedCount clips'
                  : 'Download · options',
              variant: WfButtonVariant.primary,
              leading: const Text(
                '↓',
                style: TextStyle(
                  color: T.accentInk,
                  fontWeight: FontWeight.w700,
                ),
              ),
              onPressed: onDownload,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Download options sheet
// ---------------------------------------------------------------------------

class _DownloadSheet extends ConsumerStatefulWidget {
  const _DownloadSheet({required this.match, required this.selectedCount});
  final LibraryMatch match;
  final int selectedCount;

  @override
  ConsumerState<_DownloadSheet> createState() => _DownloadSheetState();
}

class _DownloadSheetState extends ConsumerState<_DownloadSheet> {
  String _selected = 'hisel';
  VideoDownloadHandle? _handle;
  VideoDownloadProgress? _progress;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.selectedCount == 0) _selected = 'full';
  }

  @override
  void dispose() {
    // Sheet is closing — if a download is mid-flight, leave it running. The
    // service holds the handle and global progress is observable via
    // `allDownloadsProgressProvider`.
    super.dispose();
  }

  Future<void> _start() async {
    final activeId = ref.read(activeCameraIdProvider);
    if (activeId == null) {
      setState(() => _error = 'Connect a camera first');
      return;
    }
    setState(() => _error = null);
    try {
      // BLE — get short-lived URL + auth token for the recording.
      final token = await ref
          .read(bleServiceProvider)
          .requestDownload(activeId, widget.match.id);

      // WiFi — group lifecycle is owned by `wifiHandoffProvider`, but in
      // case the user opens this sheet before the orchestrator's first tick
      // has landed, defensively bring the group up here. Idempotent.
      final wifi = ref.read(wifiServiceProvider);
      if (wifi.currentGroup(activeId) == null) {
        await wifi.connectGroup(activeId);
      }
      final handle = await wifi.startDownload(activeId, token);

      setState(() => _handle = handle);
      handle.progress.listen(
        (p) {
          if (!mounted) return;
          setState(() => _progress = p);
        },
        onError: (Object e) {
          if (!mounted) return;
          setState(() => _error = e.toString());
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final running = _handle != null;
    if (running) return _buildProgress();
    final fullSize = '${widget.match.fullSizeMb} MB';
    final hiSize = '0 MB';
    final opts = <_Opt>[
      _Opt(
        key: 'full',
        label: 'Full game',
        sub: '${widget.match.fullDuration} · $fullSize · ~12 min @ WiFi',
      ),
      _Opt(
        key: 'h1',
        label: '1st half',
        sub: '35:00 · ${(widget.match.fullSizeMb / 2).round()} MB · ~6 min',
      ),
      _Opt(
        key: 'h2',
        label: '2nd half',
        sub: '38:12 · ${(widget.match.fullSizeMb / 2).round()} MB · ~7 min',
      ),
      _Opt(
        key: 'hi',
        label: 'All highlights',
        sub: '${widget.match.events.length} events · ±10s · $hiSize',
      ),
      _Opt(
        key: 'hisel',
        label: 'Selected highlights',
        sub: '${widget.selectedCount} events selected',
        badge: widget.selectedCount > 0 ? '${widget.selectedCount}' : null,
      ),
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
            (o) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: GestureDetector(
                onTap: () => setState(() => _selected = o.key),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _selected == o.key ? T.accentSoft : T.surface,
                    border: Border.all(
                      color: _selected == o.key ? T.accent : T.hair,
                      width: 1.4,
                    ),
                  ),
                  child: Row(
                    children: [
                      _Radio(on: _selected == o.key),
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
                      if (o.badge != null)
                        WfChip(label: o.badge!, active: true),
                    ],
                  ),
                ),
              ),
            ),
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
    this.badge,
  });
  final String key;
  final String label;
  final String sub;
  final String? badge;
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

extension on Border {
  BoxDecoration toBoxDecoration() => BoxDecoration(border: this);
}
