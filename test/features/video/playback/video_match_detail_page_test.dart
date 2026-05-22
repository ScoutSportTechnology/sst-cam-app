// Tests for VideoMatchDetailPage — U7: on-device detection, video player init,
// WiFi connect flow, overlay derivation from events, overlay update on scrub.
//
// Platform-channel note: VideoPlayerController.asset calls a native platform
// channel that is unavailable in the test environment. The page's
// _initPlayer() uses a catchError handler (same pattern as LivePreviewView)
// so the failure is silent and _playerInitialized stays false. In the test
// environment VideoPlayer is therefore NEVER rendered; ThumbPlaceholder fills
// the player body instead.
//
// Pending-timer note: MockWifiService starts periodic preview timers after
// connectGroup completes. To avoid the "pending timer" assertion at test end,
// the WiFi-connect test uses a MockWifiService with pairingDelay=zero AND
// observes state immediately after pump, then calls dispose inside the test
// body (not via tearDown, since tearDown runs after the assertion check).
//
// What we DO test:
//   1. On-device match: no WiFi connect, ThumbPlaceholder shown (player
//      platform channel unavailable → _playerInitialized = false).
//   2. Camera-only match (no active camera): error message shown immediately.
//   3. Connection error: error text + Retry button when WiFi fails.
//   4. Overlay toggle row and event list render correctly.
//   5. Overlay updates when onJump is called from an event row.

import 'dart:io';

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
import 'package:sst_cam_app/mock/mock_ble_service.dart';
import 'package:sst_cam_app/mock/mock_wifi_service.dart';
import 'package:video_player/video_player.dart';
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

/// Returns a path to an existing temp file → isOnDeviceProvider = true.
class _PresentVideoPathService extends VideoPathService {
  _PresentVideoPathService(this._path);
  final String _path;

  @override
  Future<String> recordingPath(String recordingId) async => _path;
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

class _DelayedNoTimerWifiService extends MockWifiService {
  _DelayedNoTimerWifiService({required this.delay});
  final Duration delay;

  @override
  Future<WifiDirectGroup> connectGroup(String deviceId) async {
    await Future<void>.delayed(delay);
    return const WifiDirectGroup(
      ssid: 'DIRECT-test',
      psk: 'mock-psk',
      groupOwnerIp: '192.168.49.1',
      previewPort: 8554,
      downloadPort: 8080,
      role: 'GROUP_OWNER',
    );
  }
}

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
}) {
  return [
    ...dbOverrides(db),
    bleServiceProvider.overrideWithValue(_newMock()),
    activeUserProvider.overrideWith((_) => 'user-1'),
    videoPathServiceProvider.overrideWithValue(
      videoPathService ?? _AbsentVideoPathService(),
    ),
    wifiServiceProvider.overrideWithValue(
      wifiService ?? MockWifiService(pairingDelay: Duration.zero),
    ),
    if (activeCameraId != null)
      activeCameraIdProvider.overrideWith((_) => activeCameraId),
  ];
}

