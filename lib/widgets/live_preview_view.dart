import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_vlc_player/flutter_vlc_player.dart';
import 'package:video_player/video_player.dart';

import '../env.dart';
import '../models/wifi.dart';
import '../state/wifi_providers.dart';
import '../theme/tokens.dart';
import 'wf_card.dart';

/// 16:9 live preview surface. Plays the camera's RTSP H.264 stream via VLC
/// when the WiFi Direct group is up and the descriptor URL is reachable;
/// falls back to the wireframe striped placeholder otherwise (no descriptor,
/// VLC error, or dev-mock with a fake RTSP URL).
///
/// Lifecycle of the WiFi Direct group is owned by `wifiHandoffProvider` —
/// this widget only reads state and the preview URL. Pass `autoStart: true`
/// when using the widget outside the orchestrated app shell (e.g. tests).
class LivePreviewView extends ConsumerStatefulWidget {
  const LivePreviewView({
    super.key,
    required this.deviceId,
    this.label,
    this.height,
    this.aspect,
    this.autoStart = false,
  });

  final String? deviceId;
  final String? label;
  final double? height;
  final double? aspect;
  final bool autoStart;

  @override
  ConsumerState<LivePreviewView> createState() => _LivePreviewViewState();
}

class _LivePreviewViewState extends ConsumerState<LivePreviewView> {
  String? _autoStartedFor;
  VlcPlayerController? _vlc;
  String? _vlcUrl;
  bool _vlcError = false;

  // Dev-mode mock video player (used when no real RTSP stream is available).
  VideoPlayerController? _mock;

  @override
  void initState() {
    super.initState();
    if (kAppEnv.isDevBackend) {
      _initMockPlayer();
    }
  }

  void _initMockPlayer() {
    final controller = VideoPlayerController.asset('assets/mock/mock-video.mp4');
    _mock = controller;
    controller
      ..setLooping(true)
      ..initialize().then((_) {
        if (mounted && _mock == controller) {
          _mock?.play();
          setState(() {});
        }
      }).catchError((_) {
        // Platform not available in test environments — fall back to placeholder.
        if (mounted && _mock == controller) {
          controller.dispose();
          _mock = null;
        }
      });
  }

  @override
  void dispose() {
    _vlc?.removeListener(_onVlcChange);
    _vlc?.dispose();
    // Null before dispose so any in-flight initialize().then() callback
    // fails the _mock == controller identity check and skips play().
    final mock = _mock;
    _mock = null;
    mock?.dispose();
    super.dispose();
  }

  void _onVlcChange() {
    final hasError = _vlc?.value.hasError ?? false;
    if (hasError != _vlcError && mounted) {
      setState(() => _vlcError = hasError);
    }
  }

  void _swapVlcController(String url) {
    _vlc?.removeListener(_onVlcChange);
    // ignore: discarded_futures
    _vlc?.dispose();
    final controller = VlcPlayerController.network(
      url,
      hwAcc: HwAcc.full,
      autoPlay: true,
      options: VlcPlayerOptions(),
    );
    controller.addListener(_onVlcChange);
    _vlc = controller;
    _vlcUrl = url;
    _vlcError = false;
  }

  @override
  Widget build(BuildContext context) {
    final deviceId = widget.deviceId;

    // Optional fallback for callers that aren't using the orchestrator (e.g.
    // tests that mount the widget without `wifiHandoffProvider`). Idempotent
    // because MockWifiService.connectGroup returns the existing group.
    if (widget.autoStart && deviceId != null && _autoStartedFor != deviceId) {
      _autoStartedFor = deviceId;
      // ignore: unawaited_futures, discarded_futures
      ref.read(wifiServiceProvider).connectGroup(deviceId).catchError((_) {
        return const WifiDirectGroup(
          ssid: '',
          psk: '',
          groupOwnerIp: '',
          previewPort: 0,
          downloadPort: 0,
          role: '',
        );
      });
    }

    if (deviceId == null) {
      return ThumbPlaceholder(
        label: widget.label ?? 'NO CAMERA',
        height: widget.height,
        aspect: widget.aspect,
      );
    }

    final wifiState = ref
        .watch(wifiConnectionStateProvider(deviceId))
        .valueOrNull;
    final frame = ref.watch(previewFrameProvider(deviceId)).valueOrNull;
    final stats = ref.watch(previewStatsProvider(deviceId)).valueOrNull;
    final descriptor = ref.watch(previewDescriptorProvider(deviceId));

    // Spin up / replace the VLC controller whenever the descriptor URL changes.
    final url = descriptor?.url;
    if (url != null && url != _vlcUrl) {
      _swapVlcController(url);
    } else if (url == null && _vlc != null) {
      _vlc?.removeListener(_onVlcChange);
      // ignore: discarded_futures
      _vlc?.dispose();
      _vlc = null;
      _vlcUrl = null;
      _vlcError = false;
    }

    final wifiConnected = wifiState == WifiDirectState.connected;
    final liveBadgeOn = wifiConnected && frame != null;
    final showVlc = wifiConnected && _vlc != null && !_vlcError;

    final statusLabel = switch (wifiState) {
      WifiDirectState.starting => 'WIFI · LINKING',
      WifiDirectState.failed => 'WIFI · FAILED',
      WifiDirectState.stopping => 'WIFI · STOPPING',
      WifiDirectState.idle || null => widget.label ?? 'WIFI · IDLE',
      WifiDirectState.connected =>
        frame == null ? 'WIFI · WAITING FOR FRAMES' : 'LIVE',
    };

    final body = Stack(
      fit: StackFit.expand,
      children: [
        if (showVlc)
          VlcPlayer(
            controller: _vlc!,
            aspectRatio: 16 / 9,
            placeholder: const ThumbPlaceholder(),
          )
        else if (kAppEnv.isDevBackend &&
            (_mock?.value.isInitialized ?? false))
          // In dev mode with no real RTSP stream, loop the mock video asset.
          FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: _mock!.value.size.width,
              height: _mock!.value.size.height,
              child: VideoPlayer(_mock!),
            ),
          )
        else
          ThumbPlaceholder(label: liveBadgeOn ? null : statusLabel),
        if (liveBadgeOn)
          Positioned(left: 8, top: 8, child: _LiveBadge(stats: stats)),
        if (liveBadgeOn)
          Positioned(
            right: 8,
            top: 8,
            child: _FrameCounter(sequence: frame.sequence),
          ),
      ],
    );

    if (widget.height != null) {
      return SizedBox(
        height: widget.height,
        width: double.infinity,
        child: body,
      );
    }
    return AspectRatio(aspectRatio: widget.aspect ?? 16 / 9, child: body);
  }
}

class _LiveBadge extends StatelessWidget {
  const _LiveBadge({required this.stats});
  final PreviewStats? stats;

  @override
  Widget build(BuildContext context) {
    final fps = stats?.fps ?? 0;
    final kbps = stats?.kbps ?? 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: T.bg.withValues(alpha: 0.85),
        border: Border.all(color: T.accent, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: T.accent,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            'LIVE · ${fps.toStringAsFixed(0)} FPS · ${kbps.toStringAsFixed(0)} KB/S',
            style: const TextStyle(
              fontFamily: T.mono,
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: T.accent,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _FrameCounter extends StatelessWidget {
  const _FrameCounter({required this.sequence});
  final int sequence;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: T.bg.withValues(alpha: 0.85),
        border: Border.all(color: T.hair),
      ),
      child: Text(
        '#${sequence.toString().padLeft(5, '0')}',
        style: const TextStyle(fontFamily: T.mono, fontSize: 9, color: T.ink2),
      ),
    );
  }
}
