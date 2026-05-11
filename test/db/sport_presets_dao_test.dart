import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sst_cam_app/db/app_database.dart';
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
      UsersTableCompanion.insert(id: userId, name: 'Coach Alice'),
    );
  });

  tearDown(() => db.close());

  // ---------------------------------------------------------------------------
  // seedBuiltInsForUser
  // ---------------------------------------------------------------------------

  test('seedBuiltInsForUser inserts 7 presets all with builtIn=true', () async {
    await db.sportPresetsDao.seedBuiltInsForUser(userId);

    final presets = await db.sportPresetsDao.getForUser(userId);
    expect(presets, hasLength(7));
    expect(presets.every((p) => p.builtIn), isTrue);
  });

  test('seedBuiltInsForUser has correct preset IDs and data', () async {
    await db.sportPresetsDao.seedBuiltInsForUser(userId);

    final presets = await db.sportPresetsDao.getForUser(userId);
    final ids = presets.map((p) => p.id).toSet();

    expect(ids, contains('${userId}_preset-soccer-std'));
    expect(ids, contains('${userId}_preset-soccer-youth'));
    expect(ids, contains('${userId}_preset-basketball-fiba'));
    expect(ids, contains('${userId}_preset-hockey-std'));
    expect(ids, contains('${userId}_preset-volleyball-5set'));
    expect(ids, contains('${userId}_preset-rugby-std'));
    expect(ids, contains('${userId}_preset-other-single'));

    final soccer = presets.firstWhere(
      (p) => p.id == '${userId}_preset-soccer-std',
    );
    expect(soccer.sport, 'Soccer');
    expect(soccer.numPeriods, 2);
    expect(soccer.periodLengthSeconds, 45 * 60);

    final basketball = presets.firstWhere(
      (p) => p.id == '${userId}_preset-basketball-fiba',
    );
    expect(basketball.sport, 'Basketball');
    expect(basketball.numPeriods, 4);
    expect(basketball.periodLengthSeconds, 10 * 60);
  });

  test('seedBuiltInsForUser is idempotent (call twice, same rows)', () async {
    await db.sportPresetsDao.seedBuiltInsForUser(userId);
    await db.sportPresetsDao.seedBuiltInsForUser(userId);

    final presets = await db.sportPresetsDao.getForUser(userId);
    expect(presets, hasLength(7));
  });

  // ---------------------------------------------------------------------------
  // Custom presets
  // ---------------------------------------------------------------------------

  test('insert custom preset → appears in watchForUser', () async {
    await db.sportPresetsDao.seedBuiltInsForUser(userId);

    final customId = const Uuid().v4();
    await db.sportPresetsDao.insertPreset(
      SportPresetsTableCompanion.insert(
        id: customId,
        userId: userId,
        name: 'My Custom Soccer',
        sport: 'Soccer',
        numPeriods: 2,
        periodLengthSeconds: 30 * 60,
      ),
    );

    final presets = await db.sportPresetsDao.watchForUser(userId).first;
    expect(presets, hasLength(8));
    final custom = presets.firstWhere((p) => p.id == customId);
    expect(custom.builtIn, isFalse);
    expect(custom.name, 'My Custom Soccer');
  });

  test('deleteById removes custom preset', () async {
    final customId = const Uuid().v4();
    await db.sportPresetsDao.insertPreset(
      SportPresetsTableCompanion.insert(
        id: customId,
        userId: userId,
        name: 'Custom Preset',
        sport: 'Other',
        numPeriods: 1,
        periodLengthSeconds: 20 * 60,
      ),
    );

    await db.sportPresetsDao.deleteById(customId);

    final presets = await db.sportPresetsDao.getForUser(userId);
    expect(presets.any((p) => p.id == customId), isFalse);
  });

  test('getById returns correct preset', () async {
    final customId = const Uuid().v4();
    await db.sportPresetsDao.insertPreset(
      SportPresetsTableCompanion.insert(
        id: customId,
        userId: userId,
        name: 'Lookup Preset',
        sport: 'Hockey',
        numPeriods: 3,
        periodLengthSeconds: 20 * 60,
      ),
    );

    final preset = await db.sportPresetsDao.getById(customId);
    expect(preset, isNotNull);
    expect(preset!.name, 'Lookup Preset');
  });

  test('getById returns null for unknown id', () async {
    final preset = await db.sportPresetsDao.getById('no-such-id');
    expect(preset, isNull);
  });

  test('watchForUser with no rows emits empty list', () async {
    final result = await db.sportPresetsDao.watchForUser(userId).first;
    expect(result, isEmpty);
  });

  test('different users have independent presets', () async {
    final userId2 = const Uuid().v4();
    await db.usersDao.insertUser(
      UsersTableCompanion.insert(id: userId2, name: 'Coach Maria'),
    );

    await db.sportPresetsDao.seedBuiltInsForUser(userId);
    // user2 gets no presets

    final presetsUser1 = await db.sportPresetsDao.getForUser(userId);
    final presetsUser2 = await db.sportPresetsDao.getForUser(userId2);

    expect(presetsUser1, hasLength(7));
    expect(presetsUser2, isEmpty);
  });

  test(
    'seedBuiltInsForUser for two users gives each 7 independent presets',
    () async {
      final userId2 = const Uuid().v4();
      await db.usersDao.insertUser(
        UsersTableCompanion.insert(id: userId2, name: 'Coach Maria'),
      );

      await db.sportPresetsDao.seedBuiltInsForUser(userId);
      await db.sportPresetsDao.seedBuiltInsForUser(userId2);

      final presetsUser1 = await db.sportPresetsDao.getForUser(userId);
      final presetsUser2 = await db.sportPresetsDao.getForUser(userId2);

      expect(presetsUser1, hasLength(7));
      expect(presetsUser2, hasLength(7));

      // IDs are user-scoped — no overlap between the two sets.
      final ids1 = presetsUser1.map((p) => p.id).toSet();
      final ids2 = presetsUser2.map((p) => p.id).toSet();
      expect(ids1.intersection(ids2), isEmpty);
    },
  );
}
