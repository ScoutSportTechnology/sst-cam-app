// Tests for LivePreviewView — the live RTSP preview surface.
//
// LivePreviewView drives a VLC controller off the WiFi preview descriptor URL
// in ALL environments. In dev that URL points at the mock-camera-wifi
// container (rtsp://localhost:8554/preview, reachable via `adb reverse`); in
// stage/prod it points at the real camera. There is no longer a dev-only
// bundled-video branch.
//
// Platform channel note: flutter_vlc_player uses a native platform view that
// renders as an empty box in the test environment (no native init). The VLC
// controller is still constructed and the VlcPlayer widget is inserted into
// the tree, so we assert on its presence/absence rather than rendered frames.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_vlc_player/flutter_vlc_player.dart';
import 'package:sst_cam_app/core/models/wifi.dart';
import 'package:sst_cam_app/core/state/device_health.dart';
import 'package:sst_cam_app/core/wifi/wifi_providers.dart';
import 'package:sst_cam_app/core/widgets/live_preview_view.dart';
import 'package:sst_cam_app/core/widgets/wf_card.dart';
import 'package:sst_cam_app/mock/emulator/mock_wifi_service.dart';

const _kDeviceId = 'SST-CAM-001';
const _kFakeDescriptor = PreviewStreamDescriptor(
  url: 'rtsp://localhost:8554/preview',
  codec: PreviewCodec.rtspH264,
  width: 640,
  height: 360,
  fps: 15,
  bitrateKbps: 1500,
);

/// Test-controlled stand-in for the U3 health gate: [captureBlockedProvider]
/// is overridden to read this switch, so tests flip health DOWN/OK edges by
/// writing it through the container.
final _captureBlockedSwitch = StateProvider<bool>((_) => false);

Widget _buildHarness({
  String? deviceId = _kDeviceId,
  PreviewStreamDescriptor? descriptor = _kFakeDescriptor,
  bool previewEnabled = true,
  WifiDirectState connectionState = WifiDirectState.connected,
}) {
  final wifi = MockWifiService();
  return ProviderScope(
    overrides: [
      wifiServiceProvider.overrideWithValue(wifi),
      captureBlockedProvider.overrideWith(
        (ref) => ref.watch(_captureBlockedSwitch),
      ),
      if (deviceId != null) ...[
        previewDescriptorProvider(deviceId).overrideWith((_) => descriptor),
        wifiConnectionStateProvider(
          deviceId,
        ).overrideWith((_) => Stream.value(connectionState)),
        livePreviewEnabledProvider(
          deviceId,
        ).overrideWith((_) => previewEnabled),
      ],
    ],
    child: MaterialApp(
      home: Scaffold(body: LivePreviewView(deviceId: deviceId)),
    ),
  );
}

VlcPlayerController _controllerOf(WidgetTester tester) =>
    tester.widget<VlcPlayer>(find.byType(VlcPlayer)).controller;

ProviderContainer _containerOf(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(LivePreviewView)));

