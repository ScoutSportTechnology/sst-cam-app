import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sst_cam_app/core/db/app_database.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
  });

  tearDown(() => db.close());

  RawRecordingsTableCompanion row(
    String id,
    String group,
    int cameraIndex, {
    String? matchId,
  }) {
    return RawRecordingsTableCompanion.insert(
      id: id,
      captureGroupId: group,
      cameraIndex: cameraIndex,
      startedAt: '2026-06-10T00:00:00Z',
      matchId: Value(matchId),
    );
  }

  test(
    'getPair returns the two per-camera files ordered by camera index',
    () async {
      await db.rawRecordingsDao.upsert(row('r1', 'grp-1', 1));
      await db.rawRecordingsDao.upsert(row('r0', 'grp-1', 0));
      await db.rawRecordingsDao.upsert(row('other', 'grp-2', 0));

      final pair = await db.rawRecordingsDao.getPair('grp-1');
      expect(pair, hasLength(2));
      expect(pair[0].cameraIndex, 0);
      expect(pair[1].cameraIndex, 1);
      expect(pair.every((r) => r.captureGroupId == 'grp-1'), isTrue);
      expect(pair.every((r) => r.isRaw), isTrue);
    },
  );

  test('setGroupComplete flips both rows of the group', () async {
    await db.rawRecordingsDao.upsert(row('r0', 'grp-1', 0));
    await db.rawRecordingsDao.upsert(row('r1', 'grp-1', 1));

    await db.rawRecordingsDao.setGroupComplete('grp-1', complete: true);

    final pair = await db.rawRecordingsDao.getPair('grp-1');
    expect(pair.every((r) => r.isComplete), isTrue);
  });

  test('upsert updates an existing row in place', () async {
    await db.rawRecordingsDao.upsert(row('r0', 'grp-1', 0));
    await db.rawRecordingsDao.upsert(
      RawRecordingsTableCompanion.insert(
        id: 'r0',
        captureGroupId: 'grp-1',
        cameraIndex: 0,
        startedAt: '2026-06-10T00:00:00Z',
        localPath: const Value('/videos/r0.nv12'),
        sizeBytes: const Value(1024),
      ),
    );

    final pair = await db.rawRecordingsDao.getPair('grp-1');
    expect(pair, hasLength(1));
    expect(pair.single.localPath, '/videos/r0.nv12');
    expect(pair.single.sizeBytes, 1024);
  });

  test(
    'FK cascade: deleting a match removes its raw rows (pragma on)',
    () async {
      await db.usersDao.insertUser(
        UsersTableCompanion.insert(id: 'u1', name: 'Coach'),
      );
      await db.teamsDao.insertTeam(
        TeamsTableCompanion.insert(
          id: 't1',
          userId: 'u1',
          name: 'Team One',
          shortName: 'T1',
          sport: 'Soccer',
        ),
      );
      await db.teamsDao.insertTeamMatch(
        TeamMatchesTableCompanion.insert(
          id: 'm1',
          teamId: 't1',
          opponent: 'vs Two',
          date: 'May 11',
          result: '',
          kind: 'upcoming',
          numPeriods: 2,
          periodLengthSeconds: 2100,
        ),
      );
      await db.rawRecordingsDao.upsert(row('r0', 'grp-1', 0, matchId: 'm1'));

      expect(await db.rawRecordingsDao.getPair('grp-1'), hasLength(1));
      await db.teamsDao.deleteTeamMatch('m1');
      expect(await db.rawRecordingsDao.getPair('grp-1'), isEmpty);
    },
  );

  test('watchAll emits on insert', () async {
    final stream = db.rawRecordingsDao.watchAll();
    await db.rawRecordingsDao.upsert(row('r0', 'grp-1', 0));
    await expectLater(
      stream,
      emitsThrough(
        predicate<List<RawRecordingsTableData>>(
          (rows) => rows.any((r) => r.id == 'r0'),
        ),
      ),
    );
  });
}
