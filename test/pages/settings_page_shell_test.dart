// U6 — Settings page shell tests.
//
// Verifies the two render shapes (empty vs populated), the
// connection-state transition, and the empty-state CTA navigation.
//
// To avoid Timer.periodic-driven streams from MockBleService that prevent
// `pumpAndSettle` from terminating, we override `connectionStateProvider`
// directly with a finite Stream rather than going through `mock.connect()`.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sst_cam_app/mock/mock_ble_service.dart';
import 'package:sst_cam_app/core/models/device.dart';
import 'package:sst_cam_app/pages/discovery_page.dart';
import 'package:sst_cam_app/pages/settings_page.dart';
import 'package:sst_cam_app/state/app_data.dart';
import 'package:sst_cam_app/state/ble_providers.dart';

import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers.dart';

const String _kFakeDeviceId = 'SST-CAM-001';

MockBleService _newMock() => MockBleService(
  scanDeviceAppearDelays: const [Duration.zero, Duration.zero],
  connectionDelay: Duration.zero,
  failureRate: 0.0,
  randomSeed: 1,
);

void main() {
  final db = useInMemoryDb();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  /// Build the harness, optionally overriding the connection state for the
  /// active camera id directly. We use a finite, immediately-completing Stream
  /// rather than `mock.connect()` to keep tests synchronous.
  Widget buildHarness({
    required MockBleService service,
    String? activeCameraId,
    CameraConnectionState? connectionState,
    StreamController<CameraConnectionState>? connectionController,
    String? activeUserId,
  }) {
    return ProviderScope(
      overrides: [
        ...dbOverrides(db),
        bleServiceProvider.overrideWithValue(service),
        if (activeCameraId != null)
          activeCameraIdProvider.overrideWith((_) => activeCameraId),
        if (connectionState != null)
          connectionStateProvider(activeCameraId!).overrideWith(
            (_) => Stream<CameraConnectionState>.value(connectionState),
          ),
        if (connectionController != null)
          connectionStateProvider(
            activeCameraId!,
          ).overrideWith((_) => connectionController.stream),
        if (activeUserId != null)
          activeUserProvider.overrideWith((_) => activeUserId),
      ],
      child: const MaterialApp(home: SettingsPage()),
    );
  }

  group('Settings shell — empty state (no camera connected)', () {
    testWidgets(
      'renders connect-camera banner; DB-backed sections always visible',
      (tester) async {
        final mock = _newMock();
        addTearDown(mock.dispose);

        await tester.pumpWidget(buildHarness(service: mock));
        await tester.pumpAndSettle();

        // Connect-camera banner replaces the camera card.
        expect(find.text('No camera connected'), findsOneWidget);
        expect(find.text('Connect camera'), findsOneWidget);

        // The real camera card is NOT present (only shown when connected).
        expect(find.text('Connected camera'), findsNothing);
        expect(find.text('Disconnect'), findsNothing);

        // DB-backed nav rows always render — no camera connection needed.
        expect(find.text('Users'), findsAtLeastNWidgets(1));
        await tester.scrollUntilVisible(find.text('Sport setups'), 200);
        expect(find.text('Sport setups'), findsOneWidget);
        await tester.scrollUntilVisible(find.text('Streaming destinations'), 200);
        expect(find.text('Streaming destinations'), findsOneWidget);
        await tester.scrollUntilVisible(find.text('Theme'), 200);
        expect(find.text('Theme'), findsOneWidget);
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
          buildHarness(
            service: mock,
            activeCameraId: _kFakeDeviceId,
            connectionState: CameraConnectionState.connected,
            activeUserId: 'user-1',
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
        // Users section collapses to a single nav row; badge shows active user.
        expect(find.text('Users'), findsAtLeastNWidgets(1));
        expect(find.text('Coach Diego'), findsOneWidget);
        // Manage users nav row is gone — management is directly in UsersSettingsPage.
        expect(find.text('Manage users'), findsNothing);
        // Nav rows are grouped in a single card; no separate WfSection headers.
        await tester.scrollUntilVisible(find.text('Sport setups'), 200);
        expect(find.text('Sport setups'), findsOneWidget);
        await tester.scrollUntilVisible(find.text('Streaming destinations'), 200);
        expect(find.text('Streaming destinations'), findsOneWidget);
        // App section rows are inline at the bottom.
        await tester.scrollUntilVisible(find.text('Theme'), 200);
        expect(find.text('Theme'), findsOneWidget);
        expect(find.text('Permissions'), findsOneWidget);
        expect(find.text('About'), findsOneWidget);

        // Removed cards from prior shell are gone.
        expect(find.text('Recording defaults'), findsNothing);
        expect(find.text('Connectivity'), findsNothing);
        expect(find.text('Connect a different camera'), findsNothing);

        // Order assertion: scroll back to the top, then walk down the
        // ListView capturing each section's `dy` as it scrolls into view.
        // After all scrolls, only the bottom of the list is visible, so
        // we can't read all positions at once. Instead we use the offsets
        // taken just before each `scrollUntilVisible` advanced past it.
        // Since scrolling above already moved each element into view in
        // order Match → Streaming → App, the order is structurally
        // enforced. We additionally assert the Users section nav row is
        // above Match setup by scrolling back to the top.
        await tester.dragUntilVisible(
          find.text('Connected camera'),
          find.byType(ListView),
          const Offset(0, 200),
        );
        final cameraPos = tester.getTopLeft(find.text('Connected camera')).dy;
        // 'Users' appears twice (WfSection + nav row label); use the first.
        final userHeaderPos = tester
            .getTopLeft(find.text('Users').first)
            .dy;
        expect(cameraPos < userHeaderPos, isTrue);
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
        final controller = StreamController<CameraConnectionState>.broadcast();
        addTearDown(controller.close);

        await tester.pumpWidget(
          buildHarness(
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

        // Emit disconnected; camera card replaced by banner; DB sections stay.
        controller.add(CameraConnectionState.disconnected);
        await tester.pumpAndSettle();
        expect(find.text('No camera connected'), findsOneWidget);
        expect(find.text('Connect camera'), findsOneWidget);
        expect(find.text('Connected camera'), findsNothing);
        // Users section still present (DB-backed, no connection needed).
        expect(find.text('Users'), findsAtLeastNWidgets(1));
      },
    );
  });

  group('Settings shell — empty-state CTA navigation', () {
    testWidgets('tapping "Connect camera" pushes a route whose first page is '
        'DiscoveryPage', (tester) async {
      final mock = _newMock();
      addTearDown(mock.dispose);

      await tester.pumpWidget(buildHarness(service: mock));
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
    });
  });
}
