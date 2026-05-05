// U9 — Settings Streaming-section tests.
//
// We override `connectionStateProvider(activeId)` directly with a finite
// Stream so `pumpAndSettle` can terminate without touching the mock's real
// connect path (which spawns a Timer.periodic for telemetry). We never call
// `mock.connect()`.
//
// Test isolation: `useDevDataStoreReset()` re-seeds the DevDataStore between
// tests so the seed users (Coach Diego = user-1, Coach Maria = user-2) are
// always there. We populate streaming destinations directly via
// `DevDataStore.instance.createStreamingDestination` for setup speed.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scout_camera/ble/dev_data_store.dart';
import 'package:scout_camera/ble/mock_ble_service.dart';
import 'package:scout_camera/models/device.dart';
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

Widget _buildHarness({
  required MockBleService service,
  String activeUserId = 'user-1',
}) {
  return ProviderScope(
    overrides: [
      bleServiceProvider.overrideWithValue(service),
      activeCameraIdProvider.overrideWith((_) => _kFakeDeviceId),
      connectionStateProvider(_kFakeDeviceId).overrideWith(
        (_) => Stream<CameraConnectionState>.value(
          CameraConnectionState.connected,
        ),
      ),
      activeUserProvider.overrideWith((_) => activeUserId),
    ],
    child: const MaterialApp(home: SettingsPage()),
  );
}

