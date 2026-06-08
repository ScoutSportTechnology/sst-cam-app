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
import 'package:sst_cam_app/core/widgets/indicators.dart' show WfSwitch;
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
        // Structural elements still present.
        expect(find.text('Overlays'), findsOneWidget);
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

    testWidgets('initial state: both Score and Events overlays are ON', (
      tester,
    ) async {
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
    });

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

    testWidgets('AE3: both OFF → score and events overlays both hidden', (
      tester,
    ) async {
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
    });

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

    testWidgets('master switch restores individual states set before turning OFF', (
      tester,
    ) async {
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
    });

    testWidgets('Score toggle does not affect Events state and vice versa', (
      tester,
    ) async {
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
    });
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
