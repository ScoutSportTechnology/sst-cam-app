// U12 — setup screen record/stream quality pickers.
//
// Verifies:
//   - AE6: pickers are populated from the firmware-advertised supported modes
//     (the mock advertises 1080p30/60 + 720p30/60, no 4K).
//   - Disconnected / no advertised modes: pickers render disabled with the
//     "Connect to camera to load available modes" hint (shown, not hidden).
//
// Mirrors match_page_test's harness (Timer.periodic → no pumpAndSettle).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sst_cam_app/core/ble/ble_providers.dart';
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

Widget _buildHarness({
  required MockBleService service,
  required DbRef db,
  CameraConnectionState connectionState = CameraConnectionState.connected,
}) {
  return ProviderScope(
    overrides: [
      ...dbOverrides(db),
      bleServiceProvider.overrideWithValue(service),
      activeCameraIdProvider.overrideWith((_) => _kFakeDeviceId),
      connectionStateProvider(_kFakeDeviceId).overrideWith(
        (_) => Stream<CameraConnectionState>.value(connectionState),
      ),
      activeUserProvider.overrideWith((_) => 'user-1'),
    ],
    child: const MaterialApp(home: MatchPage()),
  );
}

Future<void> _navigateToSetup(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 100));
  final row = find.textContaining('vs Eastfield FC');
  expect(row, findsWidgets, reason: 'Landing should show upcoming matches');
  await tester.tap(row.first);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  expect(find.text('Match setup'), findsOneWidget);
  // Let the connectedDeviceInfo future resolve (advertised modes).
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  final db = useInMemoryDb();

  setUp(() {
    SharedPreferences.setMockInitialValues({'active_user_id': 'user-1'});
  });

  testWidgets('AE6: pickers offer exactly the advertised modes (no 4K)', (
    tester,
  ) async {
    await tester.pumpWidget(_buildHarness(service: _newMock(), db: db));
    await _navigateToSetup(tester);

    // Both picker rows render with the preferred default (1080p30) selected.
    await tester.scrollUntilVisible(find.text('Record quality'), 200);
    expect(find.text('Record quality'), findsOneWidget);
    expect(find.text('Stream quality'), findsOneWidget);
    // One shown per dropdown (record + stream both default to 1080p30).
    expect(find.text('1080p · 30 fps'), findsWidgets);

    // Open a dropdown: it offers the advertised ladder (720p60 for high fps) and
    // NOT 4K, nor 1080p60 (unsustainable in software encode — see firmware).
    await tester.tap(find.text('1080p · 30 fps').first);
    await tester.pumpAndSettle();
    expect(find.text('720p · 30 fps'), findsWidgets);
    expect(find.text('720p · 60 fps'), findsWidgets);
    expect(find.text('4K · 30 fps'), findsNothing);
    expect(find.text('1080p · 60 fps'), findsNothing);
  });

  testWidgets('disconnected: pickers disabled with connect hint', (
    tester,
  ) async {
    await tester.pumpWidget(
      _buildHarness(
        service: _newMock(),
        db: db,
        connectionState: CameraConnectionState.disconnected,
      ),
    );
    await _navigateToSetup(tester);

    await tester.scrollUntilVisible(find.text('Record quality'), 200);
    // No advertised modes → hint shown (pickers present but disabled).
    expect(
      find.text('Connect to camera to load available modes'),
      findsOneWidget,
    );
    expect(find.text('Record quality'), findsOneWidget);
    expect(find.text('Stream quality'), findsOneWidget);
  });
}
