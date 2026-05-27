import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_vlc_player/flutter_vlc_player.dart';

import '../models/wifi.dart';
import '../wifi/wifi_providers.dart';
import '../theme/tokens.dart';
import 'wf_button.dart';
import 'wf_card.dart';

/// 16:9 live preview surface. Plays the camera's RTSP H.264 stream via VLC
/// when the WiFi Direct group is up and the descriptor URL is reachable;
/// falls back to the wireframe striped placeholder otherwise (no descriptor or
/// VLC error). In dev the descriptor URL points at the mock-camera-wifi
/// container; in stage/prod it points at the real camera.
///
/// Preview on/off state is shared via [livePreviewEnabledProvider] (keyed by
/// deviceId) so multiple surfaces on different pages stay in sync.
///
/// Pass [showButtons] = false when the parent manages the Preview/Stop toggle
/// externally (e.g. the main camera card's action row). Default true shows
/// the toggle buttons inside the surface itself.
///
/// Pass [autoStart] = true when using the widget outside the orchestrated app
/// shell (e.g. tests that mount without wifiHandoffProvider). Idempotent.
class LivePreviewView extends ConsumerStatefulWidget {
  const LivePreviewView({
    super.key,
    required this.deviceId,
    this.label,
    this.height,
    this.aspect,
    this.autoStart = false,
    this.showButtons = true,
  });

  final String? deviceId;
  final String? label;
  final double? height;
  final double? aspect;
  final bool autoStart;
  /// Whether to render Preview / Stop toggle buttons inside this surface.
  /// Set false when the parent provides external controls.
  final bool showButtons;

  @override
  ConsumerState<LivePreviewView> createState() => _LivePreviewViewState();
}

class _LivePreviewViewState extends ConsumerState<LivePreviewView> {
  String? _autoStartedFor;
  VlcPlayerController? _vlc;
  String? _vlcUrl;
  bool _vlcError = false;

  void _enablePreview() {
    ref.read(livePreviewEnabledProvider(widget.deviceId).notifier).state = true;
  }

  void _disablePreview() {
    ref
        .read(livePreviewEnabledProvider(widget.deviceId).notifier)
        .state = false;
  }

  /// Disposes [controller], swallowing the LateError that
  /// VlcPlayerController.dispose() throws when its native view never attached
  /// (preview torn down before the platform view initialised, or headless
  /// test env). Nothing to release in that case.
  void _disposeVlc(VlcPlayerController? controller) {
    if (controller == null) return;
    controller.removeListener(_onVlcChange);
    // dispose() is async and completes with a LateError if its native view
    // never attached — handle it on the future, not via a sync try/catch.
    // ignore: discarded_futures
    controller.dispose().catchError((Object e) {
      debugPrint('LivePreviewView: VLC dispose skipped ($e)');
    });
  }

  void _tearDownVlc() {
    _disposeVlc(_vlc);
    _vlc = null;
    _vlcUrl = null;
    _vlcError = false;
  }

  @override
  void dispose() {
    _disposeVlc(_vlc);
    super.dispose();
  }

  void _onVlcChange() {
    final hasError = _vlc?.value.hasError ?? false;
    if (hasError != _vlcError && mounted) {
      setState(() => _vlcError = hasError);
    }
  }

  void _swapVlcController(String url) {
    _disposeVlc(_vlc);
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

    // Optional fallback for callers that aren't using the orchestrator.
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

    // Tear down the VLC controller when preview is turned off.
    ref.listen<bool>(livePreviewEnabledProvider(deviceId), (prev, next) {
      if (!next && (prev ?? false)) {
        _tearDownVlc();
      }
    });

    final previewEnabled = ref.watch(livePreviewEnabledProvider(deviceId));

    // Preview is off — show placeholder (and optional Preview button).
    if (!previewEnabled) {
      final offBody = widget.showButtons
          ? Stack(
              fit: StackFit.expand,
              children: [
                ThumbPlaceholder(label: widget.label ?? 'PREVIEW'),
                Center(
                  child: WfButton(
                    label: 'Preview',
                    variant: WfButtonVariant.outline,
                    size: WfButtonSize.sm,
                    leading: const Icon(
                      Icons.play_arrow_rounded,
                      size: 13,
                      color: T.ink,
                    ),
                    onPressed: _enablePreview,
                  ),
                ),
              ],
            )
          : ThumbPlaceholder(label: widget.label ?? 'PREVIEW');

      if (widget.height != null) {
        return SizedBox(
          height: widget.height,
          width: double.infinity,
          child: offBody,
        );
      }
      return AspectRatio(
        aspectRatio: widget.aspect ?? 16 / 9,
        child: offBody,
      );
    }

    // Preview is on — read WiFi/frame state.
    final wifiState = ref
        .watch(wifiConnectionStateProvider(deviceId))
        .valueOrNull;
    final frame = ref.watch(previewFrameProvider(deviceId)).valueOrNull;
    final stats = ref.watch(previewStatsProvider(deviceId)).valueOrNull;
    final descriptor = ref.watch(previewDescriptorProvider(deviceId));

    // Spin up / replace the VLC controller whenever the descriptor URL changes.
    if (previewEnabled) {
      final url = descriptor?.url;
      if (url != null && url != _vlcUrl) {
        _swapVlcController(url);
      } else if (url == null && _vlc != null) {
        _tearDownVlc();
      }
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
        if (widget.showButtons)
          Positioned(
            right: 8,
            bottom: 8,
            child: WfButton(
              label: 'Stop',
              variant: WfButtonVariant.outline,
              size: WfButtonSize.sm,
              onPressed: _disablePreview,
            ),
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
            'LIVE · ${(stats?.fps ?? 0).toStringAsFixed(0)} FPS · ${(stats?.kbps ?? 0).toStringAsFixed(0)} KB/S',
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
