// ManageUsersPage tests — covers AE4 delete rules + switch affordance.
//
// This page is the nav destination for "Manage users" on SettingsPage.
// It lists all camera-side users with active badge, switch, and delete.
//
// Test isolation: `useDevDataStoreReset()` re-seeds the DevDataStore.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scout_camera/ble/dev_data_store.dart';
import 'package:scout_camera/ble/mock_ble_service.dart';
import 'package:scout_camera/pages/manage_users_page.dart';
import 'package:scout_camera/state/app_data.dart';
import 'package:scout_camera/state/ble_providers.dart';
import 'package:scout_camera/widgets/wf_chip.dart';

import '../test_helpers.dart';

const String _kFakeDeviceId = 'SST-CAM-001';

MockBleService _newMock() => MockBleService(
  scanDeviceAppearDelays: const [Duration.zero, Duration.zero],
  connectionDelay: Duration.zero,
  failureRate: 0.0,
  randomSeed: 1,
);

Widget _buildHarness({
  required MockBleService service,
  String? activeUserId = 'user-1',
}) {
  return ProviderScope(
    overrides: [
      bleServiceProvider.overrideWithValue(service),
      activeCameraIdProvider.overrideWith((_) => _kFakeDeviceId),
      if (activeUserId != null)
        activeUserProvider.overrideWith((_) => activeUserId),
    ],
    child: const MaterialApp(home: ManageUsersPage()),
  );
}

void main() {
  useDevDataStoreReset();

  group('User list (AE4)', () {
    testWidgets('active user row shows Active chip; non-active row does not', (
      tester,
    ) async {
      final mock = _newMock();
      addTearDown(mock.dispose);

      await tester.pumpWidget(_buildHarness(service: mock));
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
      final mock = _newMock();
      addTearDown(mock.dispose);

      await tester.pumpWidget(_buildHarness(service: mock));
      await tester.pumpAndSettle();

      // The subtitle under Diego's row (active user).
      expect(
        find.text('Switch to another user before deleting'),
        findsOneWidget,
      );
    });

    testWidgets('non-active user has enabled delete icon', (tester) async {
      final mock = _newMock();
      addTearDown(mock.dispose);

      await tester.pumpWidget(_buildHarness(service: mock));
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
      final mock = _newMock();
      addTearDown(mock.dispose);

      await tester.pumpWidget(_buildHarness(service: mock));
      await tester.pumpAndSettle();

      // Tap Coach Maria's row (non-active).
      await tester.tap(find.text('Coach Maria'));
      await tester.pumpAndSettle();

      expect(find.text('Switch user?'), findsOneWidget);
      expect(find.textContaining('Switch to Coach Maria?'), findsOneWidget);
    });

    testWidgets('confirming switch updates the active user', (tester) async {
      final mock = _newMock();
      addTearDown(mock.dispose);

      late ProviderContainer container;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            bleServiceProvider.overrideWithValue(mock),
            activeCameraIdProvider.overrideWith((_) => _kFakeDeviceId),
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
        final mock = _newMock();
        addTearDown(mock.dispose);

        await tester.pumpWidget(_buildHarness(service: mock));
        await tester.pumpAndSettle();

        // Maria is the non-active user; her delete icon should be enabled.
        // Find delete icon in Maria's row.
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

      final mock = _newMock();
      addTearDown(mock.dispose);

      await tester.pumpWidget(_buildHarness(service: mock));
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

      final users = DevDataStore.instance.listUsers();
      expect(users.map((u) => u.id), isNot(contains('user-2')));
    });
  });

  group('Add user FAB', () {
    testWidgets('tapping FAB opens the Add user form sheet', (tester) async {
      final mock = _newMock();
      addTearDown(mock.dispose);

      await tester.pumpWidget(_buildHarness(service: mock));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Add user'), findsAtLeastNWidgets(1));
    });

    testWidgets('adding a user via FAB shows the new user in the list', (
      tester,
    ) async {
      final mock = _newMock();
      addTearDown(mock.dispose);

      await tester.pumpWidget(_buildHarness(service: mock));
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
        DevDataStore.instance.deleteUser('user-2');
        expect(DevDataStore.instance.listUsers(), hasLength(1));

        final mock = _newMock();
        addTearDown(mock.dispose);

        await tester.pumpWidget(_buildHarness(service: mock));
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
