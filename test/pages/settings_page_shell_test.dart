// U6 — Settings page shell tests.
//
// Verifies the two render shapes (empty vs populated), the
// connection-state transition, and the empty-state CTA navigation.
// Uses `useDevDataStoreReset()` so the process-global DevDataStore is
// fresh before every test.
//
// To avoid Timer.periodic-driven streams from MockBleService that prevent
// `pumpAndSettle` from terminating, we override `connectionStateProvider`
// directly with a finite Stream rather than going through `mock.connect()`.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scout_camera/ble/mock_ble_service.dart';
import 'package:scout_camera/models/device.dart';
import 'package:scout_camera/pages/discovery_page.dart';
import 'package:scout_camera/pages/settings_page.dart';
import 'package:scout_camera/state/app_data.dart';
import 'package:scout_camera/state/ble_providers.dart';

import '../test_helpers.dart';

const String _kFakeDeviceId = 'SST-CAM-001';

MockBleService _newMock() => MockBleService(
  scanDeviceAppearDelays: const [Duration.zero, Duration.zero],
  connectionDelay: Duration.zero,
  failureRate: 0.0,
  randomSeed: 1,
);

/// Build the harness, optionally overriding the connection state for the
/// active camera id directly. We use a finite, immediately-completing Stream
/// rather than `mock.connect()` to keep tests synchronous.
Widget _buildHarness({
  required MockBleService service,
  String? activeCameraId,
  CameraConnectionState? connectionState,
  StreamController<CameraConnectionState>? connectionController,
}) {
  return ProviderScope(
    overrides: [
      bleServiceProvider.overrideWithValue(service),
      if (activeCameraId != null)
        activeCameraIdProvider.overrideWith((_) => activeCameraId),
      if (connectionState != null)
        connectionStateProvider(activeCameraId!).overrideWith(
          (_) => Stream<CameraConnectionState>.value(connectionState),
        ),
      if (connectionController != null)
        connectionStateProvider(activeCameraId!).overrideWith(
          (_) => connectionController.stream,
        ),
    ],
    child: const MaterialApp(home: SettingsPage()),
  );
}