void main() {
  useDevDataStoreReset();

  group('Empty state', () {
    testWidgets('with no destinations under user-1, the section card shows '
        'the "No streaming destinations yet" note above the Add row', (
      tester,
    ) async {
      final mock = _newMock();
      addTearDown(mock.dispose);

      await tester.pumpWidget(_buildHarness(service: mock));
      await tester.pumpAndSettle();

      // Scroll the streaming section into view (camera + user cards push
      // it below the fold on default test viewport).
      await tester.scrollUntilVisible(
        find.text('No streaming destinations yet. Tap below to add one.'),
        200,
      );
      expect(
        find.text('No streaming destinations yet. Tap below to add one.'),
        findsOneWidget,
      );
      expect(find.text('Add destination'), findsOneWidget);
    });
  });

  group('Destinations rendered', () {
    testWidgets('YouTube/RTMP and Custom/RTSP destinations render with '
        'provider chip + protocol pill + delete icon', (tester) async {
      // Pre-populate user-1 with two destinations.
      DevDataStore.instance.createStreamingDestination(
        'user-1',
        const StreamingDestinationDraft(
          name: 'My YouTube',
          provider: StreamingProvider.youtube,
          protocol: StreamingProtocol.rtmp,
          config: RtmpConfig(
            url: 'rtmp://a.rtmp.youtube.com/live2',
            streamKey: 'k1',
          ),
        ),
      );
      DevDataStore.instance.createStreamingDestination(
        'user-1',
        const StreamingDestinationDraft(
          name: 'Backyard cam',
          provider: StreamingProvider.custom,
          protocol: StreamingProtocol.rtsp,
          config: RtspConfig(url: 'rtsp://192.168.1.50/stream'),
        ),
      );

      final mock = _newMock();
      addTearDown(mock.dispose);

      await tester.pumpWidget(_buildHarness(service: mock));
      await tester.pumpAndSettle();

      // Scroll to streaming section.
      await tester.scrollUntilVisible(find.text('My YouTube'), 200);
      expect(find.text('My YouTube'), findsOneWidget);
      expect(find.text('Backyard cam'), findsOneWidget);

      // Provider chip labels — note "YouTube" also appears in the provider
      // chip; we just assert at-least one occurrence.
      expect(find.text('YouTube'), findsAtLeastNWidgets(1));
      expect(find.text('Custom'), findsAtLeastNWidgets(1));

      // Protocol labels (RTMP / RTSP) appear as the row subtitle.
      expect(find.text('RTMP'), findsOneWidget);
      expect(find.text('RTSP'), findsOneWidget);

      // One delete icon per destination row. The User section's Maria row
      // also has one, so we have at least 3.
      expect(find.byIcon(Icons.delete_outline), findsAtLeastNWidgets(3));
    });
  });

  group('Tap row opens edit mode', () {
    testWidgets('tapping a destination row opens the form sheet pre-filled '
        'with the destination name', (tester) async {
      DevDataStore.instance.createStreamingDestination(
        'user-1',
        const StreamingDestinationDraft(
          name: 'My YouTube',
          provider: StreamingProvider.youtube,
          protocol: StreamingProtocol.rtmp,
          config: RtmpConfig(
            url: 'rtmp://a.rtmp.youtube.com/live2',
            streamKey: 'k1',
          ),
        ),
      );

      final mock = _newMock();
      addTearDown(mock.dispose);

      await tester.pumpWidget(_buildHarness(service: mock));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(find.text('My YouTube'), 200);
      await tester.tap(find.text('My YouTube'));
      await tester.pumpAndSettle();

      // Edit-mode title.
      expect(find.text('Edit destination'), findsOneWidget);
      // Name field is pre-filled with the destination's name. We find the
      // Name field by key (defined in the form sheet).
      final nameField = tester.widget<TextField>(
        find.byKey(const Key('streaming-name-field')),
      );
      expect(nameField.controller!.text, 'My YouTube');
    });
  });

  group('Delete dialog', () {
    testWidgets('tapping the trailing delete icon opens the destructive '
        'confirm dialog with the destination name in the body', (tester) async {
      DevDataStore.instance.createStreamingDestination(
        'user-1',
        const StreamingDestinationDraft(
          name: 'My YouTube',
          provider: StreamingProvider.youtube,
          protocol: StreamingProtocol.rtmp,
          config: RtmpConfig(
            url: 'rtmp://a.rtmp.youtube.com/live2',
            streamKey: 'k1',
          ),
        ),
      );

      final mock = _newMock();
      addTearDown(mock.dispose);

      await tester.pumpWidget(_buildHarness(service: mock));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(find.text('My YouTube'), 200);

      // The delete icon for the destination row — find the row first then
      // the IconButton inside it.
      final destRow = find.ancestor(
        of: find.text('My YouTube'),
        matching: find.byType(InkWell),
      );
      final deleteBtn = find.descendant(
        of: destRow.first,
        matching: find.byIcon(Icons.delete_outline),
      );
      await tester.tap(deleteBtn);
      await tester.pumpAndSettle();

      expect(find.text('Delete destination?'), findsOneWidget);
      // Body contains the name + provider + protocol.
      expect(
        find.textContaining('Remove My YouTube from YouTube RTMP?'),
        findsOneWidget,
      );
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
    });

    testWidgets('confirming delete removes the row from the section', (
      tester,
    ) async {
      DevDataStore.instance.createStreamingDestination(
        'user-1',
        const StreamingDestinationDraft(
          name: 'My YouTube',
          provider: StreamingProvider.youtube,
          protocol: StreamingProtocol.rtmp,
          config: RtmpConfig(
            url: 'rtmp://a.rtmp.youtube.com/live2',
            streamKey: 'k1',
          ),
        ),
      );

      final mock = _newMock();
      addTearDown(mock.dispose);

      await tester.pumpWidget(_buildHarness(service: mock));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(find.text('My YouTube'), 200);

      final destRow = find.ancestor(
        of: find.text('My YouTube'),
        matching: find.byType(InkWell),
      );
      final deleteBtn = find.descendant(
        of: destRow.first,
        matching: find.byIcon(Icons.delete_outline),
      );
      await tester.tap(deleteBtn);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(find.text('My YouTube'), findsNothing);
      // The empty-state note is back.
      expect(
        find.text('No streaming destinations yet. Tap below to add one.'),
        findsOneWidget,
      );
    });

    testWidgets('canceling delete keeps the row', (tester) async {
      DevDataStore.instance.createStreamingDestination(
        'user-1',
        const StreamingDestinationDraft(
          name: 'My YouTube',
          provider: StreamingProvider.youtube,
          protocol: StreamingProtocol.rtmp,
          config: RtmpConfig(
            url: 'rtmp://a.rtmp.youtube.com/live2',
            streamKey: 'k1',
          ),
        ),
      );

      final mock = _newMock();
      addTearDown(mock.dispose);

      await tester.pumpWidget(_buildHarness(service: mock));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(find.text('My YouTube'), 200);

      final destRow = find.ancestor(
        of: find.text('My YouTube'),
        matching: find.byType(InkWell),
      );
      final deleteBtn = find.descendant(
        of: destRow.first,
        matching: find.byIcon(Icons.delete_outline),
      );
      await tester.tap(deleteBtn);
      await tester.pumpAndSettle();

      // Cancel button in the dialog.
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('My YouTube'), findsOneWidget);
    });
  });

  group('Add destination happy path', () {
    testWidgets('Add destination → YouTube default + URL + Stream key → '
        'new row appears with YouTube + RTMP labels', (tester) async {
      final mock = _newMock();
      addTearDown(mock.dispose);

      await tester.pumpWidget(_buildHarness(service: mock));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(find.text('Add destination'), 200);
      await tester.tap(find.text('Add destination'));
      await tester.pumpAndSettle();

      // YouTube is the default provider; protocol is fixed to RTMP.
      // Fill URL + Stream key.
      await tester.enterText(
        find.byKey(const Key('streaming-url-field')),
        'rtmp://a.rtmp.youtube.com/live2',
      );
      await tester.enterText(
        find.byKey(const Key('streaming-key-field')),
        'my-secret-key',
      );

      // The submit button on the sheet reads "Add destination".
      // The Settings page's "Add destination" row is also still in the
      // tree; tap the bottom-most one (the sheet's button).
      await tester.tap(find.text('Add destination').last);
      await tester.pumpAndSettle();

      // The destination should now render in the section list.
      expect(find.text('YouTube'), findsAtLeastNWidgets(1));
      expect(find.text('RTMP'), findsOneWidget);
      // The DevDataStore got the destination.
      expect(
        DevDataStore.instance.listStreamingDestinations('user-1'),
        hasLength(1),
      );
    });
  });

  group('Active user switch', () {
    testWidgets('with a destination under user-1, switching active user to '
        'user-2 hides the destination', (tester) async {
      DevDataStore.instance.createStreamingDestination(
        'user-1',
        const StreamingDestinationDraft(
          name: 'My YouTube',
          provider: StreamingProvider.youtube,
          protocol: StreamingProtocol.rtmp,
          config: RtmpConfig(
            url: 'rtmp://a.rtmp.youtube.com/live2',
            streamKey: 'k1',
          ),
        ),
      );

      final mock = _newMock();
      addTearDown(mock.dispose);

      // Build a container we can mutate so we can flip activeUserProvider.
      late ProviderContainer container;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            bleServiceProvider.overrideWithValue(mock),
            activeCameraIdProvider.overrideWith((_) => _kFakeDeviceId),
            connectionStateProvider(_kFakeDeviceId).overrideWith(
              (_) => Stream<CameraConnectionState>.value(
                CameraConnectionState.connected,
              ),
            ),
          ],
          child: Builder(
            builder: (ctx) {
              container = ProviderScope.containerOf(ctx);
              return const MaterialApp(home: SettingsPage());
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // user-1 is active by default (DevDataStore seed). Streaming row
      // visible.
      await tester.scrollUntilVisible(find.text('My YouTube'), 200);
      expect(find.text('My YouTube'), findsOneWidget);

      // Flip to user-2 directly via the provider AND DevDataStore so
      // BleService's getActiveUser returns user-2.
      DevDataStore.instance.setActiveUser('user-2');
      container.read(activeUserProvider.notifier).state = 'user-2';
      await tester.pumpAndSettle();

      // user-2 has no destinations.
      expect(find.text('My YouTube'), findsNothing);
      // The empty-state note is visible (after scroll).
      await tester.scrollUntilVisible(
        find.text('No streaming destinations yet. Tap below to add one.'),
        200,
      );
      expect(
        find.text('No streaming destinations yet. Tap below to add one.'),
        findsOneWidget,
      );
    });
  });
}
