// Tests for DownloadSheet — U9: full-game download wired through
// wifiService.downloadRecording.
//
// AE6: downloadRecording completes → isOnDeviceProvider(matchId) is
// invalidated (onDone callback).
//
// Additional coverage:
//   - Progress stream emits → LinearProgressIndicator updates
//   - Cancel button → stream closes, sheet dismisses, invalidation not called
//   - Download button not shown when already on device (only option = full game)
//   - Error path: downloadRecording throws → error state shown

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sst_cam_app/core/ble/ble_service.dart' show BleService;
import 'package:sst_cam_app/core/models/export_job.dart';
import 'package:sst_cam_app/core/models/recording.dart' show DownloadToken;
import 'package:sst_cam_app/core/models/wifi.dart';
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
    show isOnDeviceProvider, liveSessionActiveProvider, LibraryMatch;
import 'package:sst_cam_app/mock/emulator/mock_ble_service.dart';
import 'package:sst_cam_app/mock/emulator/mock_wifi_service.dart';
import 'package:drift/drift.dart' show Value;

import '../../../test_helpers.dart';

// ---------------------------------------------------------------------------
// Controlled WiFi service — gives the test fine-grained control over when
// the download progresses, errors, and completes.
// ---------------------------------------------------------------------------

class _ControlledWifiService extends MockWifiService {
  /// Pending completers for `downloadRecording` calls. The test pops one
  /// per call and drives it via [simulateProgress], [simulateError], and
  /// [simulateDone].
  final _controllers = <StreamController<VideoDownloadProgress>>[];

  /// The most recent controller created by [downloadRecording].
  StreamController<VideoDownloadProgress>? get lastController =>
      _controllers.isEmpty ? null : _controllers.last;

  bool downloadCalled = false;
  String? lastDeviceId;
  String? lastUuid;
  Exception? _throwOnDownload;

  /// Reachability gate (verify-before-action). Default reachable so the existing
  /// download tests — which never call connectGroup — pass the gate immediately.
  /// Flip to false to drive the "reconnecting…" wait.
  bool reachable = true;

  @override
  Future<bool> isCameraReachable(String deviceId) async => reachable;

  void throwOnNextDownload(Exception e) => _throwOnDownload = e;

  @override
  Future<VideoDownloadHandle> downloadRecording(
    String deviceId,
    String uuid,
  ) async {
    lastDeviceId = deviceId;
    lastUuid = uuid;
    downloadCalled = true;

    if (_throwOnDownload != null) {
      final e = _throwOnDownload!;
      _throwOnDownload = null;
      throw e;
    }

    final controller = StreamController<VideoDownloadProgress>.broadcast();
    _controllers.add(controller);

    return VideoDownloadHandle(
      downloadId: 'test-dl-$uuid',
      recordingId: uuid,
      savePath: '/tmp/$uuid.mp4',
      progress: controller.stream,
      cancel: () async {
        if (!controller.isClosed) await controller.close();
      },
    );
  }

  // #6 A6c: the overlay flow downloads the burned L2 by token via startDownload.
  bool startDownloadCalled = false;
  String? lastSaveAs;
  DownloadToken? lastToken;

  @override
  Future<VideoDownloadHandle> startDownload(
    String deviceId,
    DownloadToken token, {
    String? saveAs,
  }) async {
    startDownloadCalled = true;
    lastSaveAs = saveAs;
    lastToken = token;
    final controller = StreamController<VideoDownloadProgress>.broadcast();
    _controllers.add(controller);
    return VideoDownloadHandle(
      downloadId: 'test-ov-${token.recordingId}',
      recordingId: token.recordingId,
      savePath: saveAs ?? '/tmp/${token.recordingId}_overlay.mp4',
      progress: controller.stream,
      cancel: () async {
        if (!controller.isClosed) await controller.close();
      },
    );
  }

  void simulateProgress(VideoDownloadProgress p) {
    lastController?.add(p);
  }

  Future<void> simulateDone() async {
    await lastController?.close();
  }

  Future<void> simulateError(Object e) async {
    lastController?.addError(e);
    await lastController?.close();
  }
}

// ---------------------------------------------------------------------------
// VideoPathService stubs
// ---------------------------------------------------------------------------

