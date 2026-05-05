import 'package:flutter_test/flutter_test.dart';
import 'package:scout_camera/ble/dev_data_store.dart';
import 'package:scout_camera/models/sport_preset.dart';
import 'package:scout_camera/models/streaming.dart';
import 'package:scout_camera/models/team.dart';
import 'package:scout_camera/models/user.dart';

void main() {
  // This test owns its own setUp — it exercises reset() directly and so
  // does NOT use the shared `useDevDataStoreReset()` harness.
  setUp(() {
    DevDataStore.instance.reset();
  });

  final store = DevDataStore.instance;

  group('seed', () {
    test('listUsers returns Coach Diego and Coach Maria', () {
      final users = store.listUsers();
      expect(users, hasLength(2));
      expect(users.map((u) => u.name), ['Coach Diego', 'Coach Maria']);
      expect(users.map((u) => u.id), ['user-1', 'user-2']);
    });

    test('getActiveUser returns user-1 after reset', () {
      expect(store.getActiveUser(), 'user-1');
    });

    test('listTeams is scoped per user', () {
      expect(store.listTeams('user-1'), hasLength(4));
      expect(store.listTeams('user-2'), isEmpty);
    });

    test('listSportPresets gives both users all 7 built-ins', () {
      final p1 = store.listSportPresets('user-1');
      final p2 = store.listSportPresets('user-2');
      expect(p1, hasLength(7));
      expect(p2, hasLength(7));
      expect(p1.every((p) => p.builtIn), isTrue);
      expect(p2.every((p) => p.builtIn), isTrue);
    });

    test('every kSports value has at least one built-in default', () {
      final presets = store.listSportPresets('user-1');
      for (final sport in kSports) {
        final hasBuiltIn = presets.any((p) => p.sport == sport && p.builtIn);
        expect(
          hasBuiltIn,
          isTrue,
          reason: 'No built-in preset seeded for "$sport"',
        );
      }
    });

    test('seed team matches live under user-1 / nr-u14', () {
      expect(store.listTeamMatches('user-1', 'nr-u14'), hasLength(5));
      expect(store.listTeamMatches('user-1', 'nr-u12'), isEmpty);
      expect(store.listTeamMatches('user-2', 'nr-u14'), isEmpty);
    });
  });

  group('user CRUD', () {
    test('setActiveUser to user-2 updates getActiveUser', () {
      store.setActiveUser('user-2');
      expect(store.getActiveUser(), 'user-2');
    });

    test('createUser appends and does not change active user', () {
      final created = store.createUser(const UserDraft(name: 'Coach C'));
      expect(created.name, 'Coach C');
      expect(store.listUsers(), hasLength(3));
      expect(store.getActiveUser(), 'user-1');
    });

    test('createUser seeds built-ins for the new user', () {
      final created = store.createUser(const UserDraft(name: 'Coach C'));
      expect(store.listSportPresets(created.id), hasLength(7));
      expect(store.listTeams(created.id), isEmpty);
      expect(store.listStreamingDestinations(created.id), isEmpty);
    });

    test('updateUser changes the name', () {
      final user = store.listUsers().first;
      final updated = store.updateUser(
        UserDraft(id: user.id, name: 'Diego Sr.'),
      );
      expect(updated.name, 'Diego Sr.');
      expect(store.listUsers().first.name, 'Diego Sr.');
    });

    test('updateUser with empty id throws', () {
      expect(
        () => store.updateUser(const UserDraft(name: 'X')),
        throwsA(isA<DevDataStoreException>()),
      );
    });

    test('setActiveUser with non-existent id throws', () {
      expect(
        () => store.setActiveUser('user-bogus'),
        throwsA(isA<DevDataStoreException>()),
      );
    });

    test('deleteUser of the active user throws', () {
      expect(
        () => store.deleteUser('user-1'),
        throwsA(isA<DevDataStoreException>()),
      );
    });

    test('deleteUser of the last remaining user throws', () {
      // Switch to user-2 so user-1 can be deleted.
      store.setActiveUser('user-2');
      store.deleteUser('user-1');
      expect(store.listUsers(), hasLength(1));
      // Now user-2 is the last; deleting it must fail.
      expect(
        () => store.deleteUser('user-2'),
        throwsA(isA<DevDataStoreException>()),
      );
    });
  });

  group('streaming destinations', () {
    test('createStreamingDestination is scoped to the user', () {
      store.setActiveUser('user-2');
      final dest = store.createStreamingDestination(
        'user-2',
        const StreamingDestinationDraft(
          name: 'My YT',
          provider: StreamingProvider.youtube,
          protocol: StreamingProtocol.rtmp,
          config: RtmpConfig(
            url: 'rtmp://a.rtmp.youtube.com/live2',
            streamKey: 'abc',
          ),
        ),
      );
      expect(dest.id, startsWith('dest-'));
      expect(store.listStreamingDestinations('user-2'), hasLength(1));
      expect(store.listStreamingDestinations('user-1'), isEmpty);
    });

    test('RtmpConfig round-trips through create + list', () {
      final draft = const StreamingDestinationDraft(
        name: 'Studio Backup',
        provider: StreamingProvider.custom,
        protocol: StreamingProtocol.rtmps,
        config: RtmpConfig(
          url: 'rtmps://stream.example.com/app',
          streamKey: 'sk-rtmps-1',
        ),
      );
      store.createStreamingDestination('user-1', draft);
      final back = store.listStreamingDestinations('user-1').single;
      expect(back.name, 'Studio Backup');
      expect(back.provider, StreamingProvider.custom);
      expect(back.protocol, StreamingProtocol.rtmps);
      expect(back.config, isA<RtmpConfig>());
      final cfg = back.config as RtmpConfig;
      expect(cfg.url, 'rtmps://stream.example.com/app');
      expect(cfg.streamKey, 'sk-rtmps-1');
    });

    test('RtspConfig round-trips with username only', () {
      store.createStreamingDestination(
        'user-1',
        const StreamingDestinationDraft(
          name: 'RTSP-A',
          provider: StreamingProvider.custom,
          protocol: StreamingProtocol.rtsp,
          config: RtspConfig(url: 'rtsp://a.example/live', username: 'u'),
        ),
      );
      final back = store.listStreamingDestinations('user-1').single;
      expect(back.config, isA<RtspConfig>());
      final cfg = back.config as RtspConfig;
      expect(cfg.username, 'u');
      expect(cfg.password, isNull);
    });

    test('RtspConfig round-trips with neither credential', () {
      store.createStreamingDestination(
        'user-1',
        const StreamingDestinationDraft(
          name: 'RTSP-B',
          provider: StreamingProvider.custom,
          protocol: StreamingProtocol.rtsp,
          config: RtspConfig(url: 'rtsp://b.example/live'),
        ),
      );
      final cfg =
          store.listStreamingDestinations('user-1').single.config as RtspConfig;
      expect(cfg.username, isNull);
      expect(cfg.password, isNull);
    });

    test('RtspConfig round-trips with both credentials', () {
      store.createStreamingDestination(
        'user-1',
        const StreamingDestinationDraft(
          name: 'RTSP-C',
          provider: StreamingProvider.custom,
          protocol: StreamingProtocol.rtsp,
          config: RtspConfig(
            url: 'rtsp://c.example/live',
            username: 'u',
            password: 'p',
          ),
        ),
      );
      final cfg =
          store.listStreamingDestinations('user-1').single.config as RtspConfig;
      expect(cfg.username, 'u');
      expect(cfg.password, 'p');
    });
  });

  group('sport presets', () {
    test('createSportPreset appends a custom preset for the user', () {
      final created = store.createSportPreset(
        'user-1',
        const SportPresetDraft(
          name: 'My Soccer',
          sport: 'Soccer',
          numPeriods: 2,
          periodLengthSeconds: 30 * 60,
        ),
      );
      expect(created.builtIn, isFalse);
      final list = store.listSportPresets('user-1');
      expect(list, hasLength(8));
      expect(list.last.name, 'My Soccer');
    });

    test('updateSportPreset on a built-in throws', () {
      final builtIn = store
          .listSportPresets('user-1')
          .firstWhere((p) => p.builtIn);
      expect(
        () => store.updateSportPreset(
          'user-1',
          SportPresetDraft(
            id: builtIn.id,
            name: 'Tampered',
            sport: builtIn.sport,
            numPeriods: builtIn.numPeriods,
            periodLengthSeconds: builtIn.periodLengthSeconds,
          ),
        ),
        throwsA(isA<DevDataStoreException>()),
      );
    });

    test('deleteSportPreset on a built-in throws', () {
      final builtIn = store
          .listSportPresets('user-1')
          .firstWhere((p) => p.builtIn);
      expect(
        () => store.deleteSportPreset('user-1', builtIn.id),
        throwsA(isA<DevDataStoreException>()),
      );
    });
  });

  group('cascade delete', () {
    test('deleting a user drops teams, matches, presets, destinations and '
        'leaves other users intact', () {
      // Populate user-1 beyond the seed.
      store.createSportPreset(
        'user-1',
        const SportPresetDraft(
          name: 'Custom 1',
          sport: 'Soccer',
          numPeriods: 2,
          periodLengthSeconds: 40 * 60,
        ),
      );
      store.createStreamingDestination(
        'user-1',
        const StreamingDestinationDraft(
          name: 'D1',
          provider: StreamingProvider.youtube,
          protocol: StreamingProtocol.rtmp,
          config: RtmpConfig(url: 'rtmp://x', streamKey: 'k1'),
        ),
      );
      store.createStreamingDestination(
        'user-1',
        const StreamingDestinationDraft(
          name: 'D2',
          provider: StreamingProvider.tiktok,
          protocol: StreamingProtocol.rtmp,
          config: RtmpConfig(url: 'rtmp://y', streamKey: 'k2'),
        ),
      );
      store.createStreamingDestination(
        'user-1',
        const StreamingDestinationDraft(
          name: 'D3',
          provider: StreamingProvider.custom,
          protocol: StreamingProtocol.rtsp,
          config: RtspConfig(url: 'rtsp://z'),
        ),
      );

      // Sanity: user-1 has stuff.
      expect(store.listTeams('user-1'), isNotEmpty);
      expect(store.listTeamMatches('user-1', 'nr-u14'), isNotEmpty);
      expect(store.listSportPresets('user-1'), hasLength(8));
      expect(store.listStreamingDestinations('user-1'), hasLength(3));

      // Switch active so user-1 can be deleted.
      store.setActiveUser('user-2');
      store.deleteUser('user-1');

      // Every user-1 collection is gone.
      expect(store.listTeams('user-1'), isEmpty);
      expect(store.listTeamMatches('user-1', 'nr-u14'), isEmpty);
      expect(store.listSportPresets('user-1'), isEmpty);
      expect(store.listStreamingDestinations('user-1'), isEmpty);

      // Users list no longer contains user-1.
      final remaining = store.listUsers().map((u) => u.id);
      expect(remaining, isNot(contains('user-1')));
      expect(remaining, contains('user-2'));

      // user-2 unaffected.
      expect(store.listSportPresets('user-2'), hasLength(7));
    });
  });
}
