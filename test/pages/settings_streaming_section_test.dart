// Settings Streaming section tests — now covers StreamingDestinationsPage.
//
// The streaming section on SettingsPage is a compact nav row. This file
// pumps StreamingDestinationsPage directly to test add / edit / delete /
// empty state behavior (AE7).
//
// Test isolation: `useInMemoryDb()` provides a fresh Drift in-memory DB
// seeded with user-1 / user-2 for every test.

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sst_cam_app/mock/mock_ble_service.dart';
import 'package:sst_cam_app/pages/streaming_destinations_page.dart';
import 'package:sst_cam_app/state/app_data.dart';
import 'package:sst_cam_app/state/ble_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers.dart';

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

  Widget buildHarness({String activeUserId = 'user-1'}) {
    return ProviderScope(
      overrides: [
        ...dbOverrides(db),
        bleServiceProvider.overrideWithValue(_newMock()),
        activeUserProvider.overrideWith((_) => activeUserId),
      ],
      child: const MaterialApp(home: StreamingDestinationsPage()),
    );
  }

  group('Empty state', () {
    testWidgets('with no destinations under user-1, shows the empty note', (
      tester,
    ) async {
      await tester.pumpWidget(buildHarness());
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
      // Seed destinations directly into the in-memory DB.
      await db.value.streamingDestinationsDao.insertDestination(
        StreamingDestinationsTableCompanion.insert(
          id: 'dest-yt',
          userId: 'user-1',
          name: 'My YouTube',
          provider: 'youtube',
          protocol: 'rtmp',
          configType: 'rtmp',
          configUrl: 'rtmp://a.rtmp.youtube.com/live2',
          configStreamKey: const Value('yt-stream-key'),
        ),
      );
      await db.value.streamingDestinationsDao.insertDestination(
        StreamingDestinationsTableCompanion.insert(
          id: 'dest-rtsp',
          userId: 'user-1',
          name: 'Backyard cam',
          provider: 'custom',
          protocol: 'rtsp',
          configType: 'rtsp',
          configUrl: 'rtsp://192.168.1.50/stream',
        ),
      );

      await tester.pumpWidget(buildHarness());
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
      await db.value.streamingDestinationsDao.insertDestination(
        StreamingDestinationsTableCompanion.insert(
          id: 'dest-yt',
          userId: 'user-1',
          name: 'My YouTube',
          provider: 'youtube',
          protocol: 'rtmp',
          configType: 'rtmp',
          configUrl: 'rtmp://a.rtmp.youtube.com/live2',
          configStreamKey: const Value('yt-stream-key'),
        ),
      );

      await tester.pumpWidget(buildHarness());
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
      await db.value.streamingDestinationsDao.insertDestination(
        StreamingDestinationsTableCompanion.insert(
          id: 'dest-yt',
          userId: 'user-1',
          name: 'My YouTube',
          provider: 'youtube',
          protocol: 'rtmp',
          configType: 'rtmp',
          configUrl: 'rtmp://a.rtmp.youtube.com/live2',
          configStreamKey: const Value('yt-stream-key'),
        ),
      );

      await tester.pumpWidget(buildHarness());
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
      await db.value.streamingDestinationsDao.insertDestination(
        StreamingDestinationsTableCompanion.insert(
          id: 'dest-yt',
          userId: 'user-1',
          name: 'My YouTube',
          provider: 'youtube',
          protocol: 'rtmp',
          configType: 'rtmp',
          configUrl: 'rtmp://a.rtmp.youtube.com/live2',
          configStreamKey: const Value('yt-stream-key'),
        ),
      );

      await tester.pumpWidget(buildHarness());
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
      await db.value.streamingDestinationsDao.insertDestination(
        StreamingDestinationsTableCompanion.insert(
          id: 'dest-yt',
          userId: 'user-1',
          name: 'My YouTube',
          provider: 'youtube',
          protocol: 'rtmp',
          configType: 'rtmp',
          configUrl: 'rtmp://a.rtmp.youtube.com/live2',
          configStreamKey: const Value('yt-stream-key'),
        ),
      );

      await tester.pumpWidget(buildHarness());
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
      await tester.pumpWidget(buildHarness());
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

      // Verify via DAO that the destination was persisted.
      final rows = await db.value.streamingDestinationsDao.getForUser('user-1');
      expect(rows, hasLength(1));
    });
  });

  group('Active user switch', () {
    testWidgets('destinations scoped to active user; user-2 has none', (
      tester,
    ) async {
      await db.value.streamingDestinationsDao.insertDestination(
        StreamingDestinationsTableCompanion.insert(
          id: 'dest-yt',
          userId: 'user-1',
          name: 'My YouTube',
          provider: 'youtube',
          protocol: 'rtmp',
          configType: 'rtmp',
          configUrl: 'rtmp://a.rtmp.youtube.com/live2',
          configStreamKey: const Value('yt-stream-key'),
        ),
      );

      late ProviderContainer container;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...dbOverrides(db),
            bleServiceProvider.overrideWithValue(_newMock()),
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