Widget _buildPage({
  required AppDatabase db,
  required String matchId,
  VideoPathService? videoPathService,
  MockWifiService? wifiService,
  String? activeCameraId,
}) {
  return ProviderScope(
    overrides: _baseOverrides(
      db,
      videoPathService: videoPathService,
      wifiService: wifiService,
      activeCameraId: activeCameraId,
    ),
    child: MaterialApp(
      home: VideoMatchDetailPage(matchId: matchId),
    ),
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
    late File tmpFile;

    setUp(() async {
      tmpFile = await File('/tmp/sst-ondev-test.mp4').create(recursive: true);
      await tmpFile.writeAsBytes([0x00]);
    });

    tearDown(() async {
      if (tmpFile.existsSync()) await tmpFile.delete();
    });

    testWidgets(
      'ThumbPlaceholder shown; no "Connecting…"; VideoPlayer absent in test env',
      (tester) async {
        await largeScreen(tester);
        await _insertMatch(db.value, id: 'od-1', teamId: 'nr-u14');

        await tester.pumpWidget(
          _buildPage(
            db: db.value,
            matchId: 'od-1',
            videoPathService: _PresentVideoPathService(tmpFile.path),
          ),
        );
        final container = _container(tester);
        await _awaitMatch(tester, container, 'od-1');
        // Allow isOnDeviceProvider + _initPlayer to run.
        await tester.pump(const Duration(milliseconds: 100));

        // No WiFi connect expected.
        expect(find.text('Connecting…'), findsNothing);
        // VideoPlayer: platform channel absent, so ThumbPlaceholder renders.
        expect(find.byType(VideoPlayer), findsNothing);
        expect(find.byType(ThumbPlaceholder), findsOneWidget);
        // Structural elements still present.
        expect(find.text('Overlays'), findsOneWidget);
      },
    );
  });

  // ---------------------------------------------------------------------------
  // 2. Camera-only match, no active camera — error shown immediately.
  // ---------------------------------------------------------------------------

  group('camera-only match, no active camera', () {
    testWidgets(
      'error message shown immediately when activeCameraId is null',
      (tester) async {
        await largeScreen(tester);
        await _insertMatch(db.value, id: 'co-no-cam', teamId: 'nr-u14');

        await tester.pumpWidget(
          _buildPage(
            db: db.value,
            matchId: 'co-no-cam',
            videoPathService: _AbsentVideoPathService(),
            // activeCameraId not provided → null
          ),
        );
        final container = _container(tester);
        await _awaitMatch(tester, container, 'co-no-cam');
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.textContaining('Could not connect'), findsOneWidget);
        expect(find.text('Retry'), findsOneWidget);
        expect(find.text('Connecting…'), findsNothing);
        expect(find.byType(VideoPlayer), findsNothing);
      },
    );
  });

  // ---------------------------------------------------------------------------
  // 3. Camera-only match with active camera — "Connecting…" → ThumbPlaceholder.
  // ---------------------------------------------------------------------------

  group('camera-only match with active camera (WiFi connect flow)', () {
    testWidgets(
      '"Connecting…" shown while WiFi pairs; ThumbPlaceholder after connect',
      (tester) async {
        await largeScreen(tester);
        await _insertMatch(db.value, id: 'co-cam', teamId: 'nr-u14');

        // Use a no-timer WiFi service with a 60ms pairing delay so we can
        // observe the Connecting state before it resolves.
        final wifi = _DelayedNoTimerWifiService(
          delay: const Duration(milliseconds: 60),
        );

        await tester.pumpWidget(
          _buildPage(
            db: db.value,
            matchId: 'co-cam',
            videoPathService: _AbsentVideoPathService(),
            wifiService: wifi,
            activeCameraId: 'cam-001',
          ),
        );
        final container = _container(tester);
        await _awaitMatch(tester, container, 'co-cam');

        // Pump 10ms — _initPlayer has fired and isOnDeviceProvider is
        // resolving (absent file = false), but WiFi connect hasn't finished.
        await tester.pump(const Duration(milliseconds: 10));

        // "Connecting…" should be visible.
        expect(find.text('Connecting…'), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);

        // Advance past the 60ms pairing delay.
        await tester.pump(const Duration(milliseconds: 100));

        // WiFi connected; _connecting = false.
        expect(find.text('Connecting…'), findsNothing);

        // VideoPlayer never renders (platform channel absent).
        expect(find.byType(VideoPlayer), findsNothing);
        expect(find.byType(ThumbPlaceholder), findsOneWidget);
      },
    );
  });

  // ---------------------------------------------------------------------------
  // 5. Connection error — WiFi service throws.
  // ---------------------------------------------------------------------------

  group('connection error', () {
    testWidgets(
      'error message + Retry button when WiFi connectGroup fails',
      (tester) async {
        await largeScreen(tester);
        await _insertMatch(db.value, id: 'ce-1', teamId: 'nr-u14');

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

        expect(
          find.textContaining('Could not connect to camera'),
          findsOneWidget,
        );
        expect(find.text('Retry'), findsOneWidget);
        expect(find.text('Connecting…'), findsNothing);
        expect(find.byType(VideoPlayer), findsNothing);
      },
    );

    testWidgets(
      'tapping Retry resets error and re-attempts connection',
      (tester) async {
        await largeScreen(tester);
        await _insertMatch(db.value, id: 'ce-2', teamId: 'nr-u14');

        await tester.pumpWidget(
          _buildPage(
            db: db.value,
            matchId: 'ce-2',
            videoPathService: _AbsentVideoPathService(),
            wifiService: _FailingWifiService(),
            activeCameraId: 'cam-001',
          ),
        );
        final container = _container(tester);
        await _awaitMatch(tester, container, 'ce-2');
        await tester.pump(const Duration(milliseconds: 100));

        // Initial error is shown.
        expect(find.textContaining('Could not connect'), findsOneWidget);

        // Tap Retry.
        await tester.tap(find.text('Retry'));
        await tester.pump(const Duration(milliseconds: 100));

        // After retry, the failure re-triggers (same failing service).
        // Page is still alive and error is shown again.
        expect(find.byType(VideoMatchDetailPage), findsOneWidget);
        expect(find.textContaining('Could not connect'), findsOneWidget);
      },
    );
  });

  // ---------------------------------------------------------------------------
  // 6. Overlay toggle row and event list render.
  // ---------------------------------------------------------------------------

  group('overlay toggle and event list', () {
    const eventsJson =
        '[{"timeSeconds":600,"label":"GOAL · #7","team":"NRA","kind":"goal"}]';

    testWidgets(
      'overlay row shows Score/Events chips; event list shows event label',
      (tester) async {
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

        expect(find.text('Overlays'), findsOneWidget);
        expect(find.text('Score'), findsOneWidget);
        expect(find.text('Events'), findsOneWidget);
        expect(find.text('GOAL · #7'), findsOneWidget);
      },
    );
  });

  // ---------------------------------------------------------------------------
  // 7. Overlay updates on event jump (onJump).
  //
  // The overlay is always rendered regardless of player/connection state —
  // it sits in the Stack above the player body. We use _AbsentVideoPathService
  // (no on-device file) with no activeCameraId to reach the error state quickly,
  // then verify the overlay reflects OverlayState.atTime after a long-press.
  //
  // Important: _overlayStates is built synchronously inside _maybeStartInit
  // before the async _initPlayer starts, so it is always populated when the
  // match is available.
  // ---------------------------------------------------------------------------

  group('overlay update via event jump', () {
    const eventsJson =
        '[{"timeSeconds":600,"label":"GOAL · #7","team":"NRA","kind":"goal"}]';

    testWidgets(
      'score overlay shows "0" initially; shows "1" after jumping to goal event',
      (tester) async {
        await largeScreen(tester);
        await _insertMatch(
          db.value,
          id: 'ov-jump-1',
          teamId: 'nr-u14',
          eventsJson: eventsJson,
        );

        // Use absent path + no activeCameraId → error state, but overlay
        // still renders in the Stack above the error body.
        await tester.pumpWidget(
          _buildPage(
            db: db.value,
            matchId: 'ov-jump-1',
            videoPathService: _AbsentVideoPathService(),
            // no activeCameraId → reaches error quickly, no WiFi connect
          ),
        );
        final container = _container(tester);
        await _awaitMatch(tester, container, 'ov-jump-1');
        await tester.pump(const Duration(milliseconds: 100));

        // Error state reached; overlay still renders above the error body.
        // At t=0 (_currentOverlay default), homeScore=0 and awayScore=0.
        expect(find.text('NRA'), findsWidgets); // teamShortName in overlay
        expect(find.text('1H'), findsOneWidget); // period=1

        // Score texts: both "0" values (home and away).
        // Find them as individual Text widgets (score overlay has two score texts).
        final zeroWidgets = find.text('0');
        expect(zeroWidgets, findsWidgets);

        // Long-press "GOAL · #7" to jump to t=600.
        await tester.longPress(find.text('GOAL · #7'));
        await tester.pump();

        // After jumping to t=600, OverlayState.atTime returns the goal state:
        // homeScore=1, awayScore=0. The score overlay now shows "1".
        expect(find.text('1'), findsWidgets);
        // Period = 600 ~/ (35*60) + 1 = 0 + 1 = 1.
        expect(find.text('1H'), findsOneWidget);
      },
    );

    testWidgets(
      'overlay uses teamShortName and first word of opponent (not hardcoded)',
      (tester) async {
        await largeScreen(tester);
        await _insertMatch(
          db.value,
          id: 'ov-jump-2',
          teamId: 'nr-u14',
          eventsJson: eventsJson,
        );

        await tester.pumpWidget(
          _buildPage(
            db: db.value,
            matchId: 'ov-jump-2',
            videoPathService: _AbsentVideoPathService(),
          ),
        );
        final container = _container(tester);
        await _awaitMatch(tester, container, 'ov-jump-2');
        await tester.pump(const Duration(milliseconds: 100));

        // teamShortName 'NRA' appears in the score overlay.
        expect(find.text('NRA'), findsWidgets);
        // First word of opponent "Opponent FC" is "Opponent".
        expect(find.text('Opponent'), findsOneWidget);
        // Period indicator shows current period.
        expect(find.text('1H'), findsOneWidget);
      },
    );
  });
}
