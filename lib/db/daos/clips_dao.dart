import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/clips_table.dart';

part 'clips_dao.g.dart';

@DriftAccessor(tables: [ClipsTable])
class ClipsDao extends DatabaseAccessor<AppDatabase> with _$ClipsDaoMixin {
  ClipsDao(super.db);

  /// Watch all clips for a given match, ordered by start offset.
  Stream<List<ClipsTableData>> clipsForMatch(String matchId) =>
      (select(clipsTable)
            ..where((c) => c.matchId.equals(matchId))
            ..orderBy([(c) => OrderingTerm.asc(c.startSeconds)]))
          .watch();

  /// One-shot fetch of all clips for a match.
  Future<List<ClipsTableData>> getClipsForMatch(String matchId) =>
      (select(clipsTable)
            ..where((c) => c.matchId.equals(matchId))
            ..orderBy([(c) => OrderingTerm.asc(c.startSeconds)]))
          .get();

  /// Insert a new clip record.
  Future<void> insertClip(ClipsTableCompanion companion) =>
      into(clipsTable).insert(companion);

  /// Delete a clip by id.
  Future<int> deleteClip(String id) =>
      (delete(clipsTable)..where((c) => c.id.equals(id))).go();
}
