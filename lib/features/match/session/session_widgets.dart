// Session display widgets — top bar, live preview thumb (+ unavailable
// placeholder), notice/ended banners and the event-log row. Split from
// session_screen.dart; behavior is unchanged.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/wifi.dart' show WifiDirectState;
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/indicators.dart';
import '../../../core/widgets/live_preview_view.dart';
import '../../../core/wifi/wifi_providers.dart'
    show wifiConnectionStateProvider;
import '../../camera/camera_state.dart'
    show
        activeCameraIdProvider,
        activeTabProvider,
        modalPreviewActiveProvider,
        AppTab;
import 'session_state.dart';

// ---------------------------------------------------------------------------
// TOP BAR
// ---------------------------------------------------------------------------

class SessionTopBar extends StatelessWidget {
  const SessionTopBar({
    super.key,
    required this.indicator,
    required this.indicatorColor,
    required this.clock,
    this.onBack,
  });
  final String indicator;
  final Color indicatorColor;
  final String clock;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: T.rule)),
      ),
      child: Row(
        children: [
          if (onBack != null)
            GestureDetector(
              onTap: onBack,
              child: const Padding(
                padding: EdgeInsets.only(right: 12),
                child: Icon(Icons.arrow_back, size: 20, color: T.ink),
              ),
            ),
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: indicator == 'READY' || indicator == 'FT'
                  ? Colors.transparent
                  : indicatorColor,
              border: Border.all(color: indicatorColor, width: 1.5),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            indicator,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: indicatorColor,
              letterSpacing: 0.6,
            ),
          ),
          const Spacer(),
          Text(
            clock,
            style: const TextStyle(
              fontFamily: T.mono,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: T.ink,
            ),
          ),
          const Spacer(),
          const BatteryIndicator(level: 0.78, size: 11),
          const SizedBox(width: 4),
          const Text('78%', style: TextStyle(fontSize: 10, color: T.ink2)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// LIVE THUMB
// ---------------------------------------------------------------------------

class SessionLiveThumb extends ConsumerWidget {
  const SessionLiveThumb({
    super.key,
    required this.matchState,
    required this.isLive,
  });
  final LiveMatchState matchState;
  final bool isLive;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeId = ref.watch(activeCameraIdProvider);
    // Only the visible tab holds a VLC client (home + match preview cards both
    // stay mounted in the shell's IndexedStack; two clients on the single-stream
    // RTSP server stall the second — the match preview was the loser).
    final onMatchTab = ref.watch(activeTabProvider) == AppTab.match;
    final modalPreview = ref.watch(modalPreviewActiveProvider);

    // When WiFi Direct fails (e.g. iOS does not support local preview),
    // show a static placeholder instead of the live preview surface.
    final wifiState = activeId == null
        ? null
        : ref.watch(wifiConnectionStateProvider(activeId)).valueOrNull;
    final wifiFailed = wifiState == WifiDirectState.failed;

    if (wifiFailed) {
      return _PreviewUnavailablePlaceholder(
        matchState: matchState,
        isLive: isLive,
      );
    }
    // The firmware composites the scoreboard onto the RTSP stream itself
    // (overlay is firmware-unilateral, #6), so the app must NOT draw its
    // own overlay here — doing both showed a doubled scoreboard. The app
    // only authors + pushes the layout (PushOverlayLayout); the preview
    // shows the firmware-baked stream as-is.
    // No buttons inside the surface — Preview/Stop is in the parent layout.
    return LivePreviewView(
      deviceId: activeId,
      label: isLive ? 'LIVE PREVIEW' : 'PREVIEW',
      showButtons: false,
      paused: !onMatchTab || modalPreview,
      isStreaming: matchState.streaming,
    );
  }
}

// ---------------------------------------------------------------------------
// PREVIEW UNAVAILABLE PLACEHOLDER
// ---------------------------------------------------------------------------

/// Shown in [SessionLiveThumb] when the WiFi Direct connection has failed
/// (e.g. iOS does not support WiFi Direct local preview). Displays a
/// static scoreboard so the session UI stays fully functional.
class _PreviewUnavailablePlaceholder extends StatelessWidget {
  const _PreviewUnavailablePlaceholder({
    required this.matchState,
    required this.isLive,
  });

  final LiveMatchState matchState;
  final bool isLive;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(color: T.panel),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.videocam_off, size: 28, color: T.ink3),
                const SizedBox(height: 8),
                const Text(
                  'Preview not available',
                  style: TextStyle(
                    fontSize: 11,
                    color: T.ink2,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 8,
            right: 8,
            bottom: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: T.bg.withValues(alpha: 0.85),
                border: Border.all(color: T.hair),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _ScoreBlock(
                      label: matchState.homeName,
                      score: matchState.scoreHome,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      '${matchState.phaseLabel} · ${matchState.clockText}',
                      style: const TextStyle(
                        fontFamily: T.mono,
                        fontSize: 10,
                        color: T.ink2,
                      ),
                    ),
                  ),
                  Expanded(
                    child: _ScoreBlock(
                      label: matchState.awayName,
                      score: matchState.scoreAway,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// SCORE BLOCK
// ---------------------------------------------------------------------------

class _ScoreBlock extends StatelessWidget {
  const _ScoreBlock({required this.label, required this.score});
  final String label;
  final int score;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 9,
            color: T.ink2,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '$score',
          style: const TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w700,
            fontFamily: T.mono,
            color: T.ink,
            height: 1,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// SESSION NOTICE BANNER — one-line "ended while away" / poll-truth notices
// ---------------------------------------------------------------------------

/// One-line notice from the reconcile/poll-truth paths ("Match ended while
/// away — saved at 47:12.", "Recording stopped on the camera."). Dismissible;
/// hidden while [sessionNoticeProvider] is null.
class SessionNoticeBanner extends ConsumerWidget {
  const SessionNoticeBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notice = ref.watch(sessionNoticeProvider);
    if (notice == null) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(10, 6, 10, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: T.fillSoft,
        border: Border.all(color: T.rule, width: 1),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              notice,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: T.ink2,
              ),
            ),
          ),
          GestureDetector(
            onTap: () => ref.read(sessionNoticeProvider.notifier).state = null,
            child: const Padding(
              padding: EdgeInsets.only(left: 8),
              child: Icon(Icons.close, size: 14, color: T.ink2),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// ENDED BANNER
// ---------------------------------------------------------------------------

class SessionEndedBanner extends StatelessWidget {
  const SessionEndedBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: T.accentSoft,
        border: Border.all(color: T.accent, width: 1),
      ),
      child: const Text(
        'Match ended · tap back to return to upcoming',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: T.accent,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// EVENT LOG ROW
// ---------------------------------------------------------------------------

class SessionEventLogRow extends StatelessWidget {
  const SessionEventLogRow({super.key, required this.e});
  final LiveEvent e;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            child: Text(
              e.clock,
              style: const TextStyle(
                fontFamily: T.mono,
                fontWeight: FontWeight.w400,
                color: T.ink2,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              e.label,
              style: const TextStyle(fontSize: 12, color: T.ink),
            ),
          ),
          const Text('edit', style: TextStyle(fontSize: 11, color: T.ink2)),
        ],
      ),
    );
  }
}
