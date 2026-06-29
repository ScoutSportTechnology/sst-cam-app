// Tests for VideoMatchDetailPage — on-device detection, video player init,
// overlay derivation from events, download-to-watch flow, event rows.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sst_cam_app/core/ble/ble_providers.dart';
import 'package:sst_cam_app/core/models/wifi.dart' show WifiDirectGroup;
import 'package:sst_cam_app/core/services/video_path_service.dart';
import 'package:sst_cam_app/core/state/db_providers.dart';
import 'package:sst_cam_app/core/wifi/wifi_providers.dart';
import 'package:sst_cam_app/core/widgets/wf_card.dart' show ThumbPlaceholder;
import 'package:sst_cam_app/features/camera/camera_state.dart'
    show activeCameraIdProvider;
import 'package:sst_cam_app/features/settings/users/users_state.dart'
    show activeUserProvider;
import 'package:sst_cam_app/features/video/playback/video_match_detail_page.dart';
import 'package:sst_cam_app/features/video/video_state.dart';
import 'package:sst_cam_app/mock/emulator/mock_ble_service.dart';
import 'package:sst_cam_app/mock/emulator/mock_wifi_service.dart';
import 'package:video_player/video_player.dart' show VideoPlayer;
import 'package:drift/drift.dart' show Value;

import '../../../test_helpers.dart';

// ---------------------------------------------------------------------------
// Stub VideoPathService variants
// ---------------------------------------------------------------------------

/// Always returns a path to a non-existent file → isOnDeviceProvider = false.
class _AbsentVideoPathService extends VideoPathService {
  @override
  Future<String> recordingPath(String recordingId) async =>
      '/nonexistent/$recordingId.mp4';
}

// ---------------------------------------------------------------------------
// WiFi service that throws immediately.
// ---------------------------------------------------------------------------

class _FailingWifiService extends MockWifiService {
  @override
  Future<WifiDirectGroup> connectGroup(String deviceId) async {
    throw Exception('Simulated WiFi failure');
  }
}

// ---------------------------------------------------------------------------
// WiFi service that succeeds after a short artificial delay but never
// starts the periodic preview timers — safe for test environments where
// pending timers cause assertion failures.
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

MockBleService _newMock() => MockBleService(
  scanDeviceAppearDelays: const [Duration.zero],
  connectionDelay: Duration.zero,
  failureRate: 0.0,
  randomSeed: 42,
);

List<Override> _baseOverrides(
  AppDatabase db, {
  VideoPathService? videoPathService,
  MockWifiService? wifiService,
  String? activeCameraId,
  bool? forceIsOnDevice,
}) {
  return [
    ...dbOverrides(db),
    bleServiceProvider.overrideWithValue(_newMock()),
    liveSessionActiveProvider.overrideWithValue(false),
    activeUserProvider.overrideWith((_) => 'user-1'),
    videoPathServiceProvider.overrideWithValue(
      videoPathService ?? _AbsentVideoPathService(),
    ),
    wifiServiceProvider.overrideWithValue(
      wifiService ?? MockWifiService(pairingDelay: Duration.zero),
    ),
    if (activeCameraId != null)
      activeCameraIdProvider.overrideWith((_) => activeCameraId),
    if (forceIsOnDevice != null)
      isOnDeviceProvider.overrideWith((ref, matchId) async => forceIsOnDevice),
  ];
}

Widget _buildPage({
  required AppDatabase db,
  required String matchId,
  VideoPathService? videoPathService,
  MockWifiService? wifiService,
  String? activeCameraId,
  bool? forceIsOnDevice,
}) {
  return ProviderScope(
    overrides: _baseOverrides(
      db,
      videoPathService: videoPathService,
      wifiService: wifiService,
      activeCameraId: activeCameraId,
      forceIsOnDevice: forceIsOnDevice,
    ),
    child: MaterialApp(home: VideoMatchDetailPage(matchId: matchId)),
  );
}

