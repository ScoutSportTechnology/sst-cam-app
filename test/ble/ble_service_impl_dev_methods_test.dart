// Verifies that BleServiceImpl honors the new BleService surface (users +
// streaming destinations) by delegating to DevDataStore when
// `kAppEnv.isMock == true`. Non-mock branches throw `StateError` with a
// "Phase 7" label; that path can't be exercised at runtime because
// `kAppEnv` is a compile-time constant baked in via `--dart-define`. The
// test runner default leaves `APP_ENV` unset, so `kAppEnv.isMock` is true
// here and we exercise the mock branch end-to-end. Coverage of the
// non-mock branch is asserted by the source-text grep checks documented in
// U4's verification step.

import 'package:flutter_test/flutter_test.dart';
import 'package:scout_camera/ble/ble_service_impl.dart';
import 'package:scout_camera/ble/dev_data_store.dart';
import 'package:scout_camera/ble/mock_ble_service.dart';
import 'package:scout_camera/env.dart';
import 'package:scout_camera/models/streaming.dart';
import 'package:scout_camera/models/user.dart';

import '../test_helpers.dart';

void main() {
  // Reset the process-global DevDataStore between every test so the
  // shared store can't leak data across cases.
  useDevDataStoreReset();

  const deviceId = 'cam-1';

  test('test runner is in mock env (kAppEnv.isMock == true)', () {
    // Documents the env precondition for every other test in this file:
    // without `--dart-define=APP_ENV=...`, `kAppEnv` defaults to devMock,
    // so the mock branch of every gated method is the path under test.
    expect(kAppEnv.isMock, isTrue);
  });

  group('BleServiceImpl — users (mock env, delegates to DevDataStore)', () {
    test('createUser round-trips through listUsers', () async {
      final svc = BleServiceImpl();

      final created = await svc.createUser(
        deviceId,
        const UserDraft(name: 'Coach C'),
      );

      expect(created, isA<UserRecord>());
      expect(created.name, 'Coach C');

      final users = await svc.listUsers(deviceId);
      expect(users.map((u) => u.id), contains(created.id));
      expect(users.firstWhere((u) => u.id == created.id).name, 'Coach C');
    });

    test('setActiveUser then getActiveUser returns the new id', () async {
      final svc = BleServiceImpl();

      // Seed has user-1 active and user-2 present.
      await svc.setActiveUser(deviceId, 'user-2');
      final active = await svc.getActiveUser(deviceId);

      expect(active, 'user-2');
    });

    test(
      'BleServiceImpl and MockBleService see the same DevDataStore',
      () async {
        final impl = BleServiceImpl();
        final mock = MockBleService(
          scanDeviceAppearDelays: const [Duration.zero, Duration.zero],
          connectionDelay: Duration.zero,
          failureRate: 0.0,
          randomSeed: 1,
        );

        try {
          // Write through the impl …
          final created = await impl.createUser(
            deviceId,
            const UserDraft(name: 'Coach Shared'),
          );

          // … read through the mock — same DevDataStore singleton.
          final usersFromMock = await mock.listUsers(deviceId);
          expect(usersFromMock.map((u) => u.id), contains(created.id));
          expect(
            usersFromMock.firstWhere((u) => u.id == created.id).name,
            'Coach Shared',
          );

          // And vice versa — write through the mock, read through the impl.
          final viaMock = await mock.createUser(
            deviceId,
            const UserDraft(name: 'Coach Mirror'),
          );
          final usersFromImpl = await impl.listUsers(deviceId);
          expect(usersFromImpl.map((u) => u.id), contains(viaMock.id));
        } finally {
          await mock.dispose();
        }
      },
    );

    test(
      'deleteUser of the active user surfaces DevDataStoreException',
      () async {
        final svc = BleServiceImpl();

        // Seed leaves user-1 active. The store guards against deleting the
        // active user; the gate evaluates true and the typed exception
        // bubbles out instead of being swallowed.
        await expectLater(
          () => svc.deleteUser(deviceId, 'user-1'),
          throwsA(isA<DevDataStoreException>()),
        );
      },
    );
  });

  group(
    'BleServiceImpl — streaming destinations (mock env, delegates to DevDataStore)',
    () {
      test(
        'createStreamingDestination round-trips through listStreamingDestinations',
        () async {
          final svc = BleServiceImpl();

          // Seed user-1 starts with no destinations.
          const draft = StreamingDestinationDraft(
            name: 'Match Stream',
            provider: StreamingProvider.youtube,
            protocol: StreamingProtocol.rtmp,
            config: RtmpConfig(
              url: 'rtmp://a.rtmp.youtube.com/live2',
              streamKey: 'abcd-efgh-ijkl-mnop',
            ),
          );

          final created = await svc.createStreamingDestination(
            deviceId,
            'user-1',
            draft,
          );
          expect(created.name, 'Match Stream');
          expect(created.provider, StreamingProvider.youtube);

          final list = await svc.listStreamingDestinations(deviceId, 'user-1');
          expect(list.map((d) => d.id), contains(created.id));
          expect(
            list.firstWhere((d) => d.id == created.id).config,
            isA<RtmpConfig>(),
          );
        },
      );

      test(
        'BleServiceImpl and MockBleService see the same destinations',
        () async {
          final impl = BleServiceImpl();
          final mock = MockBleService(
            scanDeviceAppearDelays: const [Duration.zero, Duration.zero],
            connectionDelay: Duration.zero,
            failureRate: 0.0,
            randomSeed: 1,
          );

          try {
            final created = await impl.createStreamingDestination(
              deviceId,
              'user-1',
              const StreamingDestinationDraft(
                name: 'Backyard Cam',
                provider: StreamingProvider.custom,
                protocol: StreamingProtocol.rtsp,
                config: RtspConfig(url: 'rtsp://192.168.1.7/stream'),
              ),
            );

            final viaMock = await mock.listStreamingDestinations(
              deviceId,
              'user-1',
            );
            expect(viaMock.map((d) => d.id), contains(created.id));
            expect(
              viaMock.firstWhere((d) => d.id == created.id).protocol,
              StreamingProtocol.rtsp,
            );
          } finally {
            await mock.dispose();
          }
        },
      );
    },
  );
}
