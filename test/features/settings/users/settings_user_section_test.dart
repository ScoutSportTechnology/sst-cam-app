// Settings UsersSettingsPage tests — direct user list.
//
// The Users page shows:
//   - A list of users; active user has a checkmark icon
//   - Non-active users are tappable (opens switch dialog) and have a delete icon
//   - FAB opens the add-user form sheet
//   - No "Manage users" nav row — management is inline

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sst_cam_app/mock/emulator/mock_ble_service.dart';
import 'package:sst_cam_app/core/models/device.dart';
import 'package:sst_cam_app/features/settings/users/users_settings_page.dart';
import 'package:sst_cam_app/features/camera/camera_state.dart'
    show activeCameraIdProvider;
import 'package:sst_cam_app/features/settings/users/users_state.dart'
    show activeUserProvider;
import 'package:sst_cam_app/core/ble/ble_providers.dart';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../test_helpers.dart';

const String _kFakeDeviceId = 'SST-CAM-001';

MockBleService _newMock() => MockBleService(
  scanDeviceAppearDelays: const [Duration.zero, Duration.zero],
  connectionDelay: Duration.zero,
  failureRate: 0.0,
  randomSeed: 1,
);

void main() {
  final db = useInMemoryDb();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Widget buildHarness({
    required MockBleService service,
    String? activeUserId = 'user-1',
  }) {
    return ProviderScope(
      overrides: [
        ...dbOverrides(db),
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
      child: const MaterialApp(home: UsersSettingsPage()),
    );
  }

  group('User list (direct picker)', () {
    testWidgets('both users visible; active user shows checkmark', (
      tester,
    ) async {
      final mock = _newMock();
      addTearDown(mock.dispose);

      await tester.pumpWidget(buildHarness(service: mock));
      await tester.pumpAndSettle();

      // Both users visible in the list.
      expect(find.text('Coach Diego'), findsOneWidget);
      expect(find.text('Coach Maria'), findsOneWidget);
      // Active user (Diego) shows checkmark.
      expect(find.byIcon(Icons.check), findsOneWidget);
      // Non-active user (Maria) shows radio button unchecked.
      expect(find.byIcon(Icons.radio_button_unchecked), findsOneWidget);
      // No expand_more icon (no dropdown).
      expect(find.byIcon(Icons.expand_more), findsNothing);
      // No "Manage users" row.
      expect(find.text('Manage users'), findsNothing);
    });

    testWidgets('non-active user row has delete icon', (tester) async {
      final mock = _newMock();
      addTearDown(mock.dispose);

      await tester.pumpWidget(buildHarness(service: mock));
      await tester.pumpAndSettle();

      // Maria is non-active → has delete icon. Active user (Diego) must not have one.
      final mariaRow = find.ancestor(
        of: find.text('Coach Maria'),
        matching: find.byType(InkWell),
      );
      expect(find.descendant(of: mariaRow, matching: find.byIcon(Icons.delete_outline)), findsOneWidget);
      final diegoRow = find.ancestor(
        of: find.text('Diego'),
        matching: find.byType(InkWell),
      );
      expect(find.descendant(of: diegoRow, matching: find.byIcon(Icons.delete_outline)), findsNothing);
    });

    testWidgets('active user row is not tappable (no switch for self)', (
      tester,
    ) async {
      final mock = _newMock();
      addTearDown(mock.dispose);

      await tester.pumpWidget(buildHarness(service: mock));
      await tester.pumpAndSettle();

      // Tapping the active user (Diego) should not show the switch dialog.
      await tester.tap(find.text('Coach Diego'));
      await tester.pumpAndSettle();
      expect(find.text('Switch user?'), findsNothing);
    });
  });

  group('Switch dialog', () {
    testWidgets(
      'tapping a non-active user opens the switch dialog',
      (tester) async {
        final mock = _newMock();
        addTearDown(mock.dispose);

        await tester.pumpWidget(buildHarness(service: mock));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Coach Maria'));
        await tester.pumpAndSettle();

        expect(find.text('Switch user?'), findsOneWidget);
        expect(find.textContaining('Switch to Coach Maria?'), findsOneWidget);
        expect(
          find.textContaining(
            'Your teams, matches, and streaming destinations will reload',
          ),
          findsOneWidget,
        );
        expect(find.text('Cancel'), findsOneWidget);
        expect(find.text('Switch'), findsOneWidget);
      },
    );

    testWidgets('confirming the switch dialog updates activeUserProvider', (
      tester,
    ) async {
      final mock = _newMock();
      addTearDown(mock.dispose);

      late ProviderContainer container;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...dbOverrides(db),
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
              return const MaterialApp(home: UsersSettingsPage());
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Coach Maria'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Switch'));
      await tester.pumpAndSettle();

      expect(container.read(activeUserProvider), 'user-2');
      // Coach Maria is now the active user (checkmark on her row).
      expect(find.byIcon(Icons.check), findsOneWidget);
    });

    testWidgets('canceling the dialog leaves active user unchanged', (
      tester,
    ) async {
      final mock = _newMock();
      addTearDown(mock.dispose);

      await tester.pumpWidget(buildHarness(service: mock));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Coach Maria'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      // Diego still has the checkmark.
      expect(find.byIcon(Icons.check), findsOneWidget);
      // No "Switch user?" dialog.
      expect(find.text('Switch user?'), findsNothing);
    });
  });

  group('Last-user delete guard', () {
    testWidgets('delete icon is absent when only one user exists', (
      tester,
    ) async {
      // Delete user-2 from the DB so only user-1 remains.
      // useInMemoryDb re-seeds per test, so db.value is fresh each time.
      await db.value.usersDao.deleteById('user-2');

      final mock = _newMock();
      addTearDown(mock.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...dbOverrides(db),
            bleServiceProvider.overrideWithValue(mock),
            activeCameraIdProvider.overrideWith((_) => _kFakeDeviceId),
            connectionStateProvider(_kFakeDeviceId).overrideWith(
              (_) => Stream<CameraConnectionState>.value(
                CameraConnectionState.connected,
              ),
            ),
            activeUserProvider.overrideWith((_) => 'user-1'),
          ],
          child: const MaterialApp(home: UsersSettingsPage()),
        ),
      );
      await tester.pumpAndSettle();

      // Only one user — canDelete is false for all rows → no delete icon.
      expect(find.byIcon(Icons.delete_outline), findsNothing);
      // User is present.
      expect(find.text('Coach Diego'), findsOneWidget);
    });
  });

  group('No-active-user shape', () {
    testWidgets('with null activeUser, all users show radio buttons (none active)', (
      tester,
    ) async {
      final mock = _newMock();
      addTearDown(mock.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...dbOverrides(db),
            bleServiceProvider.overrideWithValue(mock),
            activeCameraIdProvider.overrideWith((_) => _kFakeDeviceId),
            connectionStateProvider(_kFakeDeviceId).overrideWith(
              (_) => Stream<CameraConnectionState>.value(
                CameraConnectionState.connected,
              ),
            ),
          ],
          child: const MaterialApp(home: UsersSettingsPage()),
        ),
      );
      await tester.pumpAndSettle();

      // No checkmark — no active user.
      expect(find.byIcon(Icons.check), findsNothing);
      // Both users visible.
      expect(find.text('Coach Diego'), findsOneWidget);
      expect(find.text('Coach Maria'), findsOneWidget);
    });
  });
}
