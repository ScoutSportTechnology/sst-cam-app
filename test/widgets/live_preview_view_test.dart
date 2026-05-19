// Tests for LivePreviewView — U1: skip VLC controller in dev-backend mode.
//
// Platform channel note: flutter_vlc_player and video_player use native
// platform channels unavailable in the test environment. The video_player
// initialize() call fails silently via the catchError handler in
// _initMockPlayer, leaving _mock == null. As a result, ThumbPlaceholder
// is always shown (neither VLC nor the mock video can render). The key
// behaviour we verify is that VlcPlayer is never inserted into the widget
// tree when isDevBackend is true (the compile-time default for tests).
//
// autoStart is not used here to avoid pending timers from MockWifiService
// pairingDelay. Instead, previewDescriptorProvider is overridden directly
// to supply a non-null descriptor URL, which is the scenario that previously
// caused VLC to be initialised.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_vlc_player/flutter_vlc_player.dart';
import 'package:sst_cam_app/models/wifi.dart';
import 'package:sst_cam_app/state/wifi_providers.dart';
import 'package:sst_cam_app/widgets/live_preview_view.dart';
import 'package:sst_cam_app/widgets/wf_card.dart';
import 'package:sst_cam_app/wifi/mock_wifi_service.dart';

const _kDeviceId = 'SST-CAM-001';
const _kFakeDescriptor = PreviewStreamDescriptor(
  url: 'rtsp://192.168.49.1:8554/live',
  codec: PreviewCodec.rtspH264,
  width: 640,
  height: 360,
  fps: 15,
  bitrateKbps: 1500,
);

// Build a harness that wires a MockWifiService but also directly overrides
// previewDescriptorProvider so the widget sees a non-null URL without needing
// autoStart / connectGroup (which would leave pending timers).
Widget _buildHarness({
  String? deviceId = _kDeviceId,
  PreviewStreamDescriptor? descriptor = _kFakeDescriptor,
}) {
  final wifi = MockWifiService();
  return ProviderScope(
    overrides: [
      wifiServiceProvider.overrideWithValue(wifi),
      if (deviceId != null)
        previewDescriptorProvider(deviceId).overrideWith(
          (_) => descriptor,
        ),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: LivePreviewView(deviceId: deviceId),
      ),
    ),
  );
}

void main() {
  group('LivePreviewView — dev-backend mode (U1)', () {
    testWidgets(
      'ThumbPlaceholder shown before mock video initialises',
      (tester) async {
        await tester.pumpWidget(_buildHarness());
        await tester.pump(); // one async gap — _initMockPlayer is async

        // In the test env the video_player platform channel fails, so the
        // catchError handler leaves _mock == null. ThumbPlaceholder fills
        // the else branch.
        expect(find.byType(ThumbPlaceholder), findsOneWidget);
      },
    );

    testWidgets(
      'VlcPlayer never in widget tree in dev-backend mode '
      'even when descriptor URL is non-null',
      (tester) async {
        // _kFakeDescriptor supplies a non-null URL directly via provider
        // override — this is the scenario that previously triggered VLC.
        await tester.pumpWidget(_buildHarness());
        await tester.pump();

        // The isDevBackend guard must skip _swapVlcController entirely
        // so _vlc stays null and VlcPlayer never appears.
        expect(find.byType(VlcPlayer), findsNothing);
        expect(find.byType(ThumbPlaceholder), findsOneWidget);
      },
    );

    testWidgets(
      'deviceId null → ThumbPlaceholder with NO CAMERA label '
      'regardless of backend mode',
      (tester) async {
        await tester.pumpWidget(_buildHarness(deviceId: null));
        await tester.pump();

        expect(find.byType(ThumbPlaceholder), findsOneWidget);
        expect(find.text('NO CAMERA'), findsOneWidget);
        expect(find.byType(VlcPlayer), findsNothing);
      },
    );
  });
}
