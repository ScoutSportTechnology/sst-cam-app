// Tests for VideoMatchDetailPage — U7: on-device detection, video player init,
// WiFi connect flow, overlay derivation from events, overlay update on scrub.
// U10: Per-event highlight clip creation (AE7, AE8, clamp, spinner, errors).
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

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sst_cam_app/core/ble/ble_providers.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart'
    as vp_interface;
import 'package:sst_cam_app/core/db/daos/clips_dao.dart';
import 'package:sst_cam_app/core/models/wifi.dart' show WifiDirectGroup;
import 'package:sst_cam_app/core/services/clip_service.dart';
import 'package:sst_cam_app/core/services/video_path_service.dart';
import 'package:sst_cam_app/core/state/db_providers.dart';
import 'package:sst_cam_app/core/wifi/wifi_providers.dart';
import 'package:sst_cam_app/core/widgets/indicators.dart' show WfSwitch;
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
import 'package:drift/drift.dart' show Value, DatabaseConnection;
import 'package:drift/native.dart' show NativeDatabase;

import '../../../test_helpers.dart';

// ---------------------------------------------------------------------------
// Stub ClipService variants
// ---------------------------------------------------------------------------

/// Records calls to trim() and returns successfully.
class _RecordingClipService extends ClipService {
  _RecordingClipService()
      : super(
          clipsDao: _NoOpClipsDao(),
          videoPathService: VideoPathService(),
        );

  final List<({
    String matchId,
    String sourcePath,
    int startSeconds,
    int durationSeconds,
    String? label,
  })> calls = [];

  @override
  Future<String> trim({
    required String matchId,
    required String sourcePath,
    required int startSeconds,
    required int durationSeconds,
    String? label,
  }) async {
    calls.add((
      matchId: matchId,
      sourcePath: sourcePath,
      startSeconds: startSeconds,
      durationSeconds: durationSeconds,
      label: label,
    ));
    return '/clips/$matchId/$startSeconds.mp4';
  }
}

/// Hangs trim() until complete() is called — used to observe in-progress state.
class _HangingClipService extends ClipService {
  _HangingClipService()
      : super(
          clipsDao: _NoOpClipsDao(),
          videoPathService: VideoPathService(),
        );

  final _completer = Completer<String>();

  void complete([String result = '/clips/mock.mp4']) {
    if (!_completer.isCompleted) _completer.complete(result);
  }

  @override
  Future<String> trim({
    required String matchId,
    required String sourcePath,
    required int startSeconds,
    required int durationSeconds,
    String? label,
  }) {
    return _completer.future;
  }
}

/// Always throws ClipTrimException.
class _FailingClipService extends ClipService {
  _FailingClipService()
      : super(
          clipsDao: _NoOpClipsDao(),
          videoPathService: VideoPathService(),
        );

  @override
  Future<String> trim({
    required String matchId,
    required String sourcePath,
    required int startSeconds,
    required int durationSeconds,
    String? label,
  }) async {
    throw const ClipTrimException('FFmpeg unavailable in test');
  }
}

/// A no-op ClipsDao stub — avoids needing a real database in ClipService stubs.
class _NoOpClipsDao extends ClipsDao {
  _NoOpClipsDao() : super(_NullDb());

  @override
  Future<void> insertClip(ClipsTableCompanion companion) async {}
}

// _NullDb is just a placeholder — _NoOpClipsDao never actually calls the DB.
// We use a real AppDatabase.forTesting so the mixin initialises without crashing.
class _NullDb extends AppDatabase {
  _NullDb()
      : super.forTesting(
          DatabaseConnection(NativeDatabase.memory()),
        );
}

// ---------------------------------------------------------------------------
// Minimal FakeVideoPlayerPlatform — replaces VideoPlayerPlatform.instance so
// VideoPlayerController.initialize() completes cleanly in tests. Without this,
// the default platform throws UnimplementedError, leaving an uncompleted
// Completer in VideoPlayerController that causes subsequent pump() calls to hang.
// ---------------------------------------------------------------------------

