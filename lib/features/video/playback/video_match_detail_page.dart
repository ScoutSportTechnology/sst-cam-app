import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import 'dart:io';

import '../../../core/models/team.dart' show opponentDisplayName;
import '../../../core/state/db_providers.dart' show videoPathServiceProvider;
import '../video_state.dart'
    show
        libraryMatchProvider,
        isOnDeviceProvider,
        liveSessionActiveProvider,
        LibraryMatch,
        LibraryEvent;
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/wf_button.dart';
import '../../../core/widgets/wf_card.dart';
import 'download_sheet.dart';

class VideoMatchDetailPage extends ConsumerStatefulWidget {
  const VideoMatchDetailPage({super.key, required this.matchId});
  final String matchId;

  @override
  ConsumerState<VideoMatchDetailPage> createState() =>
      _VideoMatchDetailPageState();
}

class _VideoMatchDetailPageState extends ConsumerState<VideoMatchDetailPage> {
  late Set<int> _selected;
  double _playheadFraction = 0.0;

  // Video player state
  VideoPlayerController? _playerController;
  bool _playerInitialized = false;
  bool _isPlaying = false;
  int _matchDurationSeconds = 0;

  // Throttle for _onPlayerStateChange to avoid 60 Hz setState calls.
  DateTime? _lastPlayheadUpdate;

  // Guards: duration computed once; player started once when on-device confirmed.
  bool _initStarted = false;
  bool _playerInitStarted = false;

  @override
  void initState() {
    super.initState();
    final m = _match();
    _selected = {
      for (int i = 0; i < (m?.events.length ?? 0); i++)
        if (i.isEven) i,
    };
  }

  /// Seeds the scrubber's duration once on first non-null match (refined to the
  /// real video duration once the player initializes). Player init is triggered
  /// reactively from [build] when [isOnDeviceProvider] resolves true.
  void _maybeStartInit(LibraryMatch match) {
    if (_initStarted) return;
    _initStarted = true;
    _matchDurationSeconds = _parseDuration(match.fullDuration);
  }

  /// Starts the video player. Called from [build] once [isOnDeviceProvider]
  /// resolves to true (includes after a download completes and the provider
  /// is invalidated + re-evaluated).
  Future<void> _startPlayer() async {
    if (!mounted) return;
    // The seeder and MockWifiService both write the actual mock video to the
    // device path, so VideoPlayerController.file() works in dev and prod alike.
    final path = await ref
        .read(videoPathServiceProvider)
        .recordingPath(widget.matchId);
    final controller = VideoPlayerController.file(File(path));
    _playerController = controller;
    await controller
        .initialize()
        .then((_) {
          if (mounted && _playerController == controller) {
            controller.setLooping(true);
            controller.addListener(_onPlayerStateChange);
            final videoSecs = controller.value.duration.inSeconds;
            setState(() {
              _playerInitialized = true;
              _isPlaying = false;
              if (videoSecs > 0) _matchDurationSeconds = videoSecs;
            });
          }
        })
        .catchError((Object e, StackTrace st) {
          // Platform channels are unavailable in test environments.
          debugPrint('VideoMatchDetailPage: player init failed: $e\n$st');
          if (mounted && _playerController == controller) {
            controller.dispose();
            _playerController = null;
          }
        });
  }

  void _onPlayerStateChange() {
    final ctrl = _playerController;
    if (ctrl == null || !mounted) return;
    // Throttle to ~250 ms so we don't call setState on every video frame.
    final now = DateTime.now();
    if (_lastPlayheadUpdate != null &&
        now.difference(_lastPlayheadUpdate!) <
            const Duration(milliseconds: 250)) {
      return;
    }
    _lastPlayheadUpdate = now;
    final playing = ctrl.value.isPlaying;
    final posSecs = ctrl.value.position.inSeconds;
    final fraction = _matchDurationSeconds > 0
        ? (posSecs / _matchDurationSeconds).clamp(0.0, 1.0)
        : 0.0;
    setState(() {
      _isPlaying = playing;
      _playheadFraction = fraction;
    });
  }

