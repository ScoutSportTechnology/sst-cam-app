// U9 — AF mode control on the camera calibration page.
//
// The Autofocus toggle sends CameraFocusControlCommand(mode) through the
// BleService port and renders the EFFECTIVE mode echoed by the firmware's
// CameraFocusResponse (observed state), never the request (intent) — per the
// settings-toggle intent-vs-observed learning. autofocus_available=false in
// the echo (fixed lens, no VCM motor) disables the focus controls.
//
// Platform note: the page embeds LivePreviewView; overriding the preview
// descriptor to null keeps the VLC controller out of the test tree.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sst_cam_app/core/ble/ble_providers.dart';
import 'package:sst_cam_app/core/models/command.dart' show CameraFocusMode;
import 'package:sst_cam_app/core/models/wifi.dart';
import 'package:sst_cam_app/core/widgets/wf_card.dart';
import 'package:sst_cam_app/core/wifi/wifi_providers.dart';
import 'package:sst_cam_app/features/camera/camera_state.dart'
    show activeCameraIdProvider;
import 'package:sst_cam_app/features/settings/calibration/camera_calibration_page.dart';
import 'package:sst_cam_app/mock/emulator/mock_ble_service.dart';
import 'package:sst_cam_app/mock/emulator/mock_wifi_service.dart';

const _kDeviceId = 'SST-CAM-001';

MockBleService _newMock() => MockBleService(
  scanDeviceAppearDelays: const [Duration.zero, Duration.zero],
  connectionDelay: Duration.zero,
  failureRate: 0.0,
  randomSeed: 1,
);

Widget _harness({required MockBleService ble, String? cameraId = _kDeviceId}) {
  return ProviderScope(
    overrides: [
      bleServiceProvider.overrideWithValue(ble),
      wifiServiceProvider.overrideWithValue(MockWifiService()),
      activeCameraIdProvider.overrideWith((_) => cameraId),
      if (cameraId != null) ...[
        // Null descriptor → placeholder instead of a VLC platform view.
        previewDescriptorProvider(cameraId).overrideWith((_) => null),
        wifiConnectionStateProvider(
          cameraId,
        ).overrideWith((_) => Stream.value(WifiDirectState.idle)),
      ],
    ],
    child: const MaterialApp(home: CameraCalibrationPage()),
  );
}

/// Controls scoped to the Autofocus card (the white-balance card above it has
/// its own Switch/Sliders).
Finder get _afCard =>
    find.ancestor(of: find.text('Autofocus'), matching: find.byType(WfCard));
Finder get _afSwitch =>
    find.descendant(of: _afCard, matching: find.byType(Switch));
Finder get _afSlider =>
    find.descendant(of: _afCard, matching: find.byType(Slider));

/// The focus card sits below the fold of the lazy ListView — scroll it into
/// existence before asserting on it.
Future<void> _revealAfCard(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.text('Autofocus'),
    150,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pump();
}

Future<void> _toggleAf(WidgetTester tester) async {
  await tester.tap(_afSwitch);
  await tester.pump(); // dispatch the command
  await tester.pump(const Duration(milliseconds: 50)); // mock echo (20 ms)
}

void main() {
  testWidgets(
    'toggle to auto sends the mode command and shows auto after the echo',
    (tester) async {
      final ble = _newMock();
      await tester.pumpWidget(_harness(ble: ble));
      await tester.pump();
      await _revealAfCard(tester);

      // Seeded at the firmware default: manual.
      expect(tester.widget<Switch>(_afSwitch).value, isFalse);

      await _toggleAf(tester);

      expect(ble.lastFocus, isNotNull);
      expect(ble.lastFocus!.mode, CameraFocusMode.auto);
      expect(ble.lastFocus!.position, isNull);
      expect(tester.widget<Switch>(_afSwitch).value, isTrue);
      expect(
        find.textContaining(
          'Continuous autofocus stays active during recording and streaming',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'firmware echoing a different effective mode wins over the request',
    (tester) async {
      final ble = _newMock()
        ..focusEffectiveModeOverride = CameraFocusMode.manual;
      await tester.pumpWidget(_harness(ble: ble));
      await tester.pump();
      await _revealAfCard(tester);

      await _toggleAf(tester); // request auto…

      // …command went out, but the UI shows the echoed EFFECTIVE mode.
      expect(ble.lastFocus!.mode, CameraFocusMode.auto);
      expect(tester.widget<Switch>(_afSwitch).value, isFalse);
      expect(find.textContaining('Manual focus'), findsOneWidget);
    },
  );

  testWidgets(
    'autofocus_available=false disables the toggle with the fixed-lens note',
    (tester) async {
      final ble = _newMock()..focusAutofocusAvailable = false;
      await tester.pumpWidget(_harness(ble: ble));
      await tester.pump();
      await _revealAfCard(tester);

      await _toggleAf(tester);

      // Echo: effective manual + AF unavailable → disabled + affordance.
      expect(tester.widget<Switch>(_afSwitch).value, isFalse);
      expect(tester.widget<Switch>(_afSwitch).onChanged, isNull);
      expect(find.textContaining('Fixed lens'), findsOneWidget);
      // The manual position slider is dead too — no motor to drive.
      expect(tester.widget<Slider>(_afSlider).onChanged, isNull);
    },
  );

  testWidgets(
    'disconnected: no focus controls, standard connect affordance, nothing sent',
    (tester) async {
      final ble = _newMock();
      await tester.pumpWidget(_harness(ble: ble, cameraId: null));
      await tester.pump();

      expect(find.textContaining('Connect to a camera'), findsOneWidget);
      expect(find.byType(Switch), findsNothing);
      expect(ble.lastFocus, isNull);
    },
  );
}
