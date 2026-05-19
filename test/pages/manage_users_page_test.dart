// ManageUsersPage tests — covers AE4 delete rules + switch affordance.
//
// This page is the nav destination for "Manage users" on SettingsPage.
// It lists all local-DB users with active badge, switch, and delete.
//
// Test isolation: `useInMemoryDb()` provides a fresh Drift in-memory DB
// seeded with user-1 / user-2 for every test.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sst_cam_app/ble/mock_ble_service.dart';
import 'package:sst_cam_app/pages/manage_users_page.dart';
import 'package:sst_cam_app/state/app_data.dart';
import 'package:sst_cam_app/state/ble_providers.dart';
import 'package:sst_cam_app/widgets/wf_chip.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers.dart';

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
    String? activeUserId = 'user-1',
    MockBleService? service,
  }) {
    final mock = service ?? _newMock();
    return ProviderScope(
      overrides: [
        ...dbOverrides(db),
        bleServiceProvider.overrideWithValue(mock),
        if (activeUserId != null)
          activeUserProvider.overrideWith((_) => activeUserId),
      ],
      child: const MaterialApp(home: ManageUsersPage()),
    );
  }

  group('User list (AE4)', () {
    testWidgets('active user row shows Active chip; non-active row does not', (
      tester,
    ) async {
      await tester.pumpWidget(buildHarness());
      await tester.pumpAndSettle();

      expect(find.text('Coach Diego'), findsOneWidget);
      expect(find.text('Coach Maria'), findsOneWidget);
      // Active chip on Diego's row.
      expect(
        find.byWidgetPredicate(
          (w) => w is WfChip && w.label == 'Active' && w.active == true,
        ),
        findsOneWidget,
      );
    });

    testWidgets('active user delete icon is disabled', (tester) async {
      await tester.pumpWidget(buildHarness());
      await tester.pumpAndSettle();

      // The subtitle under Diego's row (active user).
      expect(
        find.text('Switch to another user before deleting'),
        findsOneWidget,
      );
    });

    testWidgets('non-active user has enabled delete icon', (tester) async {
      await tester.pumpWidget(buildHarness());
      await tester.pumpAndSettle();

      // Maria's row has a delete icon. Both rows have a delete icon widget
      // (active is disabled, non-active is enabled). Maria's has no subtitle.
      expect(find.byIcon(Icons.delete_outline), findsNWidgets(2));
      expect(
        find.text('Switch to another user before deleting'),
        findsOneWidget,
      );
    });
  });

  group('Switch from ManageUsersPage', () {
    testWidgets('tapping a non-active user row opens the switch dialog', (
      tester,
    ) async {
      await tester.pumpWidget(buildHarness());
      await tester.pumpAndSettle();

      // Tap Coach Maria's row (non-active).
      await tester.tap(find.text('Coach Maria'));
      await tester.pumpAndSettle();

      expect(find.text('Switch user?'), findsOneWidget);
      expect(find.textContaining('Switch to Coach Maria?'), findsOneWidget);
    });

    testWidgets('confirming switch updates the active user', (tester) async {
      late ProviderContainer container;
      final mock = _newMock();
      addTearDown(mock.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...dbOverrides(db),
            bleServiceProvider.overrideWithValue(mock),
            activeUserProvider.overrideWith((_) => 'user-1'),
          ],
          child: Builder(
            builder: (ctx) {
              container = ProviderScope.containerOf(ctx);
              return const MaterialApp(home: ManageUsersPage());
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
      // Maria now shows Active chip.
      expect(
        find.byWidgetPredicate(
          (w) => w is WfChip && w.label == 'Active' && w.active == true,
        ),
        findsOneWidget,
      );
    });
  });

  group('Delete dialog (AE4 — cascade enumeration)', () {
    testWidgets(
      'delete dialog body contains the four cascaded collection names',
      (tester) async {
        await tester.pumpWidget(buildHarness());
        await tester.pumpAndSettle();

        // Maria is the non-active user; her delete icon should be enabled.
        final mariaRow = find.ancestor(
          of: find.text('Coach Maria'),
          matching: find.byType(InkWell),
        );
        final deleteBtn = find.descendant(
          of: mariaRow.first,
          matching: find.byIcon(Icons.delete_outline),
        );
        await tester.tap(deleteBtn);
        await tester.pumpAndSettle();

        expect(find.text('Delete user?'), findsOneWidget);

        final dialogBody = find.byWidgetPredicate((w) {
          if (w is! Text) return false;
          final s = w.data ?? '';
          return s.contains('teams') &&
              s.contains('match history') &&
              s.contains('sport setups') &&
              s.contains('streaming destinations');
        });
        expect(dialogBody, findsOneWidget);
        expect(find.text('Cancel'), findsOneWidget);
        expect(find.text('Delete user'), findsOneWidget);
      },
    );

    testWidgets('confirming delete removes the user row', (tester) async {
      await tester.pumpWidget(buildHarness());
      await tester.pumpAndSettle();

      final mariaRow = find.ancestor(
        of: find.text('Coach Maria'),
        matching: find.byType(InkWell),
      );
      final deleteBtn = find.descendant(
        of: mariaRow.first,
        matching: find.byIcon(Icons.delete_outline),
      );
      await tester.tap(deleteBtn);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete user'));
      await tester.pumpAndSettle();

      expect(find.text('Coach Maria'), findsNothing);
      expect(find.text('Coach Diego'), findsOneWidget);

      // Verify deletion via DAO directly.
      final users = await db.value.usersDao.getAll();
      expect(users.map((u) => u.id), isNot(contains('user-2')));
    });
  });

  group('Add user FAB', () {
    testWidgets('tapping FAB opens the Add user form sheet', (tester) async {
      await tester.pumpWidget(buildHarness());
      await tester.pumpAndSettle();

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Add user'), findsAtLeastNWidgets(1));
    });

    testWidgets('adding a user via FAB shows the new user in the list', (
      tester,
    ) async {
      await tester.pumpWidget(buildHarness());
      await tester.pumpAndSettle();

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Coach C');
      await tester.tap(find.text('Add user').last);
      await tester.pumpAndSettle();

      expect(find.text('Coach C'), findsOneWidget);
    });
  });

  group('Single-user case (last user remaining)', () {
    testWidgets(
      'with only one user, delete is blocked with the last-user message',
      (tester) async {
        // Delete user-2 from the in-memory DB before building the widget.
        await db.value.usersDao.deleteById('user-2');

        await tester.pumpWidget(buildHarness());
        await tester.pumpAndSettle();

        expect(find.text('Coach Diego'), findsOneWidget);
        expect(find.text('Coach Maria'), findsNothing);
        // Last-user message takes precedence over active-user message.
        expect(
          find.text('Add another user before deleting the last one'),
          findsOneWidget,
        );
      },
    );
  });
}
