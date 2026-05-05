// U8 — Settings User-section tests.
//
// We override `connectionStateProvider(activeId)` directly with a finite
// Stream so `pumpAndSettle` can terminate without touching the mock's real
// connect path (which spawns a Timer.periodic for telemetry). We never call
// `mock.connect()`.
//
// Test isolation: `useDevDataStoreReset()` re-seeds the DevDataStore between
// tests so the seed users (Coach Diego, Coach Maria) are always there.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scout_camera/ble/dev_data_store.dart';
import 'package:scout_camera/ble/mock_ble_service.dart';
import 'package:scout_camera/models/device.dart';
import 'package:scout_camera/pages/settings_page.dart';
import 'package:scout_camera/state/app_data.dart';
import 'package:scout_camera/state/ble_providers.dart';

import '../test_helpers.dart';

const String _kFakeDeviceId = 'SST-CAM-001';

MockBleService _newMock() => MockBleService(
  scanDeviceAppearDelays: const [Duration.zero, Duration.zero],
  connectionDelay: Duration.zero,
  failureRate: 0.0,
  randomSeed: 1,
);

/// MockBleService variant that returns null from `getActiveUser`, simulating
/// the post-reconnect path where the camera reports no active user — used to
/// exercise the User section's "Pick a user" shape.
class _NullActiveUserMock extends MockBleService {
  _NullActiveUserMock()
    : super(
        scanDeviceAppearDelays: const [Duration.zero, Duration.zero],
        connectionDelay: Duration.zero,
        failureRate: 0.0,
        randomSeed: 1,
      );

  @override
  Future<String?> getActiveUser(String deviceId) async => null;
}

Widget _buildHarness({
  required MockBleService service,
  String? activeUserId = 'user-1',
}) {
  return ProviderScope(
    overrides: [
      bleServiceProvider.overrideWithValue(service),
      activeCameraIdProvider.overrideWith((_) => _kFakeDeviceId),
      connectionStateProvider(_kFakeDeviceId).overrideWith(
        (_) => Stream<CameraConnectionState>.value(
          CameraConnectionState.connected,
        ),
      ),
      if (activeUserId != null)
        activeUserProvider.overrideWith((_) => activeUserId),
    ],
    child: const MaterialApp(home: SettingsPage()),
  );
}

