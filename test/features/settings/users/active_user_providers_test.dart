// Verifies the active-user state machine on the Riverpod side:
//
//   * `usersControllerProvider` returns the seed users from Drift.
//   * `setActive(userId)` updates `activeUserProvider` and persists to
//     SharedPreferences.
//   * `create(name)` inserts a user into Drift and auto-activates the first.
//   * Switching `activeUserProvider` causes `streamingDestinationsController`
//     to refetch with the right scope.
//   * Edge cases: no active user, delete pre-checks.
//   * `teamsControllerProvider` reads from Drift without a camera connection.
//   * `upcomingMatchesProvider` returns data without a camera connection.
//
// SharedPreferences is mocked with `setMockInitialValues`.
// Drift is backed by a fresh in-memory DB per test via `useInMemoryDb()`.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sst_cam_app/mock/emulator/mock_ble_service.dart';
import 'package:sst_cam_app/features/camera/camera_state.dart'
    show activeCameraIdProvider;
import 'package:sst_cam_app/features/match/match_state.dart'
    show upcomingMatchesProvider, UpcomingMatch;
import 'package:sst_cam_app/features/settings/streaming/streaming_state.dart'
    show
        streamingDestinationsControllerProvider,
        StreamingDestinationDraft,
        StreamingProvider,
        StreamingProtocol,
        RtmpConfig;
import 'package:sst_cam_app/features/settings/users/users_state.dart'
    show activeUserProvider, usersControllerProvider, UsersControllerException;
import 'package:sst_cam_app/features/teams/teams_state.dart'
    show teamsControllerProvider, MatchKind;
import 'package:sst_cam_app/core/ble/ble_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../test_helpers.dart';

MockBleService _newMock() => MockBleService(
  scanDeviceAppearDelays: const [Duration.zero, Duration.zero],
  connectionDelay: Duration.zero,
  failureRate: 0.0,
  randomSeed: 7,
);

