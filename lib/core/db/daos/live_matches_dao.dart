import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/live_matches_table.dart';

part 'live_matches_dao.g.dart';

/// Data access for the persisted live-match scoreboard (U2). One row per
/// device; see [LiveMatchesTable] for the keying/lifecycle contract.
@DriftAccessor(tables: [LiveMatchesTable])
class LiveMatchesDao extends DatabaseAccessor<AppDatabase>
    with _$LiveMatchesDaoMixin {
  LiveMatchesDao(super.db);

  /// The persisted live match for [deviceId], or null when none.
  Future<LiveMatchesTableData?> getForDevice(String deviceId) => (select(
    liveMatchesTable,
  )..where((m) => m.deviceId.equals(deviceId))).getSingleOrNull();

  /// Insert-or-replace the device's live-match row (persist-on-change).
  Future<void> upsert(LiveMatchesTableCompanion companion) =>
      into(liveMatchesTable).insertOnConflictUpdate(companion);

  /// Idempotent keyed clear: removes the device's row ONLY when it still
  /// belongs to [matchUuid] — a clear racing a newer session's persist must
  /// not wipe the newer match. Safe to call when no row exists.
  Future<void> clearForMatch(String deviceId, String matchUuid) =>
      (delete(liveMatchesTable)..where(
            (m) => m.deviceId.equals(deviceId) & m.matchUuid.equals(matchUuid),
          ))
          .go();
}
