// Settings Streaming section tests — now covers StreamingDestinationsPage.
//
// The streaming section on SettingsPage is a compact nav row. This file
// pumps StreamingDestinationsPage directly to test add / edit / delete /
// empty state behavior (AE7).
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
import 'package:scout_camera/pages/streaming_destinations_page.dart';
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
      activeUserProvider.overrideWith((_) => activeUserId),
    ],
    child: const MaterialApp(home: StreamingDestinationsPage()),
  );
}

void main() {
  useDevDataStoreReset();

  group('Empty state', () {
    testWidgets('with no destinations under user-1, shows the empty note', (
      tester,
    ) async {
      final mock = _newMock();
      addTearDown(mock.dispose);

      await tester.pumpWidget(_buildHarness(service: mock));
      await tester.pumpAndSettle();

      expect(
        find.text('No streaming destinations yet. Tap + to add one.'),
        findsOneWidget,
      );
    });
  });

  group('Destinations rendered (AE7)', () {
    testWidgets('YouTube/RTMP and Custom/RTSP destinations render with '
        'provider chip + protocol pill + delete icon', (tester) async {
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

      expect(find.text('My YouTube'), findsOneWidget);
      expect(find.text('Backyard cam'), findsOneWidget);
      expect(find.text('YouTube'), findsAtLeastNWidgets(1));
      expect(find.text('Custom'), findsAtLeastNWidgets(1));
      expect(find.text('RTMP'), findsOneWidget);
      expect(find.text('RTSP'), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline), findsNWidgets(2));
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

      await tester.tap(find.text('My YouTube'));
      await tester.pumpAndSettle();

      expect(find.text('Edit destination'), findsOneWidget);
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
      expect(
        find.textContaining('Remove My YouTube from YouTube RTMP?'),
        findsOneWidget,
      );
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
    });

    testWidgets('confirming delete removes the row', (tester) async {
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
      expect(
        find.text('No streaming destinations yet. Tap + to add one.'),
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
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('My YouTube'), findsOneWidget);
    });
  });

  group('Add destination happy path (AE7)', () {
    testWidgets('FAB → form → YouTube + URL + key → new row appears', (
      tester,
    ) async {
      final mock = _newMock();
      addTearDown(mock.dispose);

      await tester.pumpWidget(_buildHarness(service: mock));
      await tester.pumpAndSettle();

      // Tap the FAB.
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('streaming-url-field')),
        'rtmp://a.rtmp.youtube.com/live2',
      );
      await tester.enterText(
        find.byKey(const Key('streaming-key-field')),
        'my-secret-key',
      );

      await tester.tap(find.text('Add destination').last);
      await tester.pumpAndSettle();

      expect(find.text('YouTube'), findsAtLeastNWidgets(1));
      expect(find.text('RTMP'), findsOneWidget);
      expect(
        DevDataStore.instance.listStreamingDestinations('user-1'),
        hasLength(1),
      );
    });
  });

  group('Active user switch', () {
    testWidgets('destinations scoped to active user; user-2 has none', (
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

      late ProviderContainer container;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            bleServiceProvider.overrideWithValue(mock),
            activeCameraIdProvider.overrideWith((_) => _kFakeDeviceId),
            activeUserProvider.overrideWith((_) => 'user-1'),
          ],
          child: Builder(
            builder: (ctx) {
              container = ProviderScope.containerOf(ctx);
              return const MaterialApp(home: StreamingDestinationsPage());
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('My YouTube'), findsOneWidget);

      DevDataStore.instance.setActiveUser('user-2');
      container.read(activeUserProvider.notifier).state = 'user-2';
      await tester.pumpAndSettle();

      expect(find.text('My YouTube'), findsNothing);
      expect(
        find.text('No streaming destinations yet. Tap + to add one.'),
        findsOneWidget,
      );
    });
  });
}