  void _togglePlayPause() {
    final ctrl = _playerController;
    if (ctrl == null) return;
    if (ctrl.value.isPlaying) {
      ctrl.pause();
    } else {
      ctrl.play();
    }
  }

  @override
  void dispose() {
    _playerController?.removeListener(_onPlayerStateChange);
    final ctrl = _playerController;
    _playerController = null;
    ctrl?.dispose();
    super.dispose();
  }

  LibraryMatch? _match() => ref.read(libraryMatchProvider(widget.matchId));

  @override
  Widget build(BuildContext context) {
    final match = ref.watch(libraryMatchProvider(widget.matchId));
    if (match == null) {
      return const Scaffold(body: Center(child: Text('Match not found')));
    }

    // Watch on-device status reactively. When a download completes and
    // isOnDeviceProvider is invalidated, this triggers a rebuild that starts
    // the player — fixing the stale _isOnDevice local-state bug.
    final isOnDevice =
        ref.watch(isOnDeviceProvider(widget.matchId)).valueOrNull ?? false;

    final selectedCount = _selected.length;
    // HARD INVARIANT — no past-video retrieval while a match is live.
    final retrievalLocked = ref.watch(liveSessionActiveProvider);

    // Trigger overlay-state build once (idempotent guard inside).
    _maybeStartInit(match);

    // Trigger player init the first time the file is confirmed on device.
    if (isOnDevice && !_playerInitStarted) {
      _playerInitStarted = true;
      // ignore: discarded_futures
      _startPlayer();
    }

    return Scaffold(
      backgroundColor: T.bg,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Same legacy 'vs '-prefix normalization as the library card title,
            // so this page never renders "X vs vs Y".
            Text('${match.teamName} vs ${opponentDisplayName(match.opponent)}'),
            Text(
              '${match.date}${match.result.isNotEmpty ? ' · ${match.result}' : ''}',
              style: const TextStyle(fontSize: 11, color: T.ink2),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          _Player(
            match: match,
            playheadFraction: _playheadFraction,
            playerController: _playerInitialized ? _playerController : null,
            notOnDevice: !isOnDevice,
            onDownload: () => _showDownloadSheet(context, match),
            retrievalLocked: retrievalLocked,
            isPlaying: _isPlaying,
            onPlayPauseTap: _togglePlayPause,
          ),
          _Scrubber(
            totalSeconds: _matchDurationSeconds,
            events: match.events,
            value: _playheadFraction,
            onChanged: (v) {
              setState(() {
                _playheadFraction = v;
                if (_matchDurationSeconds > 0) {
                  final secs = (v * _matchDurationSeconds).round();
                  _playerController?.seekTo(Duration(seconds: secs));
                }
              });
            },
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
                    if (_matchDurationSeconds == 0) return;
                    final fraction = e.timeSeconds / _matchDurationSeconds;
                    setState(() => _playheadFraction = fraction);
                    _playerController?.seekTo(Duration(seconds: e.timeSeconds));
                  },
                );
              },
            ),
          ),
          _Footer(
            selectedCount: selectedCount,
            retrievalLocked: retrievalLocked,
            onDownload: () => _showDownloadSheet(context, match),
          ),
        ],
      ),
    );
  }

  void _showDownloadSheet(BuildContext context, LibraryMatch match) {
    // Defense-in-depth: the buttons are disabled while live, but never open
    // the retrieval sheet if a session is active.
    if (ref.read(liveSessionActiveProvider)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Can't retrieve videos while a match is live. End the session first.",
          ),
        ),
      );
      return;
    }
    final selectedEvents = [
      for (int i = 0; i < match.events.length; i++)
        if (_selected.contains(i)) match.events[i],
    ];
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: T.bg,
      isScrollControlled: true,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (_) => DownloadSheet(
        match: match,
        selectedEvents: selectedEvents,
        allEvents: match.events,
      ),
    );
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
    required this.playheadFraction,
    required this.playerController,
    required this.notOnDevice,
    required this.onDownload,
    required this.retrievalLocked,
    required this.isPlaying,
    required this.onPlayPauseTap,
  });

  final LibraryMatch match;
  final double playheadFraction;
  final VideoPlayerController? playerController;

  /// True when the recording is not yet on this device.
  final bool notOnDevice;
  final VoidCallback onDownload;

  /// True while a match is live — disables the on-frame download CTA.
  final bool retrievalLocked;
  final bool isPlaying;
  final VoidCallback onPlayPauseTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: notOnDevice ? null : onPlayPauseTap,
      child: Stack(
        children: [
          _buildPlayerBody(),
          // Play button — shown only when a player exists and is paused.
          if (!notOnDevice && playerController != null && !isPlaying)
            Positioned.fill(
              child: Center(
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: T.bg.withValues(alpha: 0.85),
                    border: Border.all(color: T.hair),
                  ),
                  child: const Icon(
                    Icons.play_arrow_rounded,
                    color: T.ink,
                    size: 26,
                  ),
                ),
              ),
            ),
          // No app-drawn overlay here (#6 A6a playback half): the overlay is
          // baked into the video by the camera on demand. A clean download has
          // no scoreboard; an overlaid download already carries the camera's.
          // The app must NOT draw its own, or it would double / diverge.
        ],
      ),
    );
  }

  Widget _buildPlayerBody() {
    if (notOnDevice) {
      // Not on device: single download CTA over the dark frame.
      return AspectRatio(
        aspectRatio: 16 / 9,
        child: ColoredBox(
          color: T.bg,
          child: Center(
            child: WfButton(
              label: retrievalLocked
                  ? 'Unavailable during live session'
                  : 'Download to watch',
              variant: WfButtonVariant.primary,
              leading: const Icon(Icons.download, size: 15, color: T.accentInk),
              onPressed: retrievalLocked ? null : onDownload,
            ),
          ),
        ),
      );
    }

    if (playerController != null) {
      return AspectRatio(
        aspectRatio: 16 / 9,
        child: VideoPlayer(playerController!),
      );
    }
    // On device but player not yet initialized (or failed in test env).
    return const ThumbPlaceholder(label: 'PLAYER');
  }
}

