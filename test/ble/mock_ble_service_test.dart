import 'package:flutter_test/flutter_test.dart';
import 'package:scout_camera/ble/ble_service.dart';
import 'package:scout_camera/ble/dev_data_store.dart';
import 'package:scout_camera/ble/mock_ble_service.dart';
import 'package:scout_camera/models/command.dart';
import 'package:scout_camera/models/device.dart';
import 'package:scout_camera/models/recording.dart';
import 'package:scout_camera/models/sport_preset.dart';
import 'package:scout_camera/models/streaming.dart';
import 'package:scout_camera/models/team.dart';
import 'package:scout_camera/models/user.dart';

import '../test_helpers.dart';

void main() {
  // Reset the process-global DevDataStore between every test so the
  // retrofitted MockBleService can't leak data across cases.
  useDevDataStoreReset();

  late MockBleService svc;

  setUp(() {
    svc = MockBleService(
      scanDeviceAppearDelays: [Duration.zero, Duration.zero],
      connectionDelay: Duration.zero,
      failureRate: 0.0,
      randomSeed: 42,
    );
  });

  tearDown(() => svc.dispose());

  group('Discovery', () {
    test('starts with empty device list', () async {
      final devices = await svc.discoveredDevices.first;
      expect(devices, isEmpty);
    });

    test('emits devices progressively during scan', () async {
      final emitted = <List<ScoutDevice>>[];
      final sub = svc.discoveredDevices.listen(emitted.add);

      await svc.startScan(timeout: const Duration(seconds: 10));
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);

      await svc.stopScan();
      await sub.cancel();

      expect(emitted.any((l) => l.length == 2), isTrue);
    });

    test('device names follow sst-cam-#### convention', () async {
      final emitted = <List<ScoutDevice>>[];
      final sub = svc.discoveredDevices.listen(emitted.add);

      await svc.startScan();
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);
      await svc.stopScan();
      await sub.cancel();

      final devices = emitted.lastWhere((l) => l.isNotEmpty, orElse: () => []);
      for (final d in devices) {
        expect(d.name.toLowerCase(), startsWith('sst-cam-'));
      }
    });

    test('stopScan sets isScanning to false', () async {
      await svc.startScan();
      await svc.stopScan();
      expect(svc.isScanning, isFalse);
    });
  });

  group('Connection', () {
    test('connect emits connecting then connected', () async {
      const id = 'SST-CAM-001';
      final states = <CameraConnectionState>[];
      final sub = svc.connectionStateStream(id).listen(states.add);

      await svc.connect(id);
      await sub.cancel();

      expect(
        states,
        containsAllInOrder([
          CameraConnectionState.connecting,
          CameraConnectionState.connected,
        ]),
      );
    });

    test('disconnect emits disconnected', () async {
      const id = 'SST-CAM-001';
      await svc.connect(id);

      final states = <CameraConnectionState>[];
      final sub = svc.connectionStateStream(id).listen(states.add);
      await svc.disconnect(id);
      await sub.cancel();

      expect(states.last, CameraConnectionState.disconnected);
    });

    test('connect to unknown device throws BleConnectionException', () {
      expect(
        () => svc.connect('UNKNOWN-999'),
        throwsA(isA<BleConnectionException>()),
      );
    });
  });

  group('Telemetry', () {
    test('emits telemetry after connect', () async {
      const id = 'SST-CAM-001';
      await svc.connect(id);

      final telemetry = await svc.telemetryStream(id).first;
      expect(telemetry.storageTotalBytes, greaterThan(0));
      expect(telemetry.cpuUsedPct, inInclusiveRange(0.0, 1.0));
      expect(telemetry.ramUsedPct, inInclusiveRange(0.0, 1.0));
    });
  });

  group('Thumbnail', () {
    test('returns valid JPEG bytes', () async {
      const id = 'SST-CAM-001';
      await svc.connect(id);
      final result = await svc.requestThumbnail(id);

      expect(result.jpegBytes, isNotEmpty);
      expect(result.jpegBytes[0], 0xFF); // JPEG SOI
      expect(result.jpegBytes[1], 0xD8);
    });
  });

  group('Recordings', () {
    test('listRecordings returns non-empty list', () async {
      final recordings = await svc.listRecordings('SST-CAM-001');
      expect(recordings, isNotEmpty);
      for (final r in recordings) {
        expect(r.id, isNotEmpty);
        expect(r.durationSeconds, greaterThan(0));
      }
    });

    test('requestDownload returns valid non-expired token', () async {
      final token = await svc.requestDownload('SST-CAM-001', 'rec-001');
      expect(token.httpUrl, startsWith('http://'));
      expect(token.authToken, isNotEmpty);
      expect(token.isExpired, isFalse);
    });
  });

  group('Commands', () {
    test('GetTelemetryCommand returns telemetry payload', () async {
      final resp = await svc.sendCommand('SST-CAM-001', GetTelemetryCommand());
      expect(resp.isOk, isTrue);
      expect(resp.payload, isNotNull);
    });

    test('GetMatchStateCommand returns match state payload', () async {
      final resp = await svc.sendCommand('SST-CAM-001', GetMatchStateCommand());
      expect(resp.isOk, isTrue);
      expect(resp.payload, isNotNull);
    });

    test('ListRecordingsCommand returns recordings', () async {
      final resp = await svc.sendCommand<List<RecordingMetadata>>(
        'SST-CAM-001',
        ListRecordingsCommand(),
      );
      expect(resp.isOk, isTrue);
      expect(resp.payload, isNotEmpty);
    });

    test('DownloadRequestCommand returns token', () async {
      final resp = await svc.sendCommand<DownloadToken>(
        'SST-CAM-001',
        DownloadRequestCommand(recordingId: 'rec-001'),
      );
      expect(resp.isOk, isTrue);
      expect(resp.payload?.httpUrl, startsWith('http://'));
    });
  });

  group('Failure simulation', () {
    test('failureRate=1.0 always throws', () async {
      final failSvc = MockBleService(
        connectionDelay: Duration.zero,
        failureRate: 1.0,
        randomSeed: 0,
      );
      addTearDown(failSvc.dispose);

      expect(
        () => failSvc.connect('SST-CAM-001'),
        throwsA(isA<BleConnectionException>()),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Backwards-compat: existing per-active-user CRUD still works against the
  // seed data layout. user-1 is the seed-active user and owns the four seed
  // teams.
  // ---------------------------------------------------------------------------

  group('Teams (seed/regression guard)', () {
    test('listTeams returns 4 seed teams under the seed-active user', () async {
      final teams = await svc.listTeams('SST-CAM-001');
      expect(teams, hasLength(4));
    });

    test('listTeamMatches returns seed matches for nr-u14', () async {
      final matches = await svc.listTeamMatches('SST-CAM-001', 'nr-u14');
      expect(matches, isNotEmpty);
    });

    test('listSportPresets returns seeded built-ins for the active user',
        () async {
      final presets = await svc.listSportPresets('SST-CAM-001');
      expect(presets, isNotEmpty);
      expect(presets.every((p) => p.builtIn), isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // User CRUD via MockBleService — straight delegation to DevDataStore.
  // ---------------------------------------------------------------------------

  group('User CRUD', () {
    const deviceId = 'SST-CAM-001';

    test('listUsers returns the two seed users', () async {
      final users = await svc.listUsers(deviceId);
      expect(users.map((u) => u.name), containsAll(['Coach Diego', 'Coach Maria']));
      expect(users, hasLength(2));
    });

    test('createUser appends a third user', () async {
      final created = await svc.createUser(
        deviceId,
        const UserDraft(name: 'Coach Riley'),
      );
      expect(created.id, isNotEmpty);
      expect(created.name, 'Coach Riley');

      final users = await svc.listUsers(deviceId);
      expect(users, hasLength(3));
      expect(users.map((u) => u.name), contains('Coach Riley'));
    });

    test('updateUser renames an existing user', () async {
      final users = await svc.listUsers(deviceId);
      final first = users.first;
      final updated = await svc.updateUser(
        deviceId,
        UserDraft(id: first.id, name: 'Coach Renamed'),
      );
      expect(updated.id, first.id);
      expect(updated.name, 'Coach Renamed');
    });

    test('getActiveUser returns the seed-active user', () async {
      final activeId = await svc.getActiveUser(deviceId);
      expect(activeId, 'user-1');
    });

    test('setActiveUser switches active; listTeams reflects user-2 (empty)',
        () async {
      await svc.setActiveUser(deviceId, 'user-2');
      final activeId = await svc.getActiveUser(deviceId);
      expect(activeId, 'user-2');

      final teams = await svc.listTeams(deviceId);
      expect(teams, isEmpty);
    });

    test('deleteUser of the active user surfaces DevDataStoreException',
        () async {
      await expectLater(
        svc.deleteUser(deviceId, 'user-1'),
        throwsA(isA<DevDataStoreException>()),
      );
    });

    test('deleteUser of a non-active user removes them', () async {
      // user-1 is the seed-active. Delete user-2 (non-active).
      await svc.deleteUser(deviceId, 'user-2');
      final users = await svc.listUsers(deviceId);
      expect(users.map((u) => u.id), isNot(contains('user-2')));
      expect(users, hasLength(1));
    });

    test('setActiveUser to unknown id throws', () async {
      await expectLater(
        svc.setActiveUser(deviceId, 'no-such-user'),
        throwsA(isA<DevDataStoreException>()),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Streaming destinations — scoped by explicit userId.
  // ---------------------------------------------------------------------------

  group('Streaming destinations', () {
    const deviceId = 'SST-CAM-001';

    test('listStreamingDestinations is empty by default for both seed users',
        () async {
      expect(
        await svc.listStreamingDestinations(deviceId, 'user-1'),
        isEmpty,
      );
      expect(
        await svc.listStreamingDestinations(deviceId, 'user-2'),
        isEmpty,
      );
    });

    test('createStreamingDestination is scoped to its userId', () async {
      final created = await svc.createStreamingDestination(
        deviceId,
        'user-2',
        const StreamingDestinationDraft(
          name: 'Personal RTMP',
          provider: StreamingProvider.custom,
          protocol: StreamingProtocol.rtmp,
          config: RtmpConfig(url: 'rtmp://example.com/live', streamKey: 'sk'),
        ),
      );
      expect(created.id, isNotEmpty);

      final user2List =
          await svc.listStreamingDestinations(deviceId, 'user-2');
      expect(user2List, hasLength(1));
      expect(user2List.first.name, 'Personal RTMP');

      final user1List =
          await svc.listStreamingDestinations(deviceId, 'user-1');
      expect(user1List, isEmpty);
    });

    test('updateStreamingDestination changes name in place', () async {
      final created = await svc.createStreamingDestination(
        deviceId,
        'user-1',
        const StreamingDestinationDraft(
          name: 'YT',
          provider: StreamingProvider.youtube,
          protocol: StreamingProtocol.rtmp,
          config: RtmpConfig(url: 'rtmp://a.rtmp.youtube.com/live2', streamKey: 'k'),
        ),
      );
      final updated = await svc.updateStreamingDestination(
        deviceId,
        'user-1',
        StreamingDestinationDraft(
          id: created.id,
          name: 'YT Renamed',
          provider: StreamingProvider.youtube,
          protocol: StreamingProtocol.rtmp,
          config: const RtmpConfig(
            url: 'rtmp://a.rtmp.youtube.com/live2',
            streamKey: 'k',
          ),
        ),
      );
      expect(updated.name, 'YT Renamed');
    });

    test('deleteStreamingDestination removes the entry', () async {
      final created = await svc.createStreamingDestination(
        deviceId,
        'user-1',
        const StreamingDestinationDraft(
          name: 'TT',
          provider: StreamingProvider.tiktok,
          protocol: StreamingProtocol.rtmp,
          config: RtmpConfig(url: 'rtmp://tiktok.example/live', streamKey: 'sk'),
        ),
      );
      await svc.deleteStreamingDestination(deviceId, 'user-1', created.id);

      final list = await svc.listStreamingDestinations(deviceId, 'user-1');
      expect(list, isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // Cascade-delete through the public service API.
  //
  // Populate user-1 with extra data via the public API, then switch active
  // to user-2 and delete user-1. Verify all four user-1 collections are gone
  // by probing DevDataStore.instance directly (the public BleService API
  // can't read another user's teams/presets/matches in the current shape).
  // ---------------------------------------------------------------------------

  group('Cascade through public API', () {
    const deviceId = 'SST-CAM-001';

    test('deleteUser cascades teams, matches, presets, destinations',
        () async {
      // user-1 starts with seed data already. Add more via the public API.
      final newTeam = await svc.createTeam(
        deviceId,
        const TeamDraft(
          name: 'Public Tigers',
          shortName: 'PTG',
          sport: 'Soccer',
        ),
      );
      await svc.createSportPreset(
        deviceId,
        const SportPresetDraft(
          name: 'My Preset',
          sport: 'Soccer',
          numPeriods: 2,
          periodLengthSeconds: 30 * 60,
        ),
      );
      await svc.createStreamingDestination(
        deviceId,
        'user-1',
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

      // Sanity: user-1 has data right now via DevDataStore probe.
      expect(
        DevDataStore.instance.listTeams('user-1'),
        contains(newTeam),
      );

      // Switch active to user-2, then delete user-1.
      await svc.setActiveUser(deviceId, 'user-2');
      await svc.deleteUser(deviceId, 'user-1');

      // Every user-1 collection should be empty / cleared in the store.
      expect(DevDataStore.instance.listTeams('user-1'), isEmpty);
      expect(
        DevDataStore.instance.listTeamMatches('user-1', 'nr-u14'),
        isEmpty,
      );
      expect(DevDataStore.instance.listSportPresets('user-1'), isEmpty);
      expect(
        DevDataStore.instance.listStreamingDestinations('user-1'),
        isEmpty,
      );

      // user-1 is gone from the user list.
      final users = await svc.listUsers(deviceId);
      expect(users.map((u) => u.id), isNot(contains('user-1')));
    });
  });
}