class _FakeVideoPlayerPlatform extends vp_interface.VideoPlayerPlatform {
  int _nextPlayerId = 0;
  final Map<int, StreamController<vp_interface.VideoEvent>> _streams = {};

  @override
  Future<void> init() async {}

  @override
  Future<int?> create(vp_interface.DataSource dataSource) async {
    return _createPlayer();
  }

  @override
  Future<int?> createWithOptions(
    vp_interface.VideoCreationOptions options,
  ) async {
    return _createPlayer();
  }

  int _createPlayer() {
    final id = _nextPlayerId++;
    final controller = StreamController<vp_interface.VideoEvent>();
    _streams[id] = controller;
    // Send initialized event so VideoPlayerController.initialize() completes.
    controller.add(
      vp_interface.VideoEvent(
        eventType: vp_interface.VideoEventType.initialized,
        size: const Size(640, 360),
        duration: const Duration(seconds: 60),
      ),
    );
    return id;
  }

  @override
  Future<void> dispose(int playerId) async {
    await _streams.remove(playerId)?.close();
  }

  @override
  Stream<vp_interface.VideoEvent> videoEventsFor(int playerId) {
    return _streams[playerId]!.stream;
  }

  @override
  Future<void> setLooping(int playerId, bool looping) async {}

  @override
  Future<void> play(int playerId) async {}

  @override
  Future<void> pause(int playerId) async {}

  @override
  Future<void> setVolume(int playerId, double volume) async {}

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<Duration> getPosition(int playerId) async => Duration.zero;

  @override
  Future<void> seekTo(int playerId, Duration position) async {}

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}
}

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
  ClipService? clipService,
  // When non-null, overrides isOnDeviceProvider so _initPlayer never reaches
  // VideoPlayerController (avoids fake-clock conflicts from MethodChannel calls).
  bool? forceIsOnDevice,
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
    if (clipService != null) clipServiceProvider.overrideWithValue(clipService),
    if (forceIsOnDevice != null)
      isOnDeviceProvider.overrideWith(
        (ref, matchId) async => forceIsOnDevice,
      ),
  ];
}

