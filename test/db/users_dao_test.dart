import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scout_camera/db/app_database.dart';
import 'package:uuid/uuid.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    // Trigger onCreate which seeds the default user + sport presets.
    await db.usersDao.getAll();
  });

  tearDown(() => db.close());

  // ---------------------------------------------------------------------------
  // watchAll
  // ---------------------------------------------------------------------------

  test('watchAll on fresh DB emits the default user from base seed', () async {
    final result = await db.usersDao.watchAll().first;
    expect(result, hasLength(1));
    expect(result.first.id, 'default-user');
  });

  test('insert user → watchAll emits it alongside the default user', () async {
    final id = const Uuid().v4();
    await db.usersDao.insertUser(
      UsersTableCompanion.insert(id: id, name: 'Coach Alice'),
    );

    final users = await db.usersDao.watchAll().first;
    expect(users, hasLength(2));
    expect(users.any((u) => u.id == id && u.name == 'Coach Alice'), isTrue);
  });

  test('getUserById returns correct user', () async {
    final id = const Uuid().v4();
    await db.usersDao.insertUser(
      UsersTableCompanion.insert(id: id, name: 'Coach Bob'),
    );

    final user = await db.usersDao.getUserById(id);
    expect(user, isNotNull);
    expect(user!.name, 'Coach Bob');
  });

  test('getUserById returns null for unknown id', () async {
    final user = await db.usersDao.getUserById('no-such-id');
    expect(user, isNull);
  });

  test('updateUser changes the name', () async {
    final id = const Uuid().v4();
    await db.usersDao.insertUser(
      UsersTableCompanion.insert(id: id, name: 'Old Name'),
    );

    await db.usersDao.updateUser(
      UsersTableCompanion(id: Value(id), name: const Value('New Name')),
    );

    final user = await db.usersDao.getUserById(id);
    expect(user!.name, 'New Name');
  });

  // ---------------------------------------------------------------------------
  // deleteById + FK cascade
  // ---------------------------------------------------------------------------

  test('deleteById removes a specific user, leaving default user intact', () async {
    final id = const Uuid().v4();
    await db.usersDao.insertUser(
      UsersTableCompanion.insert(id: id, name: 'Temp User'),
    );

    await db.usersDao.deleteById(id);

    final users = await db.usersDao.getAll();
    expect(users, hasLength(1));
    expect(users.first.id, 'default-user');
  });

  test('deleteById cascades to teams', () async {
    final userId = const Uuid().v4();
    final teamId = const Uuid().v4();

    await db.usersDao.insertUser(
      UsersTableCompanion.insert(id: userId, name: 'Coach Diego'),
    );
    await db.teamsDao.insertTeam(
      TeamsTableCompanion.insert(
        id: teamId,
        userId: userId,
        name: 'Test FC',
        shortName: 'TFC',
        sport: 'Soccer',
      ),
    );

    await db.usersDao.deleteById(userId);

    final teams = await db.teamsDao.getForUser(userId);
    expect(teams, isEmpty);
  });

  test('deleteById cascades to sport_presets', () async {
    final userId = const Uuid().v4();

    await db.usersDao.insertUser(
      UsersTableCompanion.insert(id: userId, name: 'Coach Maria'),
    );
    await db.sportPresetsDao.seedBuiltInsForUser(userId);

    await db.usersDao.deleteById(userId);

    final presets = await db.sportPresetsDao.getForUser(userId);
    expect(presets, isEmpty);
  });

  test('deleteById cascades to streaming_destinations', () async {
    final userId = const Uuid().v4();
    final destId = const Uuid().v4();

    await db.usersDao.insertUser(
      UsersTableCompanion.insert(id: userId, name: 'Coach Carlos'),
    );
    await db.streamingDestinationsDao.insertDestination(
      StreamingDestinationsTableCompanion.insert(
        id: destId,
        userId: userId,
        name: 'YouTube Live',
        provider: 'youtube',
        protocol: 'rtmp',
        configType: 'rtmp',
        configUrl: 'rtmp://a.rtmp.youtube.com/live2',
        configStreamKey: const Value('abc123'),
      ),
    );

    await db.usersDao.deleteById(userId);

    final dests = await db.streamingDestinationsDao.getForUser(userId);
    expect(dests, isEmpty);
  });
}