void main() {
  // Process-global DevDataStore reset between tests.
  useDevDataStoreReset();

  group('Settings shell — empty state (no camera connected)', () {
    testWidgets(
      'renders empty-state CTA only; no section headers in the tree (AE1)',
      (tester) async {
        final mock = _newMock();
        addTearDown(mock.dispose);

        await tester.pumpWidget(_buildHarness(service: mock));
        await tester.pumpAndSettle();

        // Empty-state copy is present.
        expect(find.text('No camera connected'), findsOneWidget);
        expect(
          find.text(
            'Connect a camera to manage users, formats, and streaming '
            'destinations.',
          ),
          findsOneWidget,
        );
        expect(find.text('Connect camera'), findsOneWidget);

        // None of the populated-layout section headers are present.
        expect(find.text('User'), findsNothing);
        expect(find.text('Match setup'), findsNothing);
        expect(find.text('Streaming setup'), findsNothing);
        expect(find.text('App'), findsNothing);

        // None of the populated-layout placeholder copy. The Camera
        // section is the real card now (U7); we still check the
        // remaining placeholders aren't bleeding into the empty state.
        expect(find.text('Connected camera'), findsNothing);
        expect(find.text('Disconnect'), findsNothing);
        expect(find.text('User section — populated in U8'), findsNothing);
        expect(
          find.text('Streaming Setup section — populated in U9'),
          findsNothing,
        );
      },
    );
  });

  group('Settings shell — populated layout (connected)', () {
    testWidgets(
      'renders all five sections in order Camera → User → Match setup → '
      'Streaming setup → App',
      (tester) async {
        final mock = _newMock();
        addTearDown(mock.dispose);

        await tester.pumpWidget(
          _buildHarness(
            service: mock,
            activeCameraId: _kFakeDeviceId,
            connectionState: CameraConnectionState.connected,
          ),
        );
        await tester.pumpAndSettle();

        // Empty-state CTA is NOT visible.
        expect(find.text('No camera connected'), findsNothing);
        expect(find.text('Connect camera'), findsNothing);

        // Camera card (U7) renders the connected-camera caption + the
        // 2x2 button grid; the User and Streaming sections are still
        // U8/U9 placeholders. The "Diagnostics" label has moved from
        // the App section onto the camera card per R5.
        expect(find.text('Connected camera'), findsOneWidget);
        expect(find.text('Reboot'), findsOneWidget);
        expect(find.text('Update fw'), findsOneWidget);
        expect(find.text('Disconnect'), findsOneWidget);
        expect(find.text('Diagnostics'), findsOneWidget);
        expect(find.text('User'), findsOneWidget);
        expect(find.text('User section — populated in U8'), findsOneWidget);
        expect(find.text('Match setup'), findsOneWidget);
        expect(find.text('Sport setups'), findsOneWidget);
        expect(find.text('Streaming setup'), findsOneWidget);
        expect(
          find.text('Streaming Setup section — populated in U9'),
          findsOneWidget,
        );
        expect(find.text('App'), findsOneWidget);
        expect(find.text('Theme'), findsOneWidget);
        // Permissions / About are below the fold now that the camera
        // card has grown to a 2x2 button grid; scroll the ListView to
        // surface them.
        await tester.scrollUntilVisible(find.text('Permissions'), 200);
        expect(find.text('Permissions'), findsOneWidget);
        await tester.scrollUntilVisible(find.text('About'), 200);
        expect(find.text('About'), findsOneWidget);

        // Removed cards from prior shell are gone.
        expect(find.text('Recording defaults'), findsNothing);
        expect(find.text('Connectivity'), findsNothing);
        expect(find.text('Connect a different camera'), findsNothing);

        // Order assertion: Camera card appears above User section
        // header, which appears above Match setup, etc.
        final cameraPos = tester.getTopLeft(find.text('Connected camera')).dy;
        final userHeaderPos = tester.getTopLeft(find.text('User')).dy;
        final matchHeaderPos = tester.getTopLeft(find.text('Match setup')).dy;
        final streamingHeaderPos = tester
            .getTopLeft(find.text('Streaming setup'))
            .dy;
        final appHeaderPos = tester.getTopLeft(find.text('App')).dy;
        expect(cameraPos < userHeaderPos, isTrue);
        expect(userHeaderPos < matchHeaderPos, isTrue);
        expect(matchHeaderPos < streamingHeaderPos, isTrue);
        expect(streamingHeaderPos < appHeaderPos, isTrue);
      },
    );
  });

  group('Settings shell — connection-state transition', () {
    testWidgets(
      'connected → disconnected re-renders to the empty state without '
      'crashing',
      (tester) async {
        final mock = _newMock();
        addTearDown(mock.dispose);

        // Use a controllable stream for the connection state so we can flip
        // it from connected → disconnected without going through the real
        // mock connect path (which starts Timer.periodic for telemetry).
        final controller =
            StreamController<CameraConnectionState>.broadcast();
        addTearDown(controller.close);

        await tester.pumpWidget(
          _buildHarness(
            service: mock,
            activeCameraId: _kFakeDeviceId,
            connectionController: controller,
          ),
        );

        // Emit connected; the page should render the populated layout
        // with the U7 camera card.
        controller.add(CameraConnectionState.connected);
        await tester.pumpAndSettle();
        expect(find.text('Connected camera'), findsOneWidget);
        expect(find.text('No camera connected'), findsNothing);

        // Emit disconnected; the page should rerender to the empty state.
        controller.add(CameraConnectionState.disconnected);
        await tester.pumpAndSettle();
        expect(find.text('No camera connected'), findsOneWidget);
        expect(find.text('Connect camera'), findsOneWidget);
        expect(find.text('Connected camera'), findsNothing);
      },
    );
  });

  group('Settings shell — empty-state CTA navigation', () {
    testWidgets(
      'tapping "Connect camera" pushes a route whose first page is '
      'DiscoveryPage',
      (tester) async {
        final mock = _newMock();
        addTearDown(mock.dispose);

        await tester.pumpWidget(_buildHarness(service: mock));
        await tester.pumpAndSettle();

        expect(find.byType(DiscoveryPage), findsNothing);

        // Tap and pump a single frame to enqueue the navigation. We use
        // `pump()` rather than `pumpAndSettle()` because DiscoveryPage's
        // initState kicks off a scan that schedules a Timer that would
        // prevent settle. One pump is enough to push the route and have
        // DiscoveryPage build at least once.
        await tester.tap(find.text('Connect camera'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(find.byType(DiscoveryPage), findsOneWidget);

        // Stop the scan so it doesn't dangle into the next test.
        await mock.stopScan();
      },
    );
  });
}
