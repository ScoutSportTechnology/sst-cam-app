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
}
