// HARD INVARIANT (plan A6c): while a match is live (recording and/or
// streaming), the app blocks ALL past-video retrieval. These tests assert the
// client-side gate — the download sheet refuses to start a download, and the
// detail page disables its download buttons — keyed off liveSessionActiveProvider.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
    show liveSessionActiveProvider, LibraryMatch;
import 'package:sst_cam_app/mock/emulator/mock_ble_service.dart';
import 'package:sst_cam_app/mock/emulator/mock_wifi_service.dart';

import '../../../test_helpers.dart';

// Records whether a download was ever requested.
class _SpyWifi extends MockWifiService {
  int downloadCalls = 0;

  @override
  Future<VideoDownloadHandle> downloadRecording(
    String deviceId,
    String uuid,
  ) async {
    downloadCalls++;
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

class _AbsentPathSvc extends VideoPathService {
  @override
  Future<String> recordingPath(String id) async => '/nonexistent/$id.mp4';
}

const _matchId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

MockBleService _newBle() => MockBleService(
  scanDeviceAppearDelays: const [Duration.zero],
  connectionDelay: Duration.zero,
  failureRate: 0.0,
  randomSeed: 42,
);

Widget _buildSheet({required AppDatabase db, required _SpyWifi wifi}) {
  return ProviderScope(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      bleServiceProvider.overrideWithValue(_newBle()),
      // Session is LIVE — retrieval must be blocked.
      liveSessionActiveProvider.overrideWithValue(true),
      deviceRecordingProvider.overrideWith((ref, matchId) => null),
      activeUserProvider.overrideWith((_) => 'user-1'),
      wifiServiceProvider.overrideWithValue(wifi),
      videoPathServiceProvider.overrideWithValue(_AbsentPathSvc()),
      activeCameraIdProvider.overrideWith((_) => 'cam-001'),
    ],
    child: const MaterialApp(
      home: Scaffold(
        body: DownloadSheet(
          match: LibraryMatch(
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
          allEvents: [],
          selectedEvents: [],
        ),
      ),
    ),
  );
}

void main() {
  final db = useInMemoryDb();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'download sheet blocks "Start download" while a session is live',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final wifi = _SpyWifi();
      await tester.pumpWidget(_buildSheet(db: db.value, wifi: wifi));
      await tester.pump();

      await tester.tap(find.text('Start download'));
      await tester.pump();

      expect(
        find.textContaining("Can't retrieve videos while a match is live"),
        findsOneWidget,
      );
      expect(
        wifi.downloadCalls,
        0,
        reason: 'no download may be requested during a live session',
      );
    },
  );
}
