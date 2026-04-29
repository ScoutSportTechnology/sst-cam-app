import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/wifi.dart';
import '../state/wifi_providers.dart';
import '../theme/tokens.dart';
import 'wf_card.dart';

/// 16:9 live preview surface. Subscribes to the WiFi Direct preview stream
/// for [deviceId] and shows the latest frame. When the group is not yet
/// connected, shows the wireframe placeholder with a status label so users
/// understand why nothing is moving yet.
///
/// In dev-mock the underlying [MockWifiService] emits placeholder JPEG bytes
/// without meaningful image content, so this widget renders a stylized
/// stripe placeholder with the live frame counter and fps overlay rather
/// than `Image.memory`. The real impl will swap to `Image.memory(frame.jpegBytes)`
/// once the camera is producing real frames.
class LivePreviewView extends ConsumerStatefulWidget {
  const LivePreviewView({
    super.key,
    required this.deviceId,
    this.label,
    this.height,
    this.aspect,
    this.autoStart = true,
  });

  final String? deviceId;
  final String? label;
  final double? height;
  final double? aspect;

  /// When true, the widget triggers `connectGroup` on the WiFi service as
  /// soon as it mounts with a non-null [deviceId]. Set to false when the
  /// caller is managing the group's lifecycle elsewhere.
  final bool autoStart;

  @override
  ConsumerState<LivePreviewView> createState() => _LivePreviewViewState();
}

class _LivePreviewViewState extends ConsumerState<LivePreviewView> {
  String? _connectedFor;

  @override
  Widget build(BuildContext context) {
    final deviceId = widget.deviceId;

    // Trigger group connect lazily once we know the deviceId. Idempotent —
    // MockWifiService.connectGroup returns the existing group on re-call.
    if (widget.autoStart && deviceId != null && _connectedFor != deviceId) {
      _connectedFor = deviceId;
      // ignore: unawaited_futures, discarded_futures
      ref.read(wifiServiceProvider).connectGroup(deviceId).catchError((_) {
        // State stream surfaces the failure; UI reads it via the provider.
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

    final connected = wifiState == WifiDirectState.connected && frame != null;
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
        ThumbPlaceholder(label: connected ? null : statusLabel),
        if (connected)
          Positioned(left: 8, top: 8, child: _LiveBadge(stats: stats)),
        if (connected)
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
