import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sst_cam_app/core/db/app_database.dart';
import 'package:sst_cam_app/core/db/daos/streaming_destinations_dao.dart';
import 'package:sst_cam_app/core/models/streaming.dart';
import 'package:uuid/uuid.dart';

void main() {
  late AppDatabase db;
  late String userId;

  setUp(() async {
    db = AppDatabase.forTesting(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    userId = const Uuid().v4();
    await db.usersDao.insertUser(
      UsersTableCompanion.insert(id: userId, name: 'Coach Diego'),
    );
  });

  tearDown(() => db.close());

  // ---------------------------------------------------------------------------
  // RTMP round-trip
  // ---------------------------------------------------------------------------

  test(
    'RTMP destination round-trip: configFromRow returns RtmpConfig',
    () async {
      final id = const Uuid().v4();
      await db.streamingDestinationsDao.insertDestination(
        StreamingDestinationsTableCompanion.insert(
          id: id,
          userId: userId,
          name: 'YouTube Live',
          provider: 'youtube',
          protocol: 'rtmp',
          configType: 'rtmp',
          configUrl: 'rtmp://a.rtmp.youtube.com/live2',
          configStreamKey: const Value('stream-key-abc'),
        ),
      );

      final rows = await db.streamingDestinationsDao.getForUser(userId);
      expect(rows, hasLength(1));

      final config = StreamingDestinationsDao.configFromRow(rows.first);
      expect(config, isA<RtmpConfig>());
      final rtmp = config as RtmpConfig;
      expect(rtmp.url, 'rtmp://a.rtmp.youtube.com/live2');
      expect(rtmp.streamKey, 'stream-key-abc');
    },
  );

  // ---------------------------------------------------------------------------
  // RTSP round-trip
  // ---------------------------------------------------------------------------

  test(
    'RTSP destination round-trip: configFromRow returns RtspConfig',
    () async {
      final id = const Uuid().v4();
      await db.streamingDestinationsDao.insertDestination(
        StreamingDestinationsTableCompanion.insert(
          id: id,
          userId: userId,
          name: 'Custom RTSP',
          provider: 'custom',
          protocol: 'rtsp',
          configType: 'rtsp',
          configUrl: 'rtsp://192.168.1.100:8554/stream',
          configUsername: const Value('admin'),
          configPassword: const Value('secret'),
        ),
      );

      final rows = await db.streamingDestinationsDao.getForUser(userId);
      final config = StreamingDestinationsDao.configFromRow(rows.first);

      expect(config, isA<RtspConfig>());
      final rtsp = config as RtspConfig;
      expect(rtsp.url, 'rtsp://192.168.1.100:8554/stream');
      expect(rtsp.username, 'admin');
      expect(rtsp.password, 'secret');
    },
  );

  test('RTSP without credentials: username and password are null', () async {
    final id = const Uuid().v4();
    await db.streamingDestinationsDao.insertDestination(
      StreamingDestinationsTableCompanion.insert(
        id: id,
        userId: userId,
        name: 'Open RTSP',
        provider: 'custom',
        protocol: 'rtsp',
        configType: 'rtsp',
        configUrl: 'rtsp://open.example.com/stream',
      ),
    );

    final rows = await db.streamingDestinationsDao.getForUser(userId);
    final config = StreamingDestinationsDao.configFromRow(rows.first);
    final rtsp = config as RtspConfig;
    expect(rtsp.username, isNull);
    expect(rtsp.password, isNull);
  });

  // ---------------------------------------------------------------------------
  // configFromRow with unknown configType
  // ---------------------------------------------------------------------------

  test('configFromRow with unknown configType throws StateError', () async {
    final id = const Uuid().v4();
    // Insert a row with a bad configType directly via raw SQL to bypass DAO
    // validation — simulates a future schema migration scenario.
    await db.streamingDestinationsDao.insertDestination(
      StreamingDestinationsTableCompanion.insert(
        id: id,
        userId: userId,
        name: 'Bad Config',
        provider: 'custom',
        protocol: 'rtmp',
        configType: 'unknown_type',
        configUrl: 'rtmp://example.com/live',
      ),
    );

    final rows = await db.streamingDestinationsDao.getForUser(userId);
    expect(
      () => StreamingDestinationsDao.configFromRow(rows.first),
      throwsA(isA<StateError>()),
    );
  });

  // ---------------------------------------------------------------------------
  // watchForUser scoping
  // ---------------------------------------------------------------------------

  test('watchForUser only returns destinations for that user', () async {
    final otherUserId = const Uuid().v4();
    await db.usersDao.insertUser(
      UsersTableCompanion.insert(id: otherUserId, name: 'Coach Maria'),
    );

    await db.streamingDestinationsDao.insertDestination(
      StreamingDestinationsTableCompanion.insert(
        id: const Uuid().v4(),
        userId: userId,
        name: 'Dest for user 1',
        provider: 'youtube',
        protocol: 'rtmp',
        configType: 'rtmp',
        configUrl: 'rtmp://a.rtmp.youtube.com/live2',
        configStreamKey: const Value('key1'),
      ),
    );
    await db.streamingDestinationsDao.insertDestination(
      StreamingDestinationsTableCompanion.insert(
        id: const Uuid().v4(),
        userId: otherUserId,
        name: 'Dest for user 2',
        provider: 'tiktok',
        protocol: 'rtmp',
        configType: 'rtmp',
        configUrl: 'rtmp://push.tiktok.com/live',
        configStreamKey: const Value('key2'),
      ),
    );

    final dests = await db.streamingDestinationsDao.watchForUser(userId).first;
    expect(dests, hasLength(1));
    expect(dests.first.name, 'Dest for user 1');
  });

  test('watchForUser with no rows emits empty list', () async {
    final result = await db.streamingDestinationsDao.watchForUser(userId).first;
    expect(result, isEmpty);
  });

  // ---------------------------------------------------------------------------
  // deleteById
  // ---------------------------------------------------------------------------

  test('deleteById removes destination', () async {
    final id = const Uuid().v4();
    await db.streamingDestinationsDao.insertDestination(
      StreamingDestinationsTableCompanion.insert(
        id: id,
        userId: userId,
        name: 'To Delete',
        provider: 'custom',
        protocol: 'rtmp',
        configType: 'rtmp',
        configUrl: 'rtmp://delete.me/live',
        configStreamKey: const Value('test-stream-key'),
      ),
    );

    await db.streamingDestinationsDao.deleteById(id);

    final dests = await db.streamingDestinationsDao.getForUser(userId);
    expect(dests, isEmpty);
  });

  // ---------------------------------------------------------------------------
  // updateDestination
  // ---------------------------------------------------------------------------

  test('updateDestination changes name', () async {
    final id = const Uuid().v4();
    await db.streamingDestinationsDao.insertDestination(
      StreamingDestinationsTableCompanion.insert(
        id: id,
        userId: userId,
        name: 'Old Name',
        provider: 'youtube',
        protocol: 'rtmp',
        configType: 'rtmp',
        configUrl: 'rtmp://a.rtmp.youtube.com/live2',
        configStreamKey: const Value('key'),
      ),
    );

    await db.streamingDestinationsDao.updateDestination(
      StreamingDestinationsTableCompanion(
        id: Value(id),
        userId: Value(userId),
        name: const Value('New Name'),
        provider: const Value('youtube'),
        protocol: const Value('rtmp'),
        configType: const Value('rtmp'),
        configUrl: const Value('rtmp://a.rtmp.youtube.com/live2'),
        configStreamKey: const Value('key'),
      ),
    );

    final dests = await db.streamingDestinationsDao.getForUser(userId);
    expect(dests.first.name, 'New Name');
  });
}
