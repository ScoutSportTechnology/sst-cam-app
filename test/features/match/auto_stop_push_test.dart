// U5 — auto_stop_minutes rides every PushSessionConfig (R5).
//
// Start-match flow (mirrors match_page_test's harness — explicit pumps, no
// pumpAndSettle, because the session screen runs a Timer.periodic):
//   - untouched setting → the pushed config carries the default 30
//   - persisted 90 → the pushed config carries 90

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sst_cam_app/core/ble/ble_providers.dart';
import 'package:sst_cam_app/core/models/command.dart';
import 'package:sst_cam_app/core/models/device.dart';
import 'package:sst_cam_app/features/camera/camera_state.dart'
    show activeCameraIdProvider;
import 'package:sst_cam_app/features/match/match_page.dart';
import 'package:sst_cam_app/features/settings/users/users_state.dart'
    show activeUserProvider;
import 'package:sst_cam_app/mock/emulator/mock_ble_service.dart';

import '../../test_helpers.dart';

const _kFakeDeviceId = 'SST-CAM-001';

MockBleService _newMock() => MockBleService(
  scanDeviceAppearDelays: const [Duration.zero],
  connectionDelay: Duration.zero,
  failureRate: 0.0,
  randomSeed: 1,
);

Widget _harness(MockBleService service, DbRef db) => ProviderScope(
  overrides: [
    ...dbOverrides(db),
    bleServiceProvider.overrideWithValue(service),
    activeCameraIdProvider.overrideWith((_) => _kFakeDeviceId),
    connectionStateProvider(_kFakeDeviceId).overrideWith(
      (_) =>
          Stream<CameraConnectionState>.value(CameraConnectionState.connected),
    ),
    // Faked connection ⇒ no handshake/telemetry health readings — pin the
    // U3 gate open (health gating has its own dedicated tests).
    healthyDeviceOverride(),
    activeUserProvider.overrideWith((_) => 'user-1'),
  ],
  child: const MaterialApp(home: MatchPage()),
);

Future<void> _startMatch(WidgetTester tester, MockBleService mock) async {
  await tester.binding.setSurfaceSize(const Size(800, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(_harness(mock, _db));

  // Navigate to setup (Drift stream needs a few pumps to emit).
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 100));
  await tester.tap(find.textContaining('vs Eastfield FC').first);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  expect(find.text('Match setup'), findsOneWidget);

  // Start the match (button may be below the fold).
  final start = find.text('Start match');
  await tester.scrollUntilVisible(start, 200);
  await tester.pump();
  await tester.tap(start);
  await tester.pump(); // start async gap
  await tester.pump(const Duration(milliseconds: 200)); // cover mock delay
}

late DbRef _db;

void main() {
  _db = useInMemoryDb();

  testWidgets('untouched setting → pushed config carries the default 30', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'active_user_id': 'user-1'});
    final mock = _newMock();
    addTearDown(mock.dispose);

    await _startMatch(tester, mock);

    expect(mock.lastPushedConfig, isNotNull);
    expect(mock.lastPushedConfig!.autoStopMinutes, kDefaultAutoStopMinutes);
  });

  testWidgets('persisted 90 → pushed config carries 90', (tester) async {
    SharedPreferences.setMockInitialValues({
      'active_user_id': 'user-1',
      'auto_stop_minutes': 90,
    });
    final mock = _newMock();
    addTearDown(mock.dispose);

    await _startMatch(tester, mock);

    expect(mock.lastPushedConfig, isNotNull);
    expect(mock.lastPushedConfig!.autoStopMinutes, 90);
  });
}