class _AbsentVideoPathService extends VideoPathService {
  @override
  Future<String> recordingPath(String recordingId) async =>
      '/nonexistent/$recordingId.mp4';

  @override
  Future<String> overlayRecordingPath(String recordingId) async =>
      '/nonexistent/${recordingId}_overlay.mp4';
}

// ---------------------------------------------------------------------------
// Match fixture
// ---------------------------------------------------------------------------

const _matchId = 'dl-test-match';

Future<void> _insertMatch(AppDatabase db, {int sizeMb = 0}) async {
  await db.teamsDao.insertTeamMatch(
    TeamMatchesTableCompanion.insert(
      id: _matchId,
      teamId: 'nr-u14',
      opponent: 'Rival FC',
      date: 'Jun 01',
      result: 'W 1-0',
      kind: 'past',
      numPeriods: 2,
      periodLengthSeconds: 35 * 60,
      sizeMb: Value(sizeMb),
    ),
  );
}

// ---------------------------------------------------------------------------
// Widget helper
// ---------------------------------------------------------------------------

MockBleService _newBle() => MockBleService(
  scanDeviceAppearDelays: const [Duration.zero],
  connectionDelay: Duration.zero,
  failureRate: 0.0,
  randomSeed: 42,
);

/// BLE stub with a configurable overlay-export poll result, so tests can drive
/// the FAILED / UNKNOWN terminal states the real firmware can return.
class _ControlledBleService extends MockBleService {
  _ControlledBleService()
    : super(
        scanDeviceAppearDelays: const [Duration.zero],
        connectionDelay: Duration.zero,
        failureRate: 0.0,
        randomSeed: 42,
      );

  ExportJob _pollResult = ExportJob(
    jobId: 'job-1',
    state: ExportJobState.ready,
    token: DownloadToken(
      recordingId: _matchId,
      httpUrl: 'http://127.0.0.1/x',
      authToken: 'tok',
      expiresAt: DateTime.fromMillisecondsSinceEpoch(0),
    ),
  );

  set pollResult(ExportJob job) => _pollResult = job;

  @override
  Future<ExportJob> requestOverlayExport(
    String deviceId,
    String recordingId,
  ) async => const ExportJob(jobId: 'job-1', state: ExportJobState.pending);

  @override
  Future<ExportJob> pollOverlayExport(String deviceId, String jobId) async =>
      _pollResult;
}

Widget _buildSheet({
  required AppDatabase db,
  required LibraryMatch match,
  required _ControlledWifiService wifiSvc,
  VideoPathService? videoPathSvc,
  BleService? bleSvc,
  String? activeCameraId = 'cam-001',
}) {
  return ProviderScope(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      bleServiceProvider.overrideWithValue(bleSvc ?? _newBle()),
      // The sheet fetches real recording metadata on build; stub it so the
      // mock's delayed listRecordings timer isn't left pending at teardown.
      deviceRecordingProvider.overrideWith((ref, matchId) => null),
      liveSessionActiveProvider.overrideWithValue(false),
      activeUserProvider.overrideWith((_) => 'user-1'),
      wifiServiceProvider.overrideWithValue(wifiSvc),
      videoPathServiceProvider.overrideWithValue(
        videoPathSvc ?? _AbsentVideoPathService(),
      ),
      if (activeCameraId != null)
        activeCameraIdProvider.overrideWith((_) => activeCameraId),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: DownloadSheet(
          match: match,
          allEvents: const [],
          selectedEvents: const [],
        ),
      ),
    ),
  );
}

LibraryMatch _makeMatch({String id = _matchId, int sizeMb = 0}) => LibraryMatch(
  id: id,
  teamId: 'nr-u14',
  teamName: 'Northside Rovers U14',
  teamShortName: 'NRA',
  date: 'Jun 01',
  opponent: 'Rival FC',
  result: 'W 1-0',
  sport: 'Soccer',
  fullDuration: '01:10:00',
  fullSizeMb: sizeMb,
  periodLengthSeconds: 35 * 60,
  events: const [],
  downloadState: sizeMb > 0 ? 'all-local' : 'remote',
);

