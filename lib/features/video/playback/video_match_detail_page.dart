import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import 'dart:io';

import '../../../core/models/overlay.dart' as app_overlay;
import '../../../core/state/db_providers.dart' show videoPathServiceProvider;
import '../video_state.dart'
    show libraryMatchProvider, isOnDeviceProvider, LibraryMatch, LibraryEvent;
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/indicators.dart';
import '../../../core/widgets/wf_button.dart';
import '../../../core/widgets/wf_card.dart';
import '../../../core/widgets/wf_chip.dart';
import 'download_sheet.dart';

class VideoMatchDetailPage extends ConsumerStatefulWidget {
  const VideoMatchDetailPage({super.key, required this.matchId});
  final String matchId;

  @override
  ConsumerState<VideoMatchDetailPage> createState() =>
      _VideoMatchDetailPageState();
}

class _VideoMatchDetailPageState extends ConsumerState<VideoMatchDetailPage> {
  bool _scoreOverlayOn = true;
  bool _eventsOverlayOn = true;
  bool _lastScoreOn = true; // restored when master toggle goes ON
  bool _lastEventsOn = true; // restored when master toggle goes ON
  late Set<int> _selected;
  double _playheadFraction = 0.0;

  // Video player state
  VideoPlayerController? _playerController;
  bool _playerInitialized = false;
  bool _isPlaying = false;
  int _matchDurationSeconds = 0;
  List<app_overlay.OverlayState> _overlayStates = [];
  app_overlay.OverlayState _currentOverlay = const app_overlay.OverlayState(
    timeSeconds: 0,
    homeScore: 0,
    awayScore: 0,
    period: 1,
    recentEventLabel: null,
  );

  // Guards: overlays built once; player started once when on-device is confirmed.
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

  /// Builds overlay states once on first non-null match. Player init is
  /// triggered reactively from [build] when [isOnDeviceProvider] resolves true.
  void _maybeStartInit(LibraryMatch match) {
    if (_initStarted) return;
    _initStarted = true;
    _buildOverlayStates(match);
  }