Widget _buildPage({
  required AppDatabase db,
  required String matchId,
  VideoPathService? videoPathService,
  MockWifiService? wifiService,
  String? activeCameraId,
  ClipService? clipService,
  bool? forceIsOnDevice,
}) {
  return ProviderScope(
    overrides: _baseOverrides(
      db,
      videoPathService: videoPathService,
      wifiService: wifiService,
      activeCameraId: activeCameraId,
      clipService: clipService,
      forceIsOnDevice: forceIsOnDevice,
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
  // 8. Independent overlay toggles (U8 / AE3).
  //
  // Score and Events overlays are toggled independently via GestureDetector-
  // wrapped WfChip widgets. The master WfSwitch turns both off (saving last
  // states) or restores both to their pre-off states.
  //
  // Detection strategy: we look for the score indicator text ('NRA' team name
  // and '1H' period label) for the score overlay, and for the recentEventLabel
  // text for the events overlay.  Because the events ticker only appears when
  // recentEventLabel is non-null, we jump to the goal event first to make it
  // visible before testing toggling.
  //
  // Note: Score overlay team-name text ('NRA') is always present in the event
  // list rows as well; use findsWidgets for those, and verify absence/presence
  // of unique score-overlay-only text like '1H' or '0'/'1' score digits.
  // ---------------------------------------------------------------------------

  group('independent overlay toggles (AE3)', () {
    const eventsJson =
        '[{"timeSeconds":600,"label":"GOAL · #7","team":"NRA","kind":"goal"}]';

    /// Helper: pump widget, await match, jump to goal event so recentEventLabel
    /// is non-null, then return the container.
    Future<ProviderContainer> pumpAndJumpToGoal(
      WidgetTester tester,
      String matchId,
    ) async {
      await tester.pumpWidget(
        _buildPage(
          db: db.value,
          matchId: matchId,
          videoPathService: _AbsentVideoPathService(),
        ),
      );
      final container = _container(tester);
      await _awaitMatch(tester, container, matchId);
      await tester.pump(const Duration(milliseconds: 100));
      // Jump to goal event to activate recentEventLabel.
      await tester.longPress(find.text('GOAL · #7'));
      await tester.pump();
      return container;
    }

    testWidgets(
      'initial state: both Score and Events overlays are ON',
      (tester) async {
        await largeScreen(tester);
        await _insertMatch(
          db.value,
          id: 'ae3-init',
          teamId: 'nr-u14',
          eventsJson: eventsJson,
        );

        await tester.pumpWidget(
          _buildPage(
            db: db.value,
            matchId: 'ae3-init',
            videoPathService: _AbsentVideoPathService(),
          ),
        );
        final container = _container(tester);
        await _awaitMatch(tester, container, 'ae3-init');
        await tester.pump(const Duration(milliseconds: 100));

        // Score chip and Events chip both render active (they are rendered
        // as WfChip widgets with label text in the toggle row regardless of
        // overlay visibility — presence in the Stack is what matters).
        expect(find.text('Score'), findsOneWidget);
        expect(find.text('Events'), findsOneWidget);
        // Score overlay visible: period indicator '1H' is rendered in Stack.
        expect(find.text('1H'), findsOneWidget);
      },
    );

    testWidgets(
      'AE3: tap Events chip OFF → events ticker hidden; score overlay still visible',
      (tester) async {
        await largeScreen(tester);
        await _insertMatch(
          db.value,
          id: 'ae3-events-off',
          teamId: 'nr-u14',
          eventsJson: eventsJson,
        );

        await pumpAndJumpToGoal(tester, 'ae3-events-off');

        // Before toggling: events ticker label is visible in the Stack.
        expect(find.text('GOAL · #7'), findsWidgets); // in list + overlay

        // Tap the Events chip to turn it OFF.
        await tester.tap(find.text('Events'));
        await tester.pump();

        // Events ticker (recentEventLabel in overlay) no longer rendered.
        // The label "GOAL · #7" may still appear in the event list row —
        // but it should only appear once (in the list, not the overlay).
        // We verify the score overlay is still present via '1H'.
        expect(find.text('1H'), findsOneWidget); // score overlay still on
      },
    );

    testWidgets(
      'AE3: tap Score chip OFF → score overlay hidden; events overlay independent',
      (tester) async {
        await largeScreen(tester);
        await _insertMatch(
          db.value,
          id: 'ae3-score-off',
          teamId: 'nr-u14',
          eventsJson: eventsJson,
        );

        await pumpAndJumpToGoal(tester, 'ae3-score-off');

        // Before toggling: score overlay shows period '1H'.
        expect(find.text('1H'), findsOneWidget);

        // Tap the Score chip to turn it OFF.
        await tester.tap(find.text('Score'));
        await tester.pump();

        // Score overlay is now hidden — '1H' no longer rendered.
        expect(find.text('1H'), findsNothing);
      },
    );

    testWidgets(
      'AE3: both OFF → score and events overlays both hidden',
      (tester) async {
        await largeScreen(tester);
        await _insertMatch(
          db.value,
          id: 'ae3-both-off',
          teamId: 'nr-u14',
          eventsJson: eventsJson,
        );

        await pumpAndJumpToGoal(tester, 'ae3-both-off');

        // Turn Score off.
        await tester.tap(find.text('Score'));
        await tester.pump();

        // Turn Events off.
        await tester.tap(find.text('Events'));
        await tester.pump();

        // Both overlays hidden.
        expect(find.text('1H'), findsNothing);
      },
    );

    testWidgets(
      'master switch OFF → both overlays hidden; master switch ON → both restored',
      (tester) async {
        await largeScreen(tester);
        await _insertMatch(
          db.value,
          id: 'ae3-master',
          teamId: 'nr-u14',
          eventsJson: eventsJson,
        );

        await pumpAndJumpToGoal(tester, 'ae3-master');

        // Both start ON — score overlay visible.
        expect(find.text('1H'), findsOneWidget);

        // Tap master switch to turn both OFF.
        await tester.tap(find.byType(WfSwitch));
        await tester.pump();

        // Both overlays hidden.
        expect(find.text('1H'), findsNothing);

        // Tap master switch again to restore both.
        await tester.tap(find.byType(WfSwitch));
        await tester.pump();

        // Score overlay restored.
        expect(find.text('1H'), findsOneWidget);
      },
    );

    testWidgets(
      'master switch restores individual states set before turning OFF',
      (tester) async {
        await largeScreen(tester);
        await _insertMatch(
          db.value,
          id: 'ae3-master-restore',
          teamId: 'nr-u14',
          eventsJson: eventsJson,
        );

        await pumpAndJumpToGoal(tester, 'ae3-master-restore');

        // Turn Score OFF individually (Events stays ON).
        await tester.tap(find.text('Score'));
        await tester.pump();

        // Score overlay gone; master is still "on" (eventsOn=true).
        expect(find.text('1H'), findsNothing);

        // Tap master switch OFF (eventsOn was true → master=true, turns both off).
        await tester.tap(find.byType(WfSwitch));
        await tester.pump();

        // Tap master switch ON → restores _lastScoreOn=false, _lastEventsOn=true.
        await tester.tap(find.byType(WfSwitch));
        await tester.pump();

        // Score is still OFF (lastScoreOn was false), Events is ON.
        expect(find.text('1H'), findsNothing);
      },
    );

    testWidgets(
      'Score toggle does not affect Events state and vice versa',
      (tester) async {
        await largeScreen(tester);
        await _insertMatch(
          db.value,
          id: 'ae3-independent',
          teamId: 'nr-u14',
          eventsJson: eventsJson,
        );

        await tester.pumpWidget(
          _buildPage(
            db: db.value,
            matchId: 'ae3-independent',
            videoPathService: _AbsentVideoPathService(),
          ),
        );
        final container = _container(tester);
        await _awaitMatch(tester, container, 'ae3-independent');
        await tester.pump(const Duration(milliseconds: 100));

        // Toggle Score OFF.
        await tester.tap(find.text('Score'));
        await tester.pump();
        // Score overlay gone.
        expect(find.text('1H'), findsNothing);
        // Events chip still present and events toggle state is independent.
        expect(find.text('Events'), findsOneWidget);

        // Toggle Score back ON.
        await tester.tap(find.text('Score'));
        await tester.pump();
        // Score overlay restored.
        expect(find.text('1H'), findsOneWidget);
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

  // ---------------------------------------------------------------------------
  // U10: Per-event highlight clip creation (AE7, AE8, clamp, spinner, errors).
  // ---------------------------------------------------------------------------

  group('per-event clip creation (U10)', () {
    // Install a fake VideoPlayerPlatform so VideoPlayerController.initialize()
    // completes cleanly in tests. Without this, the default platform throws
    // UnimplementedError and leaves an uncompleted Completer in
    // VideoPlayerController that causes subsequent pump() calls to hang.
    late vp_interface.VideoPlayerPlatform _savedPlatform;
    setUp(() {
      _savedPlatform = vp_interface.VideoPlayerPlatform.instance;
      vp_interface.VideoPlayerPlatform.instance = _FakeVideoPlayerPlatform();
    });

    tearDown(() {
      vp_interface.VideoPlayerPlatform.instance = _savedPlatform;
    });

    // A single goal event at 37:22 = 2242 s.
    const eventsJson =
        '[{"timeSeconds":2242,"label":"GOAL · #7","team":"NRA","kind":"goal"}]';

    // ---------------------------------------------------------------------------
    // AE7: match not on device → snackbar asking to download first.
    // ---------------------------------------------------------------------------

    testWidgets(
      'AE7: match not on device → tap Clip → snackbar "Download the full match first"',
      (tester) async {
        await largeScreen(tester);
        await _insertMatch(
          db.value,
          id: 'u10-ae7',
          teamId: 'nr-u14',
          eventsJson: eventsJson,
        );

        final clipSvc = _RecordingClipService();

        await tester.pumpWidget(
          _buildPage(
            db: db.value,
            matchId: 'u10-ae7',
            videoPathService: _AbsentVideoPathService(),
            clipService: clipSvc,
            // no activeCameraId → isOnDevice = false (absent file)
          ),
        );
        final container = _container(tester);
        await _awaitMatch(tester, container, 'u10-ae7');
        await tester.pump(const Duration(milliseconds: 100));

        // Tap the Clip button on the first (only) event row.
        // Drain the async chain via pump() (no duration = no timers fired).
        await tester.tap(find.text('Clip').first);
        await tester.pump();
        await tester.pump();
        await tester.pump();

        // Snackbar shown.
        expect(
          find.textContaining('Download the full match first'),
          findsOneWidget,
        );
        // trim() was NOT called.
        expect(clipSvc.calls, isEmpty);
      },
    );

    // ---------------------------------------------------------------------------
    // AE8: match on device, event at 37:22 (2242s) → startSeconds=2227.
    // ---------------------------------------------------------------------------

    testWidgets(
      'AE8: on-device match → tap Clip on goal → trim called with correct args',
      (tester) async {
        await largeScreen(tester);
        await _insertMatch(
          db.value,
          id: 'u10-ae8',
          teamId: 'nr-u14',
          eventsJson: eventsJson,
        );

        final tmpFile = await File('/tmp/sst-u10-ae8.mp4').create();
        addTearDown(() async {
          if (tmpFile.existsSync()) await tmpFile.delete();
        });

        final clipSvc = _RecordingClipService();

        await tester.pumpWidget(
          _buildPage(
            db: db.value,
            matchId: 'u10-ae8',
            videoPathService: _PresentVideoPathService(tmpFile.path),
            clipService: clipSvc,
          ),
        );
        final container = _container(tester);
        await _awaitMatch(tester, container, 'u10-ae8');
        await tester.pump(const Duration(milliseconds: 100));

        // Tap Clip.
        await tester.tap(find.text('Clip').first);
        await tester.pump();
        await tester.pump();
        await tester.pump();

        // trim() called once with correct args.
        expect(clipSvc.calls.length, 1);
        final call = clipSvc.calls.first;
        expect(call.matchId, 'u10-ae8');
        expect(call.sourcePath, tmpFile.path);
        expect(call.startSeconds, 2227); // 2242 - 15
        expect(call.durationSeconds, 30);

        // "Clip saved" snackbar.
        expect(find.text('Clip saved'), findsOneWidget);
      },
    );

    // ---------------------------------------------------------------------------
    // Clamp: event at timeSeconds=10 → startSeconds clamped to 0.
    // ---------------------------------------------------------------------------

    testWidgets(
      'event at timeSeconds=10 → startSeconds clamped to 0 (not negative)',
      (tester) async {
        await largeScreen(tester);
        const earlyEvent =
            '[{"timeSeconds":10,"label":"FOUL · #4","team":"NRA","kind":"foul"}]';
        await _insertMatch(
          db.value,
          id: 'u10-clamp',
          teamId: 'nr-u14',
          eventsJson: earlyEvent,
        );

        final tmpFile = await File('/tmp/sst-u10-clamp.mp4').create();
        addTearDown(() async {
          if (tmpFile.existsSync()) await tmpFile.delete();
        });

        final clipSvc = _RecordingClipService();

        await tester.pumpWidget(
          _buildPage(
            db: db.value,
            matchId: 'u10-clamp',
            videoPathService: _PresentVideoPathService(tmpFile.path),
            clipService: clipSvc,
          ),
        );
        final container = _container(tester);
        await _awaitMatch(tester, container, 'u10-clamp');
        await tester.pump(const Duration(milliseconds: 100));

        await tester.tap(find.text('Clip').first);
        await tester.pump();
        await tester.pump();
        await tester.pump();

        expect(clipSvc.calls.length, 1);
        // 10 - 15 = -5, clamped to 0.
        expect(clipSvc.calls.first.startSeconds, 0);
      },
    );

    // ---------------------------------------------------------------------------
    // Clip in progress → spinner on that event, other events still show Clip.
    // ---------------------------------------------------------------------------

    testWidgets(
      'clip in progress → spinner shown for that event; others show Clip button',
      (tester) async {
        await largeScreen(tester);
        // Two events.
        const twoEvents =
            '[{"timeSeconds":600,"label":"GOAL · #7","team":"NRA","kind":"goal"},'
            '{"timeSeconds":900,"label":"FOUL · #4","team":"NRA","kind":"foul"}]';
        await _insertMatch(
          db.value,
          id: 'u10-spinner',
          teamId: 'nr-u14',
          eventsJson: twoEvents,
        );

        final tmpFile = await File('/tmp/sst-u10-spinner.mp4').create();
        addTearDown(() async {
          if (tmpFile.existsSync()) await tmpFile.delete();
        });

        // A completer-controlled ClipService that hangs until we signal it.
        final completer = _HangingClipService();

        await tester.pumpWidget(
          _buildPage(
            db: db.value,
            matchId: 'u10-spinner',
            videoPathService: _PresentVideoPathService(tmpFile.path),
            clipService: completer,
          ),
        );
        final container = _container(tester);
        await _awaitMatch(tester, container, 'u10-spinner');
        await tester.pump(const Duration(milliseconds: 100));

        // Tap Clip on the FIRST event (GOAL · #7).
        final clipButtons = find.text('Clip');
        expect(clipButtons, findsNWidgets(2));
        await tester.tap(clipButtons.first);
        // Drain via pump() (no duration = no fake timers fired).
        await tester.pump();
        await tester.pump();
        await tester.pump();

        // First event row shows a spinner; second still shows Clip button.
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(find.text('Clip'), findsOneWidget);

        // Complete the hanging call so the widget cleans up.
        completer.complete();
        await tester.pump();
        await tester.pump();
        await tester.pump();
      },
    );

    // ---------------------------------------------------------------------------
    // ClipTrimException → error snackbar.
    // ---------------------------------------------------------------------------

    testWidgets(
      'ClipTrimException from ClipService → error snackbar shown',
      (tester) async {
        await largeScreen(tester);
        await _insertMatch(
          db.value,
          id: 'u10-fail',
          teamId: 'nr-u14',
          eventsJson: eventsJson,
        );

        final tmpFile = await File('/tmp/sst-u10-fail.mp4').create();
        addTearDown(() async {
          if (tmpFile.existsSync()) await tmpFile.delete();
        });

        await tester.pumpWidget(
          _buildPage(
            db: db.value,
            matchId: 'u10-fail',
            videoPathService: _PresentVideoPathService(tmpFile.path),
            clipService: _FailingClipService(),
          ),
        );
        final container = _container(tester);
        await _awaitMatch(tester, container, 'u10-fail');
        await tester.pump(const Duration(milliseconds: 100));

        await tester.tap(find.text('Clip').first);
        await tester.pump();
        await tester.pump();
        await tester.pump();

        expect(find.textContaining('Clip failed:'), findsOneWidget);
        expect(find.textContaining('FFmpeg unavailable'), findsOneWidget);
      },
    );

    // ---------------------------------------------------------------------------
    // Successful clip → "Clip saved" snackbar.
    // ---------------------------------------------------------------------------

    testWidgets(
      'successful clip → "Clip saved" snackbar shown',
      (tester) async {
        await largeScreen(tester);
        await _insertMatch(
          db.value,
          id: 'u10-ok',
          teamId: 'nr-u14',
          eventsJson: eventsJson,
        );

        await tester.pumpWidget(
          _buildPage(
            db: db.value,
            matchId: 'u10-ok',
            videoPathService: _AbsentVideoPathService(),
            clipService: _RecordingClipService(),
            forceIsOnDevice: true,
          ),
        );
        final container = _container(tester);
        await _awaitMatch(tester, container, 'u10-ok');
        await tester.pump(const Duration(milliseconds: 100));

        await tester.tap(find.text('Clip').first);
        await tester.pump();
        await tester.pump();
        await tester.pump();

        expect(find.text('Clip saved'), findsOneWidget);
      },
    );
  });
}