void main() {
  useDevDataStoreReset();

  group('Active-user shape', () {
    testWidgets('active user row renders with name and Active badge', (
      tester,
    ) async {
      final mock = _newMock();
      addTearDown(mock.dispose);

      await tester.pumpWidget(_buildHarness(service: mock));
      await tester.pumpAndSettle();

      // Active user is Coach Diego (seed user-1).
      expect(find.text('Coach Diego'), findsOneWidget);
      // "Active" badge.
      expect(find.text('Active'), findsOneWidget);
    });

    testWidgets('other users render with delete affordance', (tester) async {
      final mock = _newMock();
      addTearDown(mock.dispose);

      await tester.pumpWidget(_buildHarness(service: mock));
      await tester.pumpAndSettle();

      // Coach Maria appears in the others list.
      expect(find.text('Coach Maria'), findsOneWidget);
      // At least one delete affordance is visible (for the others row).
      expect(find.byIcon(Icons.delete_outline), findsAtLeastNWidgets(1));
      // The "Switch to set as active" subtitle is on Maria's row.
      expect(find.text('Switch to set as active'), findsOneWidget);
    });

    testWidgets('Add user row visible with person_add icon', (tester) async {
      final mock = _newMock();
      addTearDown(mock.dispose);

      await tester.pumpWidget(_buildHarness(service: mock));
      await tester.pumpAndSettle();

      expect(find.text('Add user'), findsOneWidget);
      expect(find.byIcon(Icons.person_add_outlined), findsOneWidget);
    });

    testWidgets('active user is not rendered in the others list (no '
        'delete affordance for the active user)', (tester) async {
      final mock = _newMock();
      addTearDown(mock.dispose);

      await tester.pumpWidget(_buildHarness(service: mock));
      await tester.pumpAndSettle();

      // Coach Diego appears exactly once — in the active row.
      expect(find.text('Coach Diego'), findsOneWidget);
      // Only one delete icon — the one on the others list (Maria).
      expect(find.byIcon(Icons.delete_outline), findsOneWidget);
    });
  });

  group('Switch dialog (AE3)', () {
    testWidgets('tapping a non-active user opens dialog whose body contains '
        'the reload-data copy', (tester) async {
      final mock = _newMock();
      addTearDown(mock.dispose);

      await tester.pumpWidget(_buildHarness(service: mock));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Coach Maria'));
      await tester.pumpAndSettle();

      expect(find.text('Switch user?'), findsOneWidget);
      // Body contains the user name and the reload-data sentence.
      expect(
        find.textContaining('Switch to Coach Maria?'),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          'Your teams, matches, and streaming destinations will reload',
        ),
        findsOneWidget,
      );
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Switch'), findsOneWidget);
    });

    testWidgets('confirming the switch dialog updates activeUserProvider', (
      tester,
    ) async {
      final mock = _newMock();
      addTearDown(mock.dispose);

      late ProviderContainer container;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            bleServiceProvider.overrideWithValue(mock),
            activeCameraIdProvider.overrideWith((_) => _kFakeDeviceId),
            connectionStateProvider(_kFakeDeviceId).overrideWith(
              (_) => Stream<CameraConnectionState>.value(
                CameraConnectionState.connected,
              ),
            ),
            activeUserProvider.overrideWith((_) => 'user-1'),
          ],
          child: Builder(
            builder: (context) {
              container = ProviderScope.containerOf(context);
              return const MaterialApp(home: SettingsPage());
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open dialog and confirm.
      await tester.tap(find.text('Coach Maria'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Switch'));
      await tester.pumpAndSettle();

      // activeUserProvider is now user-2.
      expect(container.read(activeUserProvider), 'user-2');
      // The active row now shows Coach Maria.
      expect(find.text('Coach Maria'), findsOneWidget);
      // Coach Diego is now in the others list.
      expect(find.text('Coach Diego'), findsOneWidget);
    });
  });

  group('Delete dialog (AE4 — cascade enumeration)', () {
    testWidgets('delete dialog body literally contains the four cascaded '
        'collection names', (tester) async {
      final mock = _newMock();
      addTearDown(mock.dispose);

      await tester.pumpWidget(_buildHarness(service: mock));
      await tester.pumpAndSettle();

      // Tap Maria's delete icon. Maria is the only "other" user, so
      // the single delete icon is hers.
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();

      expect(find.text('Delete user?'), findsOneWidget);

      // The dialog body must enumerate all four cascaded collections.
      // Use a single Finder.byWidgetPredicate over Text widgets so the
      // assertion is robust to wrapping / paragraph boundaries.
      final dialogBody = find.byWidgetPredicate((w) {
        if (w is! Text) return false;
        final s = w.data ?? '';
        return s.contains('teams') &&
            s.contains('match history') &&
            s.contains('sport setups') &&
            s.contains('streaming destinations');
      });
      expect(dialogBody, findsOneWidget);

      // Confirm + cancel buttons.
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Delete user'), findsOneWidget);
    });

    testWidgets('AE4: confirming delete cascades through DevDataStore — '
        'Coach Maria with a streaming destination is fully removed', (
      tester,
    ) async {
      // Populate Maria with a streaming destination directly via the store.
      DevDataStore.instance.createStreamingDestination(
        'user-2',
        const StreamingDestinationDraft(
          name: 'Maria YT',
          provider: StreamingProvider.youtube,
          protocol: StreamingProtocol.rtmp,
          config: RtmpConfig(
            url: 'rtmp://a.rtmp.youtube.com/live2',
            streamKey: 'k',
          ),
        ),
      );
      expect(
        DevDataStore.instance.listStreamingDestinations('user-2'),
        hasLength(1),
      );

      final mock = _newMock();
      addTearDown(mock.dispose);

      await tester.pumpWidget(_buildHarness(service: mock));
      await tester.pumpAndSettle();

      // Open delete dialog for Maria and confirm.
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete user'));
      await tester.pumpAndSettle();

      // Maria's row is gone.
      expect(find.text('Coach Maria'), findsNothing);
      // Diego is still the active user.
      expect(find.text('Coach Diego'), findsOneWidget);
      expect(find.text('Active'), findsOneWidget);

      // DevDataStore no longer lists user-2.
      final users = DevDataStore.instance.listUsers();
      expect(users.map((u) => u.id), isNot(contains('user-2')));
    });
  });

  group('Single-user case (last user remaining)', () {
    testWidgets('with only Coach Diego remaining, no delete affordance is '
        'rendered for him', (tester) async {
      // Default seed gives 2 users; remove user-2 directly to leave just
      // user-1 (active). user-2 is non-active so the store allows delete.
      DevDataStore.instance.deleteUser('user-2');
      expect(DevDataStore.instance.listUsers(), hasLength(1));

      final mock = _newMock();
      addTearDown(mock.dispose);

      await tester.pumpWidget(_buildHarness(service: mock));
      await tester.pumpAndSettle();

      // Diego is still the active user; no other rows; no delete icon.
      expect(find.text('Coach Diego'), findsOneWidget);
      expect(find.text('Active'), findsOneWidget);
      expect(find.text('Coach Maria'), findsNothing);
      // The active user is never in the others list, so no delete icon
      // is visible at all in this state.
      expect(find.byIcon(Icons.delete_outline), findsNothing);
    });
  });

  group('Add user flow', () {
    testWidgets('tapping Add user opens the bottom sheet form', (
      tester,
    ) async {
      final mock = _newMock();
      addTearDown(mock.dispose);

      await tester.pumpWidget(_buildHarness(service: mock));
      await tester.pumpAndSettle();

      // The settings page has its own "Add user" row text; tap the row's
      // InkWell. Use the last "Add user" finder (the row, below any badge
      // copy that may share the label in dialogs etc.).
      await tester.tap(find.text('Add user'));
      await tester.pumpAndSettle();

      // Bottom sheet appeared with a TextField.
      expect(find.byType(TextField), findsOneWidget);
      // The sheet's primary submit also reads "Add user" — there are now
      // two on screen. Both row + submit button render the same label.
      expect(find.text('Add user'), findsAtLeastNWidgets(2));
    });

    testWidgets('Add user happy path: typed name appears as a new row', (
      tester,
    ) async {
      final mock = _newMock();
      addTearDown(mock.dispose);

      await tester.pumpWidget(_buildHarness(service: mock));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add user'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Coach C');
      // The sheet's submit is the "Add user" button rendered last.
      await tester.tap(find.text('Add user').last);
      await tester.pumpAndSettle();

      // The new user appears in the others list.
      expect(find.text('Coach C'), findsOneWidget);
      // Diego is still active.
      expect(find.text('Coach Diego'), findsOneWidget);
      // Coach Maria is also still around.
      expect(find.text('Coach Maria'), findsOneWidget);
    });
  });

  group('No-active-user shape', () {
    testWidgets('with activeUserProvider null, renders Pick-a-user note + '
        'Make active icons + Add user; no Active badge', (tester) async {
      // UsersController.build() hydrates activeUserProvider from
      // BleService.getActiveUser when the provider is null. Use a custom
      // mock that returns null from getActiveUser so the hydration leaves
      // activeUserProvider null — that's the no-active-user shape.
      final mock = _NullActiveUserMock();
      addTearDown(mock.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            bleServiceProvider.overrideWithValue(mock),
            activeCameraIdProvider.overrideWith((_) => _kFakeDeviceId),
            connectionStateProvider(_kFakeDeviceId).overrideWith(
              (_) => Stream<CameraConnectionState>.value(
                CameraConnectionState.connected,
              ),
            ),
          ],
          child: const MaterialApp(home: SettingsPage()),
        ),
      );
      await tester.pumpAndSettle();

      // The "Pick a user" guidance is present.
      expect(
        find.textContaining(
          'Pick a user to organize your teams, matches, and streaming',
        ),
        findsOneWidget,
      );
      // No "Active" badge in this state.
      expect(find.text('Active'), findsNothing);
      // Both seed users are listed with a "Make active" radio icon each.
      expect(find.text('Coach Diego'), findsOneWidget);
      expect(find.text('Coach Maria'), findsOneWidget);
      expect(
        find.byIcon(Icons.radio_button_unchecked),
        findsNWidgets(2),
      );
      // Add user row remains.
      expect(find.text('Add user'), findsOneWidget);
    });
  });
}
