// Tests for DownloadSheet._startClips — isolated from the main download-sheet
// test suite to avoid cross-test interference caused by pending async work
// when multiple testWidgets tests share a process.
//
// Coverage:
//   - "All highlights" with events → clipSvc.trim called once per event
//   - "All highlights" with empty allEvents → option hidden in UI (UI guard)
//   - "All highlights" when video not on device → "Download the full game first"
//   - ClipTrimException thrown by clipSvc.trim → error text shown

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sst_cam_app/core/models/wifi.dart';
import 'package:sst_cam_app/core/services/clip_service.dart';
import 'package:sst_cam_app/core/services/video_path_service.dart';
import 'package:sst_cam_app/core/state/db_providers.dart';
import 'package:sst_cam_app/core/wifi/wifi_providers.dart';
import 'package:sst_cam_app/core/ble/ble_providers.dart';
import 'package:sst_cam_app/features/camera/camera_state.dart'
    show activeCameraIdProvider;
import 'package:sst_cam_app/features/settings/users/users_state.dart'
    show activeUserProvider;
import 'package:sst_cam_app/features/video/playback/download_sheet.dart';
import 'package:sst_cam_app/features/video/video_state.dart'
    show isOnDeviceProvider, LibraryEvent, LibraryMatch;
import 'package:sst_cam_app/mock/emulator/mock_ble_service.dart';
import 'package:sst_cam_app/mock/emulator/mock_wifi_service.dart';
import 'package:drift/drift.dart' show Value;

import '../../../test_helpers.dart';

// ---------------------------------------------------------------------------
// Stubs
// ---------------------------------------------------------------------------

class _FakeWifi extends MockWifiService {
  @override
  Future<VideoDownloadHandle> downloadRecording(
    String deviceId,
    String uuid,
  ) async {
    final c = StreamController<VideoDownloadProgress>.broadcast();
    return VideoDownloadHandle(
      downloadId: 'dl-$uuid',
      recordingId: uuid,
      savePath: '/tmp/$uuid.mp4',
      progress: c.stream,
      cancel: () async => c.close(),
    );
  }
}

class _FakeClipSvc extends ClipService {
  _FakeClipSvc(AppDatabase db)
    : super(clipsDao: db.clipsDao, videoPathService: VideoPathService());

  final List<Map<String, Object?>> calls = [];
  Exception? _throwNext;

  void throwOnNextTrim(Exception e) => _throwNext = e;

  @override
  Future<String> trim({
    required String matchId,
    required String sourcePath,
    required int startSeconds,
    required int durationSeconds,
    String? label,
  }) async {
    calls.add({
      'matchId': matchId,
      'sourcePath': sourcePath,
      'startSeconds': startSeconds,
      'durationSeconds': durationSeconds,
      'label': label,
    });
    if (_throwNext != null) {
      final e = _throwNext!;
      _throwNext = null;
      throw e;
    }
    return '/tmp/clip-$matchId.mp4';
  }
}

class _AbsentPathSvc extends VideoPathService {
  @override
  Future<String> recordingPath(String id) async => '/nonexistent/$id.mp4';
}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const _matchId = 'sc-match';

Future<void> _insertMatch(AppDatabase db) async {
  await db.teamsDao.insertTeamMatch(
    TeamMatchesTableCompanion.insert(
      id: _matchId,
      teamId: 'nr-u14',
      opponent: 'Opp',
      date: 'Jan 1',
      result: 'W 1-0',
      kind: 'past',
      numPeriods: 2,
      periodLengthSeconds: 2100,
      sizeMb: const Value(100),
    ),
  );
}