Future<void> _insertMatch(
  AppDatabase db, {
  required String id,
  required String teamId,
  int sizeMb = 200,
  String eventsJson = '[]',
}) async {
  await db.teamsDao.insertTeamMatch(
    TeamMatchesTableCompanion.insert(
      id: id,
      teamId: teamId,
      opponent: 'Opponent FC',
      date: 'May 01',
      result: 'W 2-0',
      kind: 'past',
      numPeriods: 2,
      periodLengthSeconds: 35 * 60,
      sizeMb: Value(sizeMb),
      eventsJson: Value(eventsJson),
    ),
  );
}

Future<void> _awaitMatch(
  WidgetTester tester,
  ProviderContainer container,
  String matchId,
) async {
  for (var i = 0; i < 50; i++) {
    await tester.pump(const Duration(milliseconds: 10));
    final m = container.read(libraryMatchProvider(matchId));
    if (m != null) break;
  }
  await tester.pump();
}

ProviderContainer _container(WidgetTester tester) {
  return ProviderScope.containerOf(
    tester.element(find.byType(VideoMatchDetailPage)),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  final db = useInMemoryDb();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  // Large surface to avoid layout overflow.
  Future<void> largeScreen(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  // ---------------------------------------------------------------------------
  // 1. On-device match — no WiFi connect, ThumbPlaceholder shown.
  // ---------------------------------------------------------------------------

  group('on-device match', () {
    testWidgets(
      'ThumbPlaceholder shown; no "Connecting…"; VideoPlayer absent in test env',
      (tester) async {
        await largeScreen(tester);
        await _insertMatch(db.value, id: 'od-1', teamId: 'nr-u14');

        await tester.pumpWidget(
          _buildPage(
            db: db.value,
            matchId: 'od-1',
            videoPathService: _AbsentVideoPathService(),
            // forceIsOnDevice ensures _isOnDevice = true is set immediately
            // without waiting for the file-existence async chain.
            forceIsOnDevice: true,
          ),
        );
        final container = _container(tester);
        await _awaitMatch(tester, container, 'od-1');
        // Allow _initPlayer to run and fail (platform channel absent in tests).
        for (var i = 0; i < 6; i++) {
          await tester.pump();
        }

        // No "Download to watch" prompt for an on-device match.
        expect(find.text('Download to watch'), findsNothing);
        // No WiFi connect attempted.
        expect(find.text('Connecting…'), findsNothing);
        // VideoPlayer: platform channel absent, so ThumbPlaceholder renders.
        expect(find.byType(VideoPlayer), findsNothing);
        expect(find.byType(ThumbPlaceholder), findsOneWidget);
        // No app-drawn overlay row (#6 A6a playback): overlay is firmware-baked.
        expect(find.text('Overlays'), findsNothing);
      },
    );
  });

  // ---------------------------------------------------------------------------
  // 2. Camera-only match — "Download to watch" prompt shown.
  // ---------------------------------------------------------------------------

  group('camera-only match', () {
    testWidgets('"Download to watch" prompt shown when match not on device', (
      tester,
    ) async {
      await largeScreen(tester);
      await _insertMatch(db.value, id: 'co-no-cam', teamId: 'nr-u14');

      await tester.pumpWidget(
        _buildPage(
          db: db.value,
          matchId: 'co-no-cam',
          videoPathService: _AbsentVideoPathService(),
        ),
      );
      final container = _container(tester);
      await _awaitMatch(tester, container, 'co-no-cam');
      await tester.pump(const Duration(milliseconds: 100));

      // New behavior: single WfButton CTA, not WiFi error.
      expect(find.textContaining('Download to watch'), findsOneWidget);
      expect(find.text('Connecting…'), findsNothing);
      expect(find.text('Retry'), findsNothing);
      expect(find.byType(VideoPlayer), findsNothing);
    });
  });

  // ---------------------------------------------------------------------------
  // 5. Camera-only match shows download prompt regardless of WiFi state.
  // ---------------------------------------------------------------------------

  group('camera-only always shows download prompt', () {
    testWidgets('no WiFi connect attempted; "Download to watch" always shown', (
      tester,
    ) async {
      await largeScreen(tester);
      await _insertMatch(db.value, id: 'ce-1', teamId: 'nr-u14');

      // Even with a connected camera, the page shows "Download to watch"
      // rather than auto-streaming.
      await tester.pumpWidget(
        _buildPage(
          db: db.value,
          matchId: 'ce-1',
          videoPathService: _AbsentVideoPathService(),
          wifiService: _FailingWifiService(),
          activeCameraId: 'cam-001',
        ),
      );
      final container = _container(tester);
      await _awaitMatch(tester, container, 'ce-1');
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.textContaining('Download to watch'), findsOneWidget);
      expect(find.textContaining('Could not connect'), findsNothing);
      expect(find.text('Connecting…'), findsNothing);
      expect(find.byType(VideoPlayer), findsNothing);
    });
  });

  // ---------------------------------------------------------------------------
  // 6. Event list renders (no app overlay row anymore — #6 A6a playback).
  // ---------------------------------------------------------------------------

  group('event list', () {
    const eventsJson =
        '[{"timeSeconds":600,"label":"GOAL · #7","team":"NRA","kind":"goal"}]';

    testWidgets('event list shows the event label; no app overlay row', (
      tester,
    ) async {
      await largeScreen(tester);
      await _insertMatch(
        db.value,
        id: 'ovt-1',
        teamId: 'nr-u14',
        eventsJson: eventsJson,
      );

      await tester.pumpWidget(
        _buildPage(
          db: db.value,
          matchId: 'ovt-1',
          videoPathService: _AbsentVideoPathService(),
        ),
      );
      final container = _container(tester);
      await _awaitMatch(tester, container, 'ovt-1');
      await tester.pump(const Duration(milliseconds: 100));

      // The overlay toggle row is gone (overlay is firmware-baked now).
      expect(find.text('Overlays'), findsNothing);
      expect(find.text('GOAL · #7'), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  // Download-to-watch and event row (post-U10 refactor).
  // ---------------------------------------------------------------------------

  group('download-to-watch and event rows', () {
    const eventsJson =
        '[{"timeSeconds":2242,"label":"GOAL · #7","team":"NRA","kind":"goal"}]';

    testWidgets(
      'match not on device shows "Download to watch" prompt, no Clip button in rows',
      (tester) async {
        await largeScreen(tester);
        await _insertMatch(
          db.value,
          id: 'dtw-1',
          teamId: 'nr-u14',
          eventsJson: eventsJson,
        );

        await tester.pumpWidget(
          _buildPage(
            db: db.value,
            matchId: 'dtw-1',
            videoPathService: _AbsentVideoPathService(),
          ),
        );
        final container = _container(tester);
        await _awaitMatch(tester, container, 'dtw-1');
        await tester.pump(const Duration(milliseconds: 100));

        // Player area shows "Download to watch" prompt.
        expect(find.textContaining('Download to watch'), findsOneWidget);
        // No per-event Clip button in the event list.
        expect(find.text('Clip'), findsNothing);
      },
    );

    testWidgets('match title shows "TeamName vs Opponent", not just date', (
      tester,
    ) async {
      await largeScreen(tester);
      await _insertMatch(
        db.value,
        id: 'title-1',
        teamId: 'nr-u14',
        eventsJson: eventsJson,
      );

      await tester.pumpWidget(
        _buildPage(
          db: db.value,
          matchId: 'title-1',
          videoPathService: _AbsentVideoPathService(),
        ),
      );
      final container = _container(tester);
      await _awaitMatch(tester, container, 'title-1');
      await tester.pump(const Duration(milliseconds: 100));

      // Title uses full team name and opponent.
      expect(find.textContaining('vs'), findsWidgets);
      // Date is not the primary/only title element.
      expect(find.text('2026-03-12'), findsNothing);
    });

    testWidgets('event row has checkbox and shows event label', (tester) async {
      await largeScreen(tester);
      await _insertMatch(
        db.value,
        id: 'row-1',
        teamId: 'nr-u14',
        eventsJson: eventsJson,
      );

      await tester.pumpWidget(
        _buildPage(
          db: db.value,
          matchId: 'row-1',
          videoPathService: _AbsentVideoPathService(),
        ),
      );
      final container = _container(tester);
      await _awaitMatch(tester, container, 'row-1');
      await tester.pump(const Duration(milliseconds: 100));

      // Event label is shown.
      expect(find.text('GOAL · #7'), findsOneWidget);
      // No Clip button.
      expect(find.text('Clip'), findsNothing);
    });
  });
}
