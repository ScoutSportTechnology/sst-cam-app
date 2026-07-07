// U3 — health gating UX across every capture surface (AE5).
//
// The main page, session screen and setup screen all gate off the ONE
// provider pair (deviceHealthProvider / captureBlockedProvider) and share the
// ONE notice widget — these tests pin that wiring:
//   - inoperable → persistent "Device inoperable" banner, preview / record /
//     stream / start-match disabled; navigation and downloads stay enabled
//   - recovering → soft note, nothing locked, no banner
//   - both OK    → no banner, everything enabled
//   - the banner is dismiss-proof while the condition holds and clears itself
//     when health recovers
//
// The provider's fold/freshness logic itself is covered in
// test/core/state/device_health_test.dart; here the health state is pinned
// via a ProviderScope override (the standard test seam).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sst_cam_app/core/ble/ble_providers.dart';
import 'package:sst_cam_app/core/models/device.dart';
import 'package:sst_cam_app/core/models/telemetry.dart';
import 'package:sst_cam_app/core/models/wifi.dart';
import 'package:sst_cam_app/core/services/video_path_service.dart';
import 'package:sst_cam_app/core/state/db_providers.dart';
import 'package:sst_cam_app/core/state/device_health.dart';
import 'package:sst_cam_app/core/widgets/wf_button.dart';
import 'package:sst_cam_app/core/wifi/wifi_providers.dart';
import 'package:sst_cam_app/features/camera/camera_state.dart'
    show activeCameraIdProvider;
import 'package:sst_cam_app/features/camera/main_page.dart';
import 'package:sst_cam_app/features/match/match_page.dart';
import 'package:sst_cam_app/features/settings/users/users_state.dart'
    show activeUserProvider;
import 'package:sst_cam_app/features/video/playback/download_sheet.dart';
import 'package:sst_cam_app/features/video/video_state.dart'
    show liveSessionActiveProvider, LibraryMatch;
import 'package:sst_cam_app/mock/emulator/mock_ble_service.dart';
import 'package:sst_cam_app/mock/emulator/mock_wifi_service.dart';

import '../../test_helpers.dart';

const _kDeviceId = 'SST-CAM-001';

const _ok = DeviceHealthState(
  camera0: CameraHealth.ok,
  camera1: CameraHealth.ok,
);
const _down = DeviceHealthState(
  camera0: CameraHealth.down,
  camera1: CameraHealth.ok,
);
const _recovering = DeviceHealthState(
  camera0: CameraHealth.ok,
  camera1: CameraHealth.recovering,
);

/// Pinned-health controller: replaces the derived notifier so surface tests
/// control the exact health state (and can flip it mid-test).
class _TestHealth extends DeviceHealthController {
  _TestHealth([this._value = _ok]);
  DeviceHealthState _value;

  @override
  DeviceHealthState build() => _value;

  void set(DeviceHealthState v) {
    _value = v;
    state = v;
  }
}

MockBleService _newMock() => MockBleService(
  scanDeviceAppearDelays: const [Duration.zero],
  connectionDelay: Duration.zero,
  failureRate: 0.0,
  randomSeed: 1,
);

List<Override> _connectedOverrides(MockBleService mock, _TestHealth health) => [
  bleServiceProvider.overrideWithValue(mock),
  wifiServiceProvider.overrideWithValue(MockWifiService()),
  activeCameraIdProvider.overrideWith((_) => _kDeviceId),
  connectionStateProvider(_kDeviceId).overrideWith(
    (_) => Stream<CameraConnectionState>.value(CameraConnectionState.connected),
  ),
  deviceHealthProvider.overrideWith(() => health),
  activeUserProvider.overrideWith((_) => 'user-1'),
];

WfButton _button(WidgetTester tester, String label) => tester.widget<WfButton>(
  find.byWidgetPredicate((w) => w is WfButton && w.label == label),
);