Widget _buildSheet({
  required AppDatabase db,
  required _FakeClipSvc clipSvc,
  required List<LibraryEvent> allEvents,
  required bool isOnDevice,
}) {
  return ProviderScope(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      bleServiceProvider.overrideWithValue(
        MockBleService(
          scanDeviceAppearDelays: const [Duration.zero],
          connectionDelay: Duration.zero,
          failureRate: 0.0,
          randomSeed: 42,
        ),
      ),
      // The sheet fetches real recording metadata on build; stub it so the
      // mock's delayed listRecordings timer isn't left pending at teardown.
      deviceRecordingProvider.overrideWith((ref, matchId) => null),
      activeUserProvider.overrideWith((_) => 'user-1'),
      wifiServiceProvider.overrideWithValue(_FakeWifi()),
      videoPathServiceProvider.overrideWithValue(_AbsentPathSvc()),
      clipServiceProvider.overrideWithValue(clipSvc),
      activeCameraIdProvider.overrideWith((_) => 'cam-001'),
      // Override isOnDeviceProvider so _startClips finds a quickly-resolved
      // Future instead of going through the full async FutureProvider chain.
      isOnDeviceProvider.overrideWith(
        (ref, id) => Future<bool>.value(isOnDevice),
      ),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: DownloadSheet(
          match: const LibraryMatch(
            id: _matchId,
            teamId: 'nr-u14',
            teamName: 'Northside Rovers U14',
            teamShortName: 'NRA',
            date: 'Jan 1',
            opponent: 'Opp',
            result: 'W 1-0',
            sport: 'Soccer',
            fullDuration: '01:10:00',
            fullSizeMb: 100,
            periodLengthSeconds: 2100,
            events: [],
            downloadState: 'all-local',
          ),
          allEvents: allEvents,
          selectedEvents: const [],
        ),
      ),
    ),
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

  Future<void> largeScreen(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  group('_startClips', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('sc_test_');
      await _insertMatch(db.value);
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    testWidgets(
      '"All highlights" with events calls clipSvc.trim for each event',
      (tester) async {
        await largeScreen(tester);

        const events = [
          LibraryEvent(
            timeSeconds: 60,
            label: 'Goal',
            team: 'NRA',
            kind: 'goal',
          ),
          LibraryEvent(
            timeSeconds: 120,
            label: 'Foul',
            team: 'OPP',
            kind: 'foul',
          ),
        ];

        final clipSvc = _FakeClipSvc(db.value);

        await tester.pumpWidget(
          _buildSheet(
            db: db.value,
            clipSvc: clipSvc,
            allEvents: events,
            isOnDevice: true,
          ),
        );
        await tester.pump();

        await tester.tap(find.text('All highlights'));
        await tester.pump();

        await tester.tap(find.text('Start download'));
        await tester.pump();
        await tester.pump();

        expect(
          clipSvc.calls.length,
          2,
          reason: 'trim should be called once per event',
        );
        expect(clipSvc.calls[0]['label'], 'Goal');
        expect(clipSvc.calls[1]['label'], 'Foul');
      },
    );

    testWidgets(
      '"All highlights" with empty allEvents option is hidden in UI',
      (tester) async {
        await largeScreen(tester);

        final clipSvc = _FakeClipSvc(db.value);

        await tester.pumpWidget(
          _buildSheet(
            db: db.value,
            clipSvc: clipSvc,
            allEvents: const [], // empty → option must not appear
            isOnDevice: true,
          ),
        );
        await tester.pump();

        // "All highlights" option must not appear when allEvents is empty.
        expect(find.text('All highlights'), findsNothing);
      },
    );

    testWidgets(
      '"All highlights" when not on device shows "Download the full game first"',
      (tester) async {
        await largeScreen(tester);

        const events = [
          LibraryEvent(
            timeSeconds: 60,
            label: 'Goal',
            team: 'NRA',
            kind: 'goal',
          ),
        ];

        final clipSvc = _FakeClipSvc(db.value);

        await tester.pumpWidget(
          _buildSheet(
            db: db.value,
            clipSvc: clipSvc,
            allEvents: events,
            isOnDevice: false, // not on device
          ),
        );
        await tester.pump();

        await tester.tap(find.text('All highlights'));
        await tester.pump();

        await tester.tap(find.text('Start download'));
        await tester.pump();
        await tester.pump();

        expect(
          find.textContaining('Download the full game first'),
          findsOneWidget,
        );
        expect(clipSvc.calls, isEmpty);
      },
    );

    testWidgets('ClipTrimException surfaces as error text', (tester) async {
      await largeScreen(tester);

      const events = [
        LibraryEvent(timeSeconds: 60, label: 'Goal', team: 'NRA', kind: 'goal'),
      ];

      final clipSvc = _FakeClipSvc(db.value);
      clipSvc.throwOnNextTrim(const ClipTrimException('FFmpeg failed'));

      await tester.pumpWidget(
        _buildSheet(
          db: db.value,
          clipSvc: clipSvc,
          allEvents: events,
          isOnDevice: true,
        ),
      );
      await tester.pump();

      await tester.tap(find.text('All highlights'));
      await tester.pump();

      await tester.tap(find.text('Start download'));
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('Clip failed'), findsOneWidget);
      expect(find.textContaining('FFmpeg failed'), findsOneWidget);
    });
  });
}