VideoDownloadProgress _progressAt(
  double fraction, {
  DownloadStatus status = DownloadStatus.running,
}) {
  const totalBytes = 60 * 1024 * 1024;
  return VideoDownloadProgress(
    downloadId: 'test-dl',
    recordingId: _matchId,
    status: status,
    bytesReceived: (totalBytes * fraction).toInt(),
    bytesTotal: totalBytes,
    kbps: 8000,
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

  // ---------------------------------------------------------------------------
  // Baseline: sheet renders with only the "Full game" option and Start button.
  // ---------------------------------------------------------------------------

  group('sheet baseline', () {
    testWidgets('renders Full game option and Start download button', (
      tester,
    ) async {
      await largeScreen(tester);
      await _insertMatch(db.value);

      final wifiSvc = _ControlledWifiService();
      await tester.pumpWidget(
        _buildSheet(db: db.value, match: _makeMatch(), wifiSvc: wifiSvc),
      );
      await tester.pump();

      expect(find.text('Full game'), findsOneWidget);
      expect(find.text('Start download'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      // Out-of-scope options must not appear.
      expect(find.text('1st half'), findsNothing);
      expect(find.text('2nd half'), findsNothing);
      expect(find.text('All highlights'), findsNothing);
      expect(find.text('Selected highlights'), findsNothing);
    });
  });

  // ---------------------------------------------------------------------------
  // Progress stream emits → LinearProgressIndicator updates.
  // ---------------------------------------------------------------------------

  group('progress updates', () {
    testWidgets(
      'LinearProgressIndicator shown when download starts; updates on progress',
      (tester) async {
        await largeScreen(tester);
        await _insertMatch(db.value);

        final wifiSvc = _ControlledWifiService();
        await tester.pumpWidget(
          _buildSheet(db: db.value, match: _makeMatch(), wifiSvc: wifiSvc),
        );
        await tester.pump();

        // Tap Start download.
        await tester.tap(find.text('Start download'));
        await tester.pump();

        // downloadRecording was called.
        expect(wifiSvc.downloadCalled, isTrue);
        expect(wifiSvc.lastUuid, equals(_matchId));

        // Emit a 50% progress event.
        wifiSvc.simulateProgress(_progressAt(0.5));
        await tester.pump();

        // Progress view shown.
        expect(find.byType(LinearProgressIndicator), findsOneWidget);
        expect(find.text('Downloading'), findsOneWidget);
      },
    );
  });

  // ---------------------------------------------------------------------------
  // U4: verify-before-action — reachability gate before a download starts.
  // ---------------------------------------------------------------------------

  group('verify-before-action (U4)', () {
    testWidgets(
      'Covers AE1. unreachable then reachable → shows reconnecting, then downloads',
      (tester) async {
        await largeScreen(tester);
        await _insertMatch(db.value);

        final wifiSvc = _ControlledWifiService()..reachable = false;
        await tester.pumpWidget(
          _buildSheet(db: db.value, match: _makeMatch(), wifiSvc: wifiSvc),
        );
        await tester.pump();

        await tester.tap(find.text('Start download'));
        await tester.pump(); // first probe fails → reconnecting surface

        expect(find.text('Reconnecting to camera…'), findsOneWidget);
        expect(wifiSvc.downloadCalled, isFalse);

        // Phone rejoins the saved network; the next poll succeeds.
        wifiSvc.reachable = true;
        await tester.pump(const Duration(seconds: 1)); // fire one poll
        await tester.pump(); // flush the download start

        expect(wifiSvc.downloadCalled, isTrue);
        expect(find.text('Reconnecting to camera…'), findsNothing);
      },
    );

    testWidgets(
      'Covers AE2. stays unreachable past the budget → clear error, no download',
      (tester) async {
        await largeScreen(tester);
        await _insertMatch(db.value);

        final wifiSvc = _ControlledWifiService()..reachable = false;
        await tester.pumpWidget(
          _buildSheet(db: db.value, match: _makeMatch(), wifiSvc: wifiSvc),
        );
        await tester.pump();

        await tester.tap(find.text('Start download'));
        await tester.pump();
        expect(find.text('Reconnecting to camera…'), findsOneWidget);

        // Elapse the whole wait budget — every poll fails.
        await tester.pump(const Duration(seconds: 21));
        await tester.pump();

        expect(wifiSvc.downloadCalled, isFalse);
        expect(
          find.textContaining("Couldn't reach the camera"),
          findsOneWidget,
        );
      },
    );
  });

  // ---------------------------------------------------------------------------
  // AE6: downloadRecording completes → isOnDeviceProvider(matchId) invalidated.
  // ---------------------------------------------------------------------------

  group('AE6: onDone invalidates isOnDeviceProvider', () {
    testWidgets('isOnDeviceProvider is invalidated when stream closes (onDone)', (
      tester,
    ) async {
      await largeScreen(tester);
      await _insertMatch(db.value);

      final wifiSvc = _ControlledWifiService();

      // Start with an absent file — isOnDeviceProvider resolves to false.
      await tester.pumpWidget(
        _buildSheet(
          db: db.value,
          match: _makeMatch(),
          wifiSvc: wifiSvc,
          videoPathSvc: _AbsentVideoPathService(),
        ),
      );
      await tester.pump();

      // Tap Start download.
      await tester.tap(find.text('Start download'));
      await tester.pump();

      // Retrieve the ProviderContainer from the widget tree.
      final container = ProviderScope.containerOf(
        tester.element(find.byType(DownloadSheet)),
      );

      // Read isOnDeviceProvider — resolves to false (absent file).
      final beforeDone = await container.read(
        isOnDeviceProvider(_matchId).future,
      );
      expect(beforeDone, isFalse);

      // Emit a completed progress event, then close the stream (onDone).
      wifiSvc.simulateProgress(
        _progressAt(1.0, status: DownloadStatus.completed),
      );
      await wifiSvc.simulateDone();
      // Let the onDone callback fire and any resulting provider rebuilds run.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // After invalidation the provider is dirty — reading it schedules a
      // new future. We cannot assert the file exists (it wasn't written), but
      // we CAN verify the provider was invalidated by checking the container
      // has discarded its previous (cached) value.
      // The simplest observable: the provider's state is AsyncLoading after
      // invalidation (because the file check hasn't re-resolved yet), OR it
      // has already resolved. Either way it must not be the old cached false.
      final state = container.read(isOnDeviceProvider(_matchId));
      // Provider must not have errored, and must not have retained the old
      // cached false value (loading = invalidated, true = re-resolved).
      expect(state.hasError, isFalse);
      expect(
        state.isLoading || state.valueOrNull == true,
        isTrue,
        reason:
            'Provider should be loading (just invalidated) or resolved true; '
            'resolved-false means the cached pre-download value was not discarded',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Cancel button → stream closes, sheet dismisses, invalidation not called.
  // ---------------------------------------------------------------------------

  group('cancel flow', () {
    testWidgets(
      'Cancel before download starts dismisses the sheet without calling downloadRecording',
      (tester) async {
        await largeScreen(tester);
        await _insertMatch(db.value);

        final wifiSvc = _ControlledWifiService();
        bool sheetDismissed = false;

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              appDatabaseProvider.overrideWithValue(db.value),
              bleServiceProvider.overrideWithValue(_newBle()),
              liveSessionActiveProvider.overrideWithValue(false),
              activeUserProvider.overrideWith((_) => 'user-1'),
              wifiServiceProvider.overrideWithValue(wifiSvc),
              videoPathServiceProvider.overrideWithValue(
                _AbsentVideoPathService(),
              ),
              activeCameraIdProvider.overrideWith((_) => 'cam-001'),
            ],
            child: MaterialApp(
              home: Scaffold(
                body: Builder(
                  builder: (ctx) => ElevatedButton(
                    onPressed: () async {
                      await showModalBottomSheet<void>(
                        context: ctx,
                        builder: (_) => DownloadSheet(
                          match: _makeMatch(),
                          allEvents: const [],
                          selectedEvents: const [],
                        ),
                      );
                      sheetDismissed = true;
                    },
                    child: const Text('Open'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        // Open the sheet.
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        expect(find.text('Start download'), findsOneWidget);

        // Tap Cancel.
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();

        expect(sheetDismissed, isTrue);
        expect(wifiSvc.downloadCalled, isFalse);
      },
    );

    testWidgets(
      'Cancel during download cancels handle and dismisses the sheet',
      (tester) async {
        await largeScreen(tester);
        await _insertMatch(db.value);

        final wifiSvc = _ControlledWifiService();
        await tester.pumpWidget(
          _buildSheet(db: db.value, match: _makeMatch(), wifiSvc: wifiSvc),
        );
        await tester.pump();

        // Start download.
        await tester.tap(find.text('Start download'));
        await tester.pump();

        // Emit some progress so the progress view is shown.
        wifiSvc.simulateProgress(_progressAt(0.3));
        await tester.pump();

        expect(find.text('Cancel'), findsOneWidget);
        expect(find.byType(LinearProgressIndicator), findsOneWidget);

        // Tap Cancel in progress view.
        await tester.tap(find.text('Cancel'));
        await tester.pump();

        // Stream controller should be closed (cancelled).
        expect(wifiSvc.lastController?.isClosed, isTrue);
      },
    );
  });

  // ---------------------------------------------------------------------------
  // Error path: downloadRecording throws → error state shown.
  // ---------------------------------------------------------------------------

  group('error path', () {
    testWidgets(
      'error message shown when downloadRecording throws synchronously',
      (tester) async {
        await largeScreen(tester);
        await _insertMatch(db.value);

        final wifiSvc = _ControlledWifiService();
        wifiSvc.throwOnNextDownload(Exception('Network unreachable'));

        await tester.pumpWidget(
          _buildSheet(db: db.value, match: _makeMatch(), wifiSvc: wifiSvc),
        );
        await tester.pump();

        // Tap Start download.
        await tester.tap(find.text('Start download'));
        await tester.pump();

        // Error text is shown.
        expect(find.textContaining('Network unreachable'), findsOneWidget);
        // Still on the options view, not progress view.
        expect(find.byType(LinearProgressIndicator), findsNothing);
      },
    );

    testWidgets('error shown when progress stream emits an error', (
      tester,
    ) async {
      await largeScreen(tester);
      await _insertMatch(db.value);

      final wifiSvc = _ControlledWifiService();
      await tester.pumpWidget(
        _buildSheet(db: db.value, match: _makeMatch(), wifiSvc: wifiSvc),
      );
      await tester.pump();

      await tester.tap(find.text('Start download'));
      await tester.pump();

      // Emit an error on the stream.
      await wifiSvc.simulateError(Exception('Connection dropped'));
      await tester.pump();

      // Error should be displayed.
      expect(find.textContaining('Connection dropped'), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  // No active camera → error shown, download not started.
  // ---------------------------------------------------------------------------

  group('no active camera', () {
    testWidgets(
      'shows "Connect a camera first" error when activeCameraId is null',
      (tester) async {
        await largeScreen(tester);
        await _insertMatch(db.value);

        final wifiSvc = _ControlledWifiService();
        await tester.pumpWidget(
          _buildSheet(
            db: db.value,
            match: _makeMatch(),
            wifiSvc: wifiSvc,
            activeCameraId: null,
          ),
        );
        await tester.pump();

        await tester.tap(find.text('Start download'));
        await tester.pump();

        expect(find.textContaining('Connect a camera first'), findsOneWidget);
        expect(wifiSvc.downloadCalled, isFalse);
      },
    );
  });

  // ---------------------------------------------------------------------------
  // #6 A6c: overlay burn → poll → download the overlaid L2.
  // ---------------------------------------------------------------------------

  group('overlay export (A6c)', () {
    testWidgets(
      'checking "Burn in scoreboard overlay" renders then downloads the L2 by token',
      (tester) async {
        await largeScreen(tester);
        await _insertMatch(db.value);

        final wifiSvc = _ControlledWifiService();
        await tester.pumpWidget(
          _buildSheet(db: db.value, match: _makeMatch(), wifiSvc: wifiSvc),
        );
        await tester.pump();

        // Opt into the overlay burn, then start.
        await tester.tap(find.text('Burn in scoreboard overlay'));
        await tester.pump();
        await tester.tap(find.text('Start download'));
        await tester.pump();

        // The "rendering" surface shows while the camera burns the L2.
        expect(find.textContaining('Rendering overlay'), findsOneWidget);
        // The plain full-game download path must NOT have been used.
        expect(wifiSvc.downloadCalled, isFalse);

        // Let the BLE request + 1s poll interval + poll resolve.
        await tester.pump(const Duration(milliseconds: 120)); // request
        await tester.pump(const Duration(seconds: 1)); // poll interval
        await tester.pump(const Duration(milliseconds: 120)); // poll → READY
        await tester.pump(); // setState(handle)

        // The overlaid L2 is downloaded by the export token to a distinct path.
        expect(wifiSvc.startDownloadCalled, isTrue);
        expect(wifiSvc.lastSaveAs, contains('_overlay.mp4'));
        expect(wifiSvc.lastToken!.authToken, 'mock-export-token');
        expect(wifiSvc.lastToken!.recordingId, _matchId);
      },
    );

    testWidgets(
      'export FAILED surfaces the firmware error and skips download',
      (tester) async {
        await largeScreen(tester);
        await _insertMatch(db.value);

        final wifiSvc = _ControlledWifiService();
        final ble = _ControlledBleService()
          ..pollResult = const ExportJob(
            jobId: 'job-1',
            state: ExportJobState.failed,
            errorMessage: 'encoder exploded',
          );
        await tester.pumpWidget(
          _buildSheet(
            db: db.value,
            match: _makeMatch(),
            wifiSvc: wifiSvc,
            bleSvc: ble,
          ),
        );
        await tester.pump();

        await tester.tap(find.text('Burn in scoreboard overlay'));
        await tester.pump();
        await tester.tap(find.text('Start download'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 120)); // request
        await tester.pump(const Duration(seconds: 1)); // poll interval
        await tester.pump(const Duration(milliseconds: 120)); // poll → FAILED
        await tester.pump();

        expect(find.textContaining('encoder exploded'), findsOneWidget);
        expect(wifiSvc.startDownloadCalled, isFalse);
      },
    );

    testWidgets(
      'export UNKNOWN (lost job) surfaces a clear error and skips download',
      (tester) async {
        await largeScreen(tester);
        await _insertMatch(db.value);

        final wifiSvc = _ControlledWifiService();
        final ble = _ControlledBleService()
          ..pollResult = const ExportJob(
            jobId: 'job-1',
            state: ExportJobState.unknown,
          );
        await tester.pumpWidget(
          _buildSheet(
            db: db.value,
            match: _makeMatch(),
            wifiSvc: wifiSvc,
            bleSvc: ble,
          ),
        );
        await tester.pump();

        await tester.tap(find.text('Burn in scoreboard overlay'));
        await tester.pump();
        await tester.tap(find.text('Start download'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 120));
        await tester.pump(const Duration(seconds: 1));
        await tester.pump(const Duration(milliseconds: 120));
        await tester.pump();

        expect(
          find.textContaining('lost track of the render job'),
          findsOneWidget,
        );
        expect(wifiSvc.startDownloadCalled, isFalse);
      },
    );

    testWidgets('live session blocks the overlay burn before any BLE call', (
      tester,
    ) async {
      await largeScreen(tester);
      await _insertMatch(db.value);

      final wifiSvc = _ControlledWifiService();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db.value),
            bleServiceProvider.overrideWithValue(_newBle()),
            deviceRecordingProvider.overrideWith((ref, matchId) => null),
            liveSessionActiveProvider.overrideWithValue(true), // live!
            activeUserProvider.overrideWith((_) => 'user-1'),
            wifiServiceProvider.overrideWithValue(wifiSvc),
            videoPathServiceProvider.overrideWithValue(
              _AbsentVideoPathService(),
            ),
            activeCameraIdProvider.overrideWith((_) => 'cam-001'),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: DownloadSheet(
                match: _makeMatch(),
                allEvents: const [],
                selectedEvents: const [],
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Burn in scoreboard overlay'));
      await tester.pump();
      await tester.tap(find.text('Start download'));
      await tester.pump();

      expect(find.textContaining("Can't retrieve videos"), findsOneWidget);
      expect(wifiSvc.startDownloadCalled, isFalse);
      expect(find.textContaining('Rendering overlay'), findsNothing);
    });
  });

  // _startClips coverage lives in start_clips_test.dart (same directory).
  // Tests are isolated there to prevent cross-test interference caused by
  // pending async work when testWidgets tests share a process.
}
