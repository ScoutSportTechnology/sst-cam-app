// Slim "connect camera" banner — shown on the Settings page when no camera is
// connected, in place of the camera card, so the camera-independent sections
// still render below it. Split from settings_page.dart; behavior is unchanged.
//
// The CTA runs a small state machine:
//   1. On tap → loading (disabled, "Connecting…", inline spinner).
//   2. If `lastConnectedDeviceIdProvider` has a value, attempt the universal
//      connect handshake via `ConnectController.connect(lastId)`. The
//      controller owns the sole handshake timeout — no caller-side
//      `.timeout()` wrapper (Future.timeout doesn't cancel the underlying
//      op, so caller and service would disagree about the in-flight state).
//   3. Success: the controller wrote `activeCameraIdProvider`; the page
//      rerenders to the populated layout. If `getActiveUser` returns null we
//      leave `activeUserProvider` null and the User section renders the
//      "Pick a user" prompt.
//   4. Failure (typed exception from the controller; link already dropped):
//      push `DiscoveryPage` and surface a `SnackBar` with the "Couldn't
//      reconnect" copy.
//   5. No persisted last id: push `DiscoveryPage` directly without
//      attempting reconnect (no loading state, no snackbar).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/state/connect_controller.dart';
import '../../core/state/last_camera.dart';
import '../../core/state/reconnect_controller.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/wf_button.dart';
import '../../core/widgets/wf_card.dart';
import '../discovery/discovery_page.dart';

class ConnectCameraBanner extends ConsumerStatefulWidget {
  const ConnectCameraBanner({super.key});

  @override
  ConsumerState<ConnectCameraBanner> createState() =>
      _ConnectCameraBannerState();
}

class _ConnectCameraBannerState extends ConsumerState<ConnectCameraBanner> {
  bool _isConnecting = false;

  Future<void> _onConnectTapped() async {
    setState(() => _isConnecting = true);
    try {
      final lastIdAsync = ref.read(lastConnectedDeviceIdProvider);
      final lastId = lastIdAsync.valueOrNull;
      if (lastId == null) {
        // First-launch path: just push DiscoveryPage.
        if (!mounted) return;
        await Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const DiscoveryPage()));
        return;
      }

      // One-tap reconnect through the universal handshake. Success side
      // effects (active-camera id, selection adoption from the firmware
      // snapshot, last-connected persistence) live in the controller.
      try {
        await ref.read(connectControllerProvider).connect(lastId);
      } catch (_) {
        // BleConnectionException, BleHandshakeException, anything else —
        // same user-facing fallback per the plan (link already dropped).
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "Couldn't reconnect to last camera — searching for cameras.",
            ),
          ),
        );
        await Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const DiscoveryPage()));
      }
    } finally {
      if (mounted) setState(() => _isConnecting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Subtle U6 indicator: while the auto-reconnect loop is chasing the
    // dropped camera, the banner says so — the state stays honestly
    // "not connected" and the manual CTA below keeps working (a manual
    // connect dedups with the loop's in-flight attempt).
    final reconnecting =
        ref.watch(reconnectControllerProvider).phase ==
        ReconnectPhase.reconnecting;
    return WfCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: T.fillSoft,
                  shape: BoxShape.circle,
                  border: Border.all(color: T.hair),
                ),
                child: const Icon(
                  Icons.videocam_off_outlined,
                  color: T.ink2,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'No camera connected',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: T.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      reconnecting
                          ? 'Connection lost — reconnecting automatically…'
                          : 'Connect a camera to manage users, formats, and '
                                'streaming destinations.',
                      style: TextStyle(
                        fontSize: 11,
                        color: reconnecting ? T.warn : T.ink2,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_isConnecting)
            Row(
              children: const [
                Expanded(
                  child: WfButton(
                    label: 'Connecting…',
                    variant: WfButtonVariant.primary,
                    full: true,
                    onPressed: null,
                  ),
                ),
                SizedBox(width: 10),
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(T.accent),
                  ),
                ),
              ],
            )
          else
            WfButton(
              label: 'Connect camera',
              variant: WfButtonVariant.primary,
              full: true,
              onPressed: _onConnectTapped,
            ),
        ],
      ),
    );
  }
}