void main() {
  final db = useInMemoryDb();

  setUp(() {
    SharedPreferences.setMockInitialValues({'active_user_id': 'user-1'});
  });

  // ---------------------------------------------------------------------
  // Main page
  // ---------------------------------------------------------------------

  Future<void> pumpMainPage(WidgetTester tester, _TestHealth health) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final mock = _newMock();
    addTearDown(mock.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [...dbOverrides(db), ..._connectedOverrides(mock, health)],
        child: const MaterialApp(home: MainPage()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('main page — inoperable: banner shown, Preview disabled, '
      'navigation stays enabled', (tester) async {
    await pumpMainPage(tester, _TestHealth(_down));

    expect(find.text('Device inoperable'), findsOneWidget);
    expect(_button(tester, 'Preview').onPressed, isNull);
    // Everything that is not a capture start stays reachable.
    expect(_button(tester, 'Open match').onPressed, isNotNull);
    expect(_button(tester, 'Disconnect').onPressed, isNotNull);
    expect(_button(tester, 'Diagnostics').onPressed, isNotNull);
  });

  testWidgets('main page — both OK: no banner, Preview enabled', (
    tester,
  ) async {
    await pumpMainPage(tester, _TestHealth(_ok));

    expect(find.text('Device inoperable'), findsNothing);
    expect(_button(tester, 'Preview').onPressed, isNotNull);
  });

  testWidgets('main page — recovering: soft note, no banner, no lockout', (
    tester,
  ) async {
    await pumpMainPage(tester, _TestHealth(_recovering));

    expect(find.text('Device inoperable'), findsNothing);
    expect(find.textContaining('Camera recovering'), findsOneWidget);
    expect(_button(tester, 'Preview').onPressed, isNotNull);
  });

  testWidgets('main page — banner is state-driven: appears when health flips '
      'DOWN and clears when it recovers (dismiss-proof)', (tester) async {
    final health = _TestHealth(_ok);
    await pumpMainPage(tester, health);
    expect(find.text('Device inoperable'), findsNothing);

    health.set(_down);
    await tester.pump();
    expect(find.text('Device inoperable'), findsOneWidget);
    // No close affordance exists on the banner.
    expect(
      find.descendant(
        of: find.ancestor(
          of: find.text('Device inoperable'),
          matching: find.byType(Container),
        ),
        matching: find.byIcon(Icons.close),
      ),
      findsNothing,
    );

    health.set(_ok);
    await tester.pump();
    expect(find.text('Device inoperable'), findsNothing);
  });

  // ---------------------------------------------------------------------
  // Setup screen + session screen (via the MatchPage flow)
  // ---------------------------------------------------------------------

  Future<void> pumpMatchPage(WidgetTester tester, _TestHealth health) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final mock = _newMock();
    addTearDown(mock.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [...dbOverrides(db), ..._connectedOverrides(mock, health)],
        child: const MaterialApp(home: MatchPage()),
      ),
    );
  }

  Future<void> reachSetupScreen(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final row = find.textContaining('vs Eastfield FC');
    expect(row, findsWidgets, reason: 'Landing must show upcoming matches');
    await tester.tap(row.first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Match setup'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('setup screen — inoperable: banner shown, Start match disabled '
      'by the same gate', (tester) async {
    await pumpMatchPage(tester, _TestHealth(_down));
    await reachSetupScreen(tester);

    await tester.scrollUntilVisible(find.text('Start match'), 200);
    expect(find.text('Device inoperable'), findsOneWidget);
    expect(_button(tester, 'Start match').onPressed, isNull);
  });

  testWidgets('setup screen — both OK: no banner, Start match enabled', (
    tester,
  ) async {
    await pumpMatchPage(tester, _TestHealth(_ok));
    await reachSetupScreen(tester);

    await tester.scrollUntilVisible(find.text('Start match'), 200);
    expect(find.text('Device inoperable'), findsNothing);
    expect(_button(tester, 'Start match').onPressed, isNotNull);
  });

  testWidgets('session screen — health flips DOWN mid-session: banner '
      'appears, Record + Start streaming disabled, then recovers', (
    tester,
  ) async {
    final health = _TestHealth(_ok);
    await pumpMatchPage(tester, health);
    await reachSetupScreen(tester);

    // Start the match (healthy) to reach the session screen.
    final startBtn = find.text('Start match');
    await tester.scrollUntilVisible(startBtn, 200);
    await tester.pump();
    await tester.tap(startBtn);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Kickoff'), findsOneWidget);

    // Healthy: everything enabled, no banner.
    expect(find.text('Device inoperable'), findsNothing);
    expect(_button(tester, 'Record').onPressed, isNotNull);
    expect(_button(tester, 'Start streaming').onPressed, isNotNull);

    // AE5: one camera goes DOWN → banner + capture starts locked.
    health.set(_down);
    await tester.pump();
    expect(find.text('Device inoperable'), findsOneWidget);
    expect(_button(tester, 'Record').onPressed, isNull);
    expect(_button(tester, 'Start streaming').onPressed, isNull);
    // The match itself is not locked out (kickoff is a timer action).
    expect(_button(tester, 'Kickoff').onPressed, isNotNull);

    // RECOVERING: soft state — no banner, no lockout.
    health.set(_recovering);
    await tester.pump();
    expect(find.text('Device inoperable'), findsNothing);
    expect(find.textContaining('Camera recovering'), findsOneWidget);
    expect(_button(tester, 'Record').onPressed, isNotNull);
    expect(_button(tester, 'Start streaming').onPressed, isNotNull);
  });

  // ---------------------------------------------------------------------
  // Downloads stay enabled (AE5) — the gate never touches retrieval
  // ---------------------------------------------------------------------

  testWidgets('download sheet — starting a download works while the device '
      'is inoperable', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final wifi = _SpyWifi();
    final mock = _newMock();
    addTearDown(mock.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...dbOverrides(db),
          bleServiceProvider.overrideWithValue(mock),
          activeCameraIdProvider.overrideWith((_) => _kDeviceId),
          connectionStateProvider(_kDeviceId).overrideWith(
            (_) => Stream<CameraConnectionState>.value(
              CameraConnectionState.connected,
            ),
          ),
          deviceHealthProvider.overrideWith(() => _TestHealth(_down)),
          liveSessionActiveProvider.overrideWithValue(false),
          deviceRecordingProvider.overrideWith((ref, matchId) => null),
          activeUserProvider.overrideWith((_) => 'user-1'),
          wifiServiceProvider.overrideWithValue(wifi),
          videoPathServiceProvider.overrideWithValue(_AbsentPathSvc()),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: DownloadSheet(
              match: const LibraryMatch(
                id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
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
              allEvents: const [],
              selectedEvents: const [],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Start download'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      wifi.downloadCalls,
      1,
      reason: 'an inoperable device must never lock downloads (AE5)',
    );
  });
}

// Records whether a download was ever requested (mirrors the live-session
// gate test's spy).
class _SpyWifi extends MockWifiService {
  int downloadCalls = 0;

  // The camera link is up — reachability is not what this test exercises.
  @override
  Future<bool> isCameraReachable(String deviceId) async => true;

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