void main() {
  // Drift in-memory DB — seeded with user-1 / user-2 + teams.
  final db = useInMemoryDb();

  // Reset SharedPreferences before every test so active_user_id never leaks.
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  ProviderContainer makeContainer({
    String? cameraId = 'SST-CAM-001',
    String? activeUserId,
    MockBleService? service,
  }) {
    final svc = service ?? _newMock();
    final container = ProviderContainer(
      overrides: [
        ...dbOverrides(db),
        bleServiceProvider.overrideWithValue(svc),
        if (activeUserId != null)
          activeUserProvider.overrideWith((_) => activeUserId),
      ],
    );
    if (cameraId != null) {
      container.read(activeCameraIdProvider.notifier).state = cameraId;
    }
    addTearDown(container.dispose);
    return container;
  }

  group('UsersController — seed + setActive', () {
    test('returns the two seed users (Coach Diego, Coach Maria)', () async {
      final container = makeContainer();
      final users = await container.read(usersControllerProvider.future);
      expect(users, hasLength(2));
      expect(
        users.map((u) => u.name),
        containsAll(['Coach Diego', 'Coach Maria']),
      );
    });

    test('setActive(user-2) updates activeUserProvider', () async {
      final container = makeContainer();
      await container.read(usersControllerProvider.future);

      await container
          .read(usersControllerProvider.notifier)
          .setActive('user-2');

      expect(container.read(activeUserProvider), 'user-2');
    });

    test('setActive persists to SharedPreferences', () async {
      final container = makeContainer();
      await container.read(usersControllerProvider.future);

      await container
          .read(usersControllerProvider.notifier)
          .setActive('user-2');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('active_user_id'), 'user-2');
    });

    test(
      'build() hydrates activeUserProvider from SharedPreferences',
      () async {
        // Pre-populate SharedPreferences with user-2 as the active user.
        SharedPreferences.setMockInitialValues({'active_user_id': 'user-2'});

        final container = makeContainer();
        await container.read(usersControllerProvider.future);

        expect(container.read(activeUserProvider), 'user-2');
      },
    );

    test(
      'build() auto-selects the sole user when SharedPreferences is empty',
      () async {
        // SharedPreferences is empty (set in setUp), DB has two seed users.
        // Delete user-2 so only one remains, then verify auto-selection fires.
        final container = makeContainer(activeUserId: 'user-1');
        await container.read(usersControllerProvider.future);
        await container.read(usersControllerProvider.notifier).delete('user-2');
        await Future<void>.delayed(Duration.zero);

        // Now build a fresh container with no activeUserId override and empty prefs.
        final fresh = ProviderContainer(
          overrides: [
            ...dbOverrides(db),
            bleServiceProvider.overrideWithValue(_newMock()),
          ],
        );
        addTearDown(fresh.dispose);

        await fresh.read(usersControllerProvider.future);

        // The sole remaining user should have been auto-activated.
        expect(fresh.read(activeUserProvider), 'user-1');
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('active_user_id'), 'user-1');
      },
    );
  });

  group('create(name)', () {
    test('create inserts user into Drift and returns UserRecord', () async {
      final container = makeContainer(activeUserId: 'user-1');
      await container.read(usersControllerProvider.future);

      final created = await container
          .read(usersControllerProvider.notifier)
          .create('Coach C');
      expect(created.name, 'Coach C');

      final users = await container.read(usersControllerProvider.future);
      expect(users.map((u) => u.name), contains('Coach C'));
    });
  });

  group('streamingDestinationsController', () {
    test(
      'returns active user\'s destinations; switching user returns empty',
      () async {
        final container = makeContainer(activeUserId: 'user-1');
        await container.read(usersControllerProvider.future);

        // Create a destination for user-1.
        final dest = await container
            .read(streamingDestinationsControllerProvider.notifier)
            .create(
              const StreamingDestinationDraft(
                name: 'YT',
                provider: StreamingProvider.youtube,
                protocol: StreamingProtocol.rtmp,
                config: RtmpConfig(
                  url: 'rtmp://a.rtmp.youtube.com/live2',
                  streamKey: 'k',
                ),
              ),
            );
        expect(dest.name, 'YT');

        // Allow the Drift watch stream to propagate the insert.
        await Future<void>.delayed(Duration.zero);

        var list = await container.read(
          streamingDestinationsControllerProvider.future,
        );
        expect(list, hasLength(1));
        expect(list.first.name, 'YT');

        // Switch to user-2 — they have nothing.
        await container
            .read(usersControllerProvider.notifier)
            .setActive('user-2');
        list = await container.read(
          streamingDestinationsControllerProvider.future,
        );
        expect(list, isEmpty);
      },
    );

    test('with activeUserProvider null, returns empty', () async {
      final container = makeContainer(activeUserId: null);

      final list = await container.read(
        streamingDestinationsControllerProvider.future,
      );
      expect(list, isEmpty);
      expect(container.read(activeUserProvider), isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // TeamsController — Drift-backed (U5)
  // ---------------------------------------------------------------------------

  group('teamsControllerProvider', () {
    test(
      'returns seeded teams for user-1 without a camera connection',
      () async {
        // No activeCameraIdProvider override → it starts null.
        final container = ProviderContainer(
          overrides: [
            ...dbOverrides(db),
            bleServiceProvider.overrideWithValue(_newMock()),
            activeUserProvider.overrideWith((_) => 'user-1'),
          ],
        );
        addTearDown(container.dispose);

        final teams = await container.read(teamsControllerProvider.future);
        // Seed has 4 teams under user-1.
        expect(teams, hasLength(4));
        expect(teams.map((t) => t.id), contains('nr-u14'));
        // activeCameraIdProvider was never set — data still came through.
        expect(container.read(activeCameraIdProvider), isNull);
      },
    );

    test('returns empty list when activeUserProvider is null', () async {
      final container = ProviderContainer(
        overrides: [
          ...dbOverrides(db),
          bleServiceProvider.overrideWithValue(_newMock()),
        ],
      );
      addTearDown(container.dispose);

      final teams = await container.read(teamsControllerProvider.future);
      expect(teams, isEmpty);
    });

    test('returns empty for user-2 (no seed teams)', () async {
      final container = ProviderContainer(
        overrides: [
          ...dbOverrides(db),
          bleServiceProvider.overrideWithValue(_newMock()),
          activeUserProvider.overrideWith((_) => 'user-2'),
        ],
      );
      addTearDown(container.dispose);

      final teams = await container.read(teamsControllerProvider.future);
      expect(teams, isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // upcomingMatchesProvider — Drift-backed (U5 regression fix)
  // ---------------------------------------------------------------------------

  group('upcomingMatchesProvider', () {
    test(
      'returns upcoming matches without a camera connection (R2 fix)',
      () async {
        // No activeCameraIdProvider — must still return data.
        final container = ProviderContainer(
          overrides: [
            ...dbOverrides(db),
            bleServiceProvider.overrideWithValue(_newMock()),
            activeUserProvider.overrideWith((_) => 'user-1'),
          ],
        );
        addTearDown(container.dispose);

        // upcomingMatchesProvider is a StreamProvider — get first value.
        final upcoming = await container.read(upcomingMatchesProvider.future);
        // Seed has 2 upcoming matches on nr-u14 under user-1.
        expect(upcoming, hasLength(2));
        expect(
          upcoming.every((u) => u.match.kind == MatchKind.upcoming),
          isTrue,
        );
        // Confirmed: no camera needed.
        expect(container.read(activeCameraIdProvider), isNull);
      },
    );

    test('returns empty when activeUserProvider is null', () async {
      final container = ProviderContainer(
        overrides: [
          ...dbOverrides(db),
          bleServiceProvider.overrideWithValue(_newMock()),
        ],
      );
      addTearDown(container.dispose);

      final upcoming = await container.read(upcomingMatchesProvider.future);
      expect(upcoming, isEmpty);
    });

    test('excludes matches for hidden teams', () async {
      final container = ProviderContainer(
        overrides: [
          ...dbOverrides(db),
          bleServiceProvider.overrideWithValue(_newMock()),
          activeUserProvider.overrideWith((_) => 'user-1'),
        ],
      );
      addTearDown(container.dispose);

      // Hide nr-u14 (the team with upcoming matches).
      await container
          .read(teamsControllerProvider.notifier)
          .setHidden('nr-u14', hidden: true);

      // Allow stream to propagate.
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final upcoming = await container.read(upcomingMatchesProvider.future);
      // All upcoming matches belonged to nr-u14 — now hidden.
      expect(upcoming, isEmpty);
    });

    test('re-emits when a team match row is inserted', () async {
      final container = ProviderContainer(
        overrides: [
          ...dbOverrides(db),
          bleServiceProvider.overrideWithValue(_newMock()),
          activeUserProvider.overrideWith((_) => 'user-1'),
        ],
      );
      addTearDown(container.dispose);

      // Collect emissions into a list.
      final emissions = <List<UpcomingMatch>>[];
      final sub = container.listen(upcomingMatchesProvider, (_, next) {
        if (next.hasValue) emissions.add(next.value!);
      });

      // Consume the initial emission (2 upcoming matches in seed data).
      final initial = await container.read(upcomingMatchesProvider.future);
      expect(initial, hasLength(2));
      emissions.clear();

      // Insert a new upcoming match for nr-u14.
      await db.value.teamsDao.insertTeamMatch(
        TeamMatchesTableCompanion.insert(
          id: 'nr-u14-up3',
          teamId: 'nr-u14',
          opponent: 'vs Hillside FC',
          date: 'May 25',
          result: '',
          kind: 'upcoming',
          numPeriods: 2,
          periodLengthSeconds: 35 * 60,
        ),
      );

      // Allow the Drift watch stream to propagate.
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final updated = await container.read(upcomingMatchesProvider.future);
      expect(updated, hasLength(3));
      sub.close();
    });

    test('re-emits when a team match row is deleted', () async {
      final container = ProviderContainer(
        overrides: [
          ...dbOverrides(db),
          bleServiceProvider.overrideWithValue(_newMock()),
          activeUserProvider.overrideWith((_) => 'user-1'),
        ],
      );
      addTearDown(container.dispose);

      // Confirm seed state: 2 upcoming matches.
      final initial = await container.read(upcomingMatchesProvider.future);
      expect(initial, hasLength(2));

      // Delete one upcoming match directly via the DAO.
      await db.value.teamsDao.deleteTeamMatch(seedMatchUp1Id);

      // Allow the Drift watch stream to propagate.
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final updated = await container.read(upcomingMatchesProvider.future);
      expect(updated, hasLength(1));
      expect(updated.first.match.id, seedMatchUp2Id);
    });
  });

  group('UsersController.delete pre-checks', () {
    test('delete(activeUserId) throws UsersControllerException', () async {
      final container = makeContainer(activeUserId: 'user-1');
      await container.read(usersControllerProvider.future);
      final ctrl = container.read(usersControllerProvider.notifier);

      await expectLater(
        ctrl.delete('user-1'),
        throwsA(isA<UsersControllerException>()),
      );

      // Both seed users are still present.
      final users = await container.read(usersControllerProvider.future);
      expect(users, hasLength(2));
      expect(users.map((u) => u.id), containsAll(['user-1', 'user-2']));
    });

    test(
      'delete on the last remaining user throws UsersControllerException',
      () async {
        final container = makeContainer(activeUserId: 'user-2');
        await container.read(usersControllerProvider.future);
        final ctrl = container.read(usersControllerProvider.notifier);

        // Delete user-1 (not active).
        await ctrl.delete('user-1');
        // Allow the Drift watch stream to propagate.
        await Future<void>.delayed(Duration.zero);

        var users = await container.read(usersControllerProvider.future);
        expect(users, hasLength(1));
        expect(users.first.id, 'user-2');

        // Now user-2 is the sole and active user — active-user check fires.
        await expectLater(
          ctrl.delete('user-2'),
          throwsA(isA<UsersControllerException>()),
        );

        users = await container.read(usersControllerProvider.future);
        expect(users, hasLength(1));
      },
    );
  });
}