  void _buildOverlayStates(LibraryMatch match) {
    _matchDurationSeconds = _parseDuration(match.fullDuration);
    _overlayStates = app_overlay.OverlayState.fromEvents(
      match.events,
      periodLengthSeconds: match.periodLengthSeconds,
      homeShortName: match.teamShortName,
    );
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
            controller.play();
            setState(() {
              _playerInitialized = true;
              _isPlaying = true;
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
            Text('${match.teamName} vs ${match.opponent}'),
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
            scoreOverlayOn: _scoreOverlayOn,
            eventsOverlayOn: _eventsOverlayOn,
            playheadFraction: _playheadFraction,
            playerController: _playerInitialized ? _playerController : null,
            notOnDevice: !isOnDevice,
            currentOverlay: _currentOverlay,
            onDownload: () => _showDownloadSheet(context, match),
            isPlaying: _isPlaying,
            onPlayPauseTap: _togglePlayPause,
          ),
          _Scrubber(
            match: match,
            value: _playheadFraction,
            onChanged: (v) {
              setState(() {
                _playheadFraction = v;
                final maxSecs = _parseDuration(match.fullDuration);
                if (maxSecs > 0) {
                  final secs = (v * maxSecs).round();
                  _currentOverlay =
                      app_overlay.OverlayState.atTime(_overlayStates, secs);
                  // Seek the video to match the scrubber position.
                  _playerController?.seekTo(Duration(seconds: secs));
                }
              });
            },
          ),
          _OverlayToggleRow(
            scoreOn: _scoreOverlayOn,
            eventsOn: _eventsOverlayOn,
            lastScoreOn: _lastScoreOn,
            lastEventsOn: _lastEventsOn,
            onScoreChanged: (v) => setState(() {
              _scoreOverlayOn = v;
              _lastScoreOn = v;
            }),
            onEventsChanged: (v) => setState(() {
              _eventsOverlayOn = v;
              _lastEventsOn = v;
            }),
            onMasterChanged: (value) {
              setState(() {
                if (value) {
                  _scoreOverlayOn = _lastScoreOn;
                  _eventsOverlayOn = _lastEventsOn;
                } else {
                  _scoreOverlayOn = false;
                  _eventsOverlayOn = false;
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
                  index: i,
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
                    final fraction = e.timeSeconds / maxSecs;
                    setState(() {
                      _playheadFraction = fraction;
                      _currentOverlay =
                          app_overlay.OverlayState.atTime(_overlayStates, e.timeSeconds);
                    });
                  },
                );
              },
            ),
          ),
          _Footer(
            selectedCount: selectedCount,
            onDownload: () => _showDownloadSheet(context, match),
          ),
        ],
      ),
    );
  }

  void _showDownloadSheet(BuildContext context, LibraryMatch match) {
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
    required this.scoreOverlayOn,
    required this.eventsOverlayOn,
    required this.playheadFraction,
    required this.playerController,
    required this.notOnDevice,
    required this.currentOverlay,
    required this.onDownload,
    required this.isPlaying,
    required this.onPlayPauseTap,
  });

  final LibraryMatch match;
  final bool scoreOverlayOn;
  final bool eventsOverlayOn;
  final double playheadFraction;
  final VideoPlayerController? playerController;
  /// True when the recording is not yet on this device.
  final bool notOnDevice;
  final app_overlay.OverlayState currentOverlay;
  final VoidCallback onDownload;
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
        if (scoreOverlayOn)
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
                children: [
                  Text(
                    match.teamShortName,
                    style: const TextStyle(
                      fontSize: 9,
                      color: T.ink2,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${currentOverlay.homeScore}',
                    style: const TextStyle(
                      fontFamily: T.mono,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: T.ink,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${currentOverlay.period}H',
                    style: const TextStyle(
                      fontFamily: T.mono,
                      fontSize: 9,
                      color: T.ink3,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    () {
                      final t = currentOverlay.timeSeconds;
                      final mm = (t ~/ 60).toString().padLeft(2, '0');
                      final ss = (t % 60).toString().padLeft(2, '0');
                      return '$mm:$ss';
                    }(),
                    style: const TextStyle(
                      fontFamily: T.mono,
                      fontSize: 9,
                      color: T.ink3,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${currentOverlay.awayScore}',
                    style: const TextStyle(
                      fontFamily: T.mono,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: T.ink,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    match.opponent.split(' ').first,
                    style: const TextStyle(
                      fontSize: 9,
                      color: T.ink2,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (eventsOverlayOn &&
            currentOverlay.recentEventLabel != null &&
            currentOverlay.recentEventLabel!.isNotEmpty)
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              color: T.accent,
              child: Text(
                currentOverlay.recentEventLabel!,
                style: const TextStyle(
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
      ),
    );
  }

  Widget _buildPlayerBody() {
    if (notOnDevice) {
      // Not on device: single download CTA over the dark frame.
      return AspectRatio(
        aspectRatio: 16 / 9,
        child: ColoredBox(
          color: Colors.black,
          child: Center(
            child: WfButton(
              label: 'Download to watch',
              variant: WfButtonVariant.primary,
              leading: const Icon(Icons.download, size: 15, color: T.accentInk),
              onPressed: onDownload,
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
  const _OverlayToggleRow({
    required this.scoreOn,
    required this.eventsOn,
    required this.lastScoreOn,
    required this.lastEventsOn,
    required this.onScoreChanged,
    required this.onEventsChanged,
    required this.onMasterChanged,
  });

  final bool scoreOn;
  final bool eventsOn;
  final bool lastScoreOn;
  final bool lastEventsOn;
  final ValueChanged<bool> onScoreChanged;
  final ValueChanged<bool> onEventsChanged;
  final ValueChanged<bool> onMasterChanged;

  @override
  Widget build(BuildContext context) {
    final masterOn = scoreOn || eventsOn;
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
          GestureDetector(
            onTap: () => onScoreChanged(!scoreOn),
            child: WfChip(label: 'Score', active: scoreOn),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: () => onEventsChanged(!eventsOn),
            child: WfChip(label: 'Events', active: eventsOn),
          ),
          const SizedBox(width: 8),
          WfSwitch(value: masterOn, onChanged: onMasterChanged),
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
    required this.index,
    required this.selected,
    required this.onTap,
    required this.onJump,
  });
  final LibraryEvent event;
  final int index;
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
  });
  final int selectedCount;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: const Border(
        top: BorderSide(color: T.rule),
      ).toBoxDecoration(),
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
    );
  }
}

extension on Border {
  BoxDecoration toBoxDecoration() => BoxDecoration(border: this);
}
