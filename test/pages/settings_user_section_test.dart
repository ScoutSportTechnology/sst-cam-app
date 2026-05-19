// Settings User-section tests — compact chip shape.
//
// The User section shows:
//   - A WfCard with [Active chip] + name + expand_more icon (full-width menu)
//   - A "Manage users" nav row (opens ManageUsersPage with FAB for Add user)
//
// Delete, add-user, and full-list management are tested in
// manage_users_page_test.dart.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sst_cam_app/ble/mock_ble_service.dart';
import 'package:sst_cam_app/models/device.dart';
import 'package:sst_cam_app/pages/users_settings_page.dart';
import 'package:sst_cam_app/state/app_data.dart';
import 'package:sst_cam_app/state/ble_providers.dart';
import 'package:sst_cam_app/widgets/wf_chip.dart';

import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers.dart';

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

  group('Compact user row (AE3)', () {
    testWidgets('Active chip + user name displayed in compact row', (
      tester,
    ) async {
      final mock = _newMock();
      addTearDown(mock.dispose);

      await tester.pumpWidget(buildHarness(service: mock));
      await tester.pumpAndSettle();

      // Active chip and user name visible.
      expect(find.text('Coach Diego'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) => w is WfChip && w.label == 'Active' && w.active == true,
        ),
        findsOneWidget,
      );
      // Expand indicator.
      expect(find.byIcon(Icons.expand_more), findsOneWidget);
      // No delete icon on Settings page.
      expect(find.byIcon(Icons.delete_outline), findsNothing);
    });

    testWidgets('Manage users nav row visible; Add user not on Settings page', (
      tester,
    ) async {
      final mock = _newMock();
      addTearDown(mock.dispose);

      await tester.pumpWidget(buildHarness(service: mock));
      await tester.pumpAndSettle();

      expect(find.text('Manage users'), findsOneWidget);
      expect(find.text('Add user'), findsNothing);
    });

    testWidgets('full-width menu shows all users with Active chip', (
      tester,
    ) async {
      final mock = _newMock();
      addTearDown(mock.dispose);

      await tester.pumpWidget(buildHarness(service: mock));
      await tester.pumpAndSettle();

      // Tap the expand icon to open the full-width picker.
      await tester.tap(find.byIcon(Icons.expand_more));
      await tester.pumpAndSettle();

      // Both users appear in the menu.
      expect(find.text('Coach Diego'), findsAtLeastNWidgets(1));
      expect(find.text('Coach Maria'), findsOneWidget);
      // Active badge on Diego's menu item.
      expect(
        find.byWidgetPredicate(
          (w) => w is WfChip && w.label == 'Active' && w.active == true,
        ),
        findsAtLeastNWidgets(1),
      );
    });
  });

  group('Switch dialog (AE3)', () {
    testWidgets(
      'selecting a non-active user from the menu opens the switch dialog',
      (tester) async {
        final mock = _newMock();
        addTearDown(mock.dispose);

        await tester.pumpWidget(buildHarness(service: mock));
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.expand_more));
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

      await tester.tap(find.byIcon(Icons.expand_more));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Coach Maria'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Switch'));
      await tester.pumpAndSettle();

      expect(container.read(activeUserProvider), 'user-2');
      // Compact row shows Coach Maria's name.
      expect(find.text('Coach Maria'), findsOneWidget);
    });

    testWidgets('canceling the dialog leaves active user unchanged', (
      tester,
    ) async {
      final mock = _newMock();
      addTearDown(mock.dispose);

      await tester.pumpWidget(buildHarness(service: mock));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.expand_more));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Coach Maria'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Coach Diego'), findsOneWidget);
    });
  });

  group('No-active-user shape', () {
    testWidgets('with null activeUser, compact row shows "Pick a user" note', (
      tester,
    ) async {
      // No active_user_id in SharedPreferences → activeUserProvider stays null.
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

      expect(find.textContaining('Pick a user to get started'), findsOneWidget);
      // No Active chip in the main view.
      expect(
        find.byWidgetPredicate(
          (w) => w is WfChip && w.label == 'Active' && w.active == true,
        ),
        findsNothing,
      );
      // Manage users nav row remains.
      expect(find.text('Manage users'), findsOneWidget);
    });
  });
}
