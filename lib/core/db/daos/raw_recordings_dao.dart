import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/raw_recordings_table.dart';

part 'raw_recordings_dao.g.dart';

@DriftAccessor(tables: [RawRecordingsTable])
class RawRecordingsDao extends DatabaseAccessor<AppDatabase>
    with _$RawRecordingsDaoMixin {
  RawRecordingsDao(super.db);

  /// Watch all raw recordings, newest session first then by camera index.
  Stream<List<RawRecordingsTableData>> watchAll() => (select(rawRecordingsTable)
        ..orderBy([
          (r) => OrderingTerm.desc(r.startedAt),
          (r) => OrderingTerm.asc(r.cameraIndex),
        ]))
      .watch();

  /// The two per-camera files of one raw session, ordered by camera index.
  Future<List<RawRecordingsTableData>> getPair(String captureGroupId) =>
      (select(rawRecordingsTable)
            ..where((r) => r.captureGroupId.equals(captureGroupId))
            ..orderBy([(r) => OrderingTerm.asc(r.cameraIndex)]))
          .get();

  Stream<List<RawRecordingsTableData>> watchPair(String captureGroupId) =>
      (select(rawRecordingsTable)
            ..where((r) => r.captureGroupId.equals(captureGroupId))
            ..orderBy([(r) => OrderingTerm.asc(r.cameraIndex)]))
          .watch();

  Future<void> upsert(RawRecordingsTableCompanion companion) =>
      into(rawRecordingsTable).insertOnConflictUpdate(companion);

  /// Mark a session's rows complete (both files present) or incomplete.
  Future<int> setGroupComplete(String captureGroupId, {required bool complete}) =>
      (update(rawRecordingsTable)
            ..where((r) => r.captureGroupId.equals(captureGroupId)))
          .write(RawRecordingsTableCompanion(isComplete: Value(complete)));

  Future<int> deleteGroup(String captureGroupId) =>
      (delete(rawRecordingsTable)
            ..where((r) => r.captureGroupId.equals(captureGroupId)))
          .go();
}
