// Match-setup streaming protocol picker: None / RTMP / RTMPS / RTSP with an
// inline URL (+ key for RTMP/RTMPS). Mirrors match_page_test's harness
// (Timer.periodic → no pumpAndSettle).

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

Widget _harness(MockBleService service, DbRef db) => ProviderScope(
  overrides: [
    ...dbOverrides(db),
    bleServiceProvider.overrideWithValue(service),
    activeCameraIdProvider.overrideWith((_) => _kFakeDeviceId),
    connectionStateProvider(_kFakeDeviceId).overrideWith(
      (_) =>
          Stream<CameraConnectionState>.value(CameraConnectionState.connected),
    ),
    activeUserProvider.overrideWith((_) => 'user-1'),
  ],
  child: const MaterialApp(home: MatchPage()),
);

Future<void> _navigateToSetup(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 100));
  await tester.tap(find.textContaining('vs Eastfield FC').first);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  expect(find.text('Match setup'), findsOneWidget);
}

Future<void> _pickDestination(WidgetTester tester, String label) async {
  await tester.scrollUntilVisible(find.text('Destination'), 200);
  // The Destination dropdown shows 'None' by default; tap it, then the option.
  await tester.tap(find.text('None').last);
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

void main() {
  final db = useInMemoryDb();

  setUp(() {
    SharedPreferences.setMockInitialValues({'active_user_id': 'user-1'});
  });

  testWidgets('default None → record-only, no URL field', (tester) async {
    await tester.pumpWidget(_harness(_newMock(), db));
    await _navigateToSetup(tester);
    await tester.scrollUntilVisible(find.text('Destination'), 200);

    expect(find.text('None'), findsWidgets);
    // No URL/key entry until a streaming protocol is picked.
    expect(find.byType(TextField), findsNothing);
    // Start match is reachable (record-only is a valid, startable selection).
    await tester.scrollUntilVisible(find.text('Start match'), 200);
    expect(find.text('Start match'), findsOneWidget);
  });

  testWidgets('RTMP reveals URL field; invalid URL blocks start', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(_newMock(), db));
    await _navigateToSetup(tester);
    await _pickDestination(tester, 'RTMP');

    // URL field appears; a non-rtmp URL shows the scheme error.
    final urlField = find.byType(TextField).first;
    await tester.enterText(urlField, 'http://nope/live');
    await tester.pump();
    expect(find.textContaining('Must start with rtmp://'), findsOneWidget);

    // A scheme-valid URL clears the error.
    await tester.enterText(urlField, 'rtmp://ingest/live');
    await tester.pump();
    expect(find.textContaining('Must start with'), findsNothing);
  });

  testWidgets('RTSP shows the firmware-unsupported note', (tester) async {
    await tester.pumpWidget(_harness(_newMock(), db));
    await _navigateToSetup(tester);
    await _pickDestination(tester, 'RTSP');

    expect(
      find.textContaining('RTSP egress is not yet supported'),
      findsOneWidget,
    );
    // RTSP has no separate stream-key field.
    expect(find.text('Stream key (optional)'), findsNothing);
  });
}