void main() {
  group('LivePreviewView — RTSP preview', () {
    testWidgets(
      'drives VlcPlayer from the descriptor URL when preview is on + connected',
      (tester) async {
        await tester.pumpWidget(_buildHarness());
        await tester.pump(); // resolve the connection-state stream

        expect(find.byType(VlcPlayer), findsOneWidget);
      },
    );

    testWidgets(
      'shows placeholder and no VlcPlayer when the descriptor is null',
      (tester) async {
        await tester.pumpWidget(_buildHarness(descriptor: null));
        await tester.pump();

        expect(find.byType(VlcPlayer), findsNothing);
        expect(find.byType(ThumbPlaceholder), findsOneWidget);
      },
    );

    testWidgets(
      'preview off shows the placeholder with a Preview button, no VlcPlayer',
      (tester) async {
        await tester.pumpWidget(_buildHarness(previewEnabled: false));
        await tester.pump();

        expect(find.byType(VlcPlayer), findsNothing);
        expect(find.byType(ThumbPlaceholder), findsOneWidget);
        expect(find.text('Preview'), findsOneWidget);
      },
    );

    testWidgets(
      'preview on + WiFi down (re-form) → RECONNECTING… placeholder, no VlcPlayer',
      (tester) async {
        await tester.pumpWidget(
          _buildHarness(connectionState: WifiDirectState.failed),
        );
        await tester.pump();

        // Lean model: a dropped-but-stable group reads as reconnecting (the OS
        // rejoins), not as a failure — and VLC stays torn down until it's back.
        expect(find.byType(VlcPlayer), findsNothing);
        expect(find.text('RECONNECTING…'), findsOneWidget);
        expect(find.text('WIFI · FAILED'), findsNothing);
      },
    );

    testWidgets(
      'deviceId null → ThumbPlaceholder with NO CAMERA label, no VlcPlayer',
      (tester) async {
        await tester.pumpWidget(_buildHarness(deviceId: null));
        await tester.pump();

        expect(find.byType(ThumbPlaceholder), findsOneWidget);
        expect(find.text('NO CAMERA'), findsOneWidget);
        expect(find.byType(VlcPlayer), findsNothing);
      },
    );
  });

  group('LivePreviewView — auto-resume after camera recovery', () {
    testWidgets(
      'health inoperable → OK restarts the player with a fresh controller',
      (tester) async {
        await tester.pumpWidget(_buildHarness());
        await tester.pump();
        expect(find.byType(VlcPlayer), findsOneWidget);
        final before = _controllerOf(tester);
        final container = _containerOf(tester);

        // Camera dies mid-preview → health gate blocks capture: the VLC
        // client is released and the explicit unavailable state is shown.
        container.read(_captureBlockedSwitch.notifier).state = true;
        await tester.pump();
        expect(find.byType(VlcPlayer), findsNothing);
        expect(find.text('CAMERA UNAVAILABLE'), findsOneWidget);

        // Camera restored → gate lifts: playback restarts automatically with
        // a brand-new controller — no manual Stop → Preview cycle.
        container.read(_captureBlockedSwitch.notifier).state = false;
        await tester.pump();
        expect(find.byType(VlcPlayer), findsOneWidget);
        expect(_controllerOf(tester), isNot(same(before)));
      },
    );

    testWidgets(
      'player error while streaming → automatic stop/play cycle after the '
      'restart delay',
      (tester) async {
        await tester.pumpWidget(_buildHarness());
        await tester.pump();
        final before = _controllerOf(tester);

        // The RTSP connect errors (e.g. it raced the camera's pipeline
        // restart right after recovery) → surface drops to the placeholder…
        before.value = VlcPlayerValue.erroneous('stream died');
        await tester.pump();
        expect(find.byType(VlcPlayer), findsNothing);

        // …and after the restart delay a fresh controller retries on its own.
        await tester.pump(LivePreviewView.vlcRestartDelay);
        await tester.pump();
        expect(find.byType(VlcPlayer), findsOneWidget);
        expect(_controllerOf(tester), isNot(same(before)));
      },
    );

    testWidgets(
      'playing stream that stops (camera died, no health flip) → automatic '
      'stop/play cycle',
      (tester) async {
        await tester.pumpWidget(_buildHarness());
        await tester.pump();
        final before = _controllerOf(tester);

        // Frames flow… then the stream ends without an error.
        before.value = before.value.copyWith(
          isPlaying: true,
          playingState: PlayingState.playing,
        );
        await tester.pump();
        before.value = before.value.copyWith(
          isPlaying: false,
          playingState: PlayingState.stopped,
        );
        await tester.pump();

        await tester.pump(LivePreviewView.vlcRestartDelay);
        await tester.pump();
        expect(find.byType(VlcPlayer), findsOneWidget);
        expect(_controllerOf(tester), isNot(same(before)));
      },
    );

    testWidgets(
      'silent stall — frozen frame while "playing" (no error, no stop edge) '
      '→ automatic cycle after the stall window',
      (tester) async {
        await tester.pumpWidget(_buildHarness());
        await tester.pump();
        final before = _controllerOf(tester);

        // Frames flow: position advances across watchdog ticks (this arms the
        // frozen-frame detection by proving the position signal is live).
        before.value = before.value.copyWith(
          isPlaying: true,
          playingState: PlayingState.playing,
          position: const Duration(seconds: 1),
        );
        await tester.pump(LivePreviewView.stallCheckInterval);
        before.value = before.value.copyWith(
          position: const Duration(seconds: 3),
        );
        await tester.pump(LivePreviewView.stallCheckInterval);

        // Camera pipeline restarts underneath: VLC keeps claiming "playing"
        // but the position pins — the exact metal failure that needed a
        // manual Stop → Preview.
        await tester.pump(
          LivePreviewView.stallWindow + LivePreviewView.stallCheckInterval * 2,
        );
        await tester.pump(LivePreviewView.vlcRestartDelay);
        await tester.pump();
        expect(find.byType(VlcPlayer), findsOneWidget);
        expect(_controllerOf(tester), isNot(same(before)));
      },
    );

    testWidgets(
      'silent stall — pinned in buffering forever (never reaches playing) '
      '→ automatic cycle after the stall window',
      (tester) async {
        await tester.pumpWidget(_buildHarness());
        await tester.pump();
        final before = _controllerOf(tester);

        before.value = before.value.copyWith(
          isPlaying: false,
          playingState: PlayingState.buffering,
        );
        await tester.pump(
          LivePreviewView.stallWindow + LivePreviewView.stallCheckInterval * 2,
        );
        await tester.pump(LivePreviewView.vlcRestartDelay);
        await tester.pump();
        expect(find.byType(VlcPlayer), findsOneWidget);
        expect(_controllerOf(tester), isNot(same(before)));
      },
    );

    testWidgets('a healthy advancing stream is never cycled by the watchdog', (
      tester,
    ) async {
      await tester.pumpWidget(_buildHarness());
      await tester.pump();
      final before = _controllerOf(tester);

      before.value = before.value.copyWith(
        isPlaying: true,
        playingState: PlayingState.playing,
        position: const Duration(seconds: 1),
      );
      // Position keeps moving every tick — well past the stall window.
      for (var i = 2; i < 10; i++) {
        await tester.pump(LivePreviewView.stallCheckInterval);
        before.value = before.value.copyWith(position: Duration(seconds: i));
      }
      await tester.pump(LivePreviewView.vlcRestartDelay);
      await tester.pump();
      expect(_controllerOf(tester), same(before));
    });
  });
}
