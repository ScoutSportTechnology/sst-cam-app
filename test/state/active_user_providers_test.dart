// Verifies the active-user state machine on the Riverpod side:
//
//   * `usersControllerProvider` returns the seed users from Drift.
//   * `setActive(userId)` updates `activeUserProvider` and persists to
//     SharedPreferences.
//   * `create(name)` inserts a user into Drift and auto-activates the first.
//   * Switching `activeUserProvider` causes `streamingDestinationsController`
//     to refetch with the right scope.
//   * Edge cases: no active user, delete pre-checks.
//
// SharedPreferences is mocked with `setMockInitialValues`.
// Drift is backed by a fresh in-memory DB per test via `useInMemoryDb()`.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scout_camera/ble/mock_ble_service.dart';
import 'package:scout_camera/state/app_data.dart';
import 'package:scout_camera/state/ble_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers.dart';

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

      await container.read(usersControllerProvider.notifier).setActive('user-2');

      expect(container.read(activeUserProvider), 'user-2');
    });

    test('setActive persists to SharedPreferences', () async {
      final container = makeContainer();
      await container.read(usersControllerProvider.future);

      await container.read(usersControllerProvider.notifier).setActive('user-2');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('active_user_id'), 'user-2');
    });

    test('build() hydrates activeUserProvider from SharedPreferences', () async {
      // Pre-populate SharedPreferences with user-2 as the active user.
      SharedPreferences.setMockInitialValues({'active_user_id': 'user-2'});

      final container = makeContainer();
      await container.read(usersControllerProvider.future);

      expect(container.read(activeUserProvider), 'user-2');
    });
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

    test(
      'with activeUserProvider null, returns empty',
      () async {
        final container = makeContainer(activeUserId: null);

        final list = await container.read(
          streamingDestinationsControllerProvider.future,
        );
        expect(list, isEmpty);
        expect(container.read(activeUserProvider), isNull);
      },
    );
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