class _Scrubber extends StatelessWidget {
  const _Scrubber({
    required this.totalSeconds,
    required this.events,
    required this.value,
    required this.onChanged,
  });
  final int totalSeconds;
  final List<LibraryEvent> events;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final maxSecs = totalSeconds;
    if (maxSecs == 0) return const SizedBox.shrink();
    final ticks = events.map((e) => e.timeSeconds / maxSecs).toList();
    final currentSec = (value * maxSecs).round();
    final m = (currentSec ~/ 60).toString().padLeft(2, '0');
    final s = (currentSec % 60).toString().padLeft(2, '0');
    final th = (maxSecs ~/ 3600).toString().padLeft(2, '0');
    final tm = ((maxSecs % 3600) ~/ 60).toString().padLeft(2, '0');
    final ts = (maxSecs % 60).toString().padLeft(2, '0');
    final totalLabel = '$th:$tm:$ts';

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
                  totalLabel,
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
    required this.retrievalLocked,
    required this.onDownload,
  });
  final int selectedCount;

  /// True while a match is live — disables the footer download button.
  final bool retrievalLocked;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: const Border(
        top: BorderSide(color: T.rule),
      ).toBoxDecoration(),
      child: WfButton(
        label: retrievalLocked
            ? 'Unavailable during live session'
            : (selectedCount > 0
                  ? 'Download · $selectedCount clips'
                  : 'Download · options'),
        variant: WfButtonVariant.primary,
        leading: const Text(
          '↓',
          style: TextStyle(color: T.accentInk, fontWeight: FontWeight.w700),
        ),
        onPressed: retrievalLocked ? null : onDownload,
      ),
    );
  }
}

extension on Border {
  BoxDecoration toBoxDecoration() => BoxDecoration(border: this);
}
