import 'package:drift/drift.dart';

import '../../core/models/streaming.dart';
import '../app_database.dart';
import '../tables/streaming_destinations_table.dart';

part 'streaming_destinations_dao.g.dart';

@DriftAccessor(tables: [StreamingDestinationsTable])
class StreamingDestinationsDao extends DatabaseAccessor<AppDatabase>
    with _$StreamingDestinationsDaoMixin {
  StreamingDestinationsDao(super.db);

  /// Watch all destinations for a user — emits on every mutation.
  Stream<List<StreamingDestinationsTableData>> watchForUser(String userId) =>
      (select(
        streamingDestinationsTable,
      )..where((d) => d.userId.equals(userId))).watch();

  /// One-shot fetch of all destinations for a user.
  Future<List<StreamingDestinationsTableData>> getForUser(String userId) =>
      (select(
        streamingDestinationsTable,
      )..where((d) => d.userId.equals(userId))).get();

  /// Insert a new destination row.
  ///
  /// Throws [ArgumentError] if the companion is for an RTMP destination
  /// but has no stream key — surfacing the data-integrity issue at write
  /// time rather than silently at stream-push time.
  Future<void> insertDestination(
    StreamingDestinationsTableCompanion companion,
  ) {
    if (companion.configType.value == 'rtmp' &&
        (companion.configStreamKey.value == null ||
            companion.configStreamKey.value!.isEmpty)) {
      throw ArgumentError('RTMP streaming destination requires a stream key');
    }
    return into(streamingDestinationsTable).insert(companion);
  }

  /// Update an existing destination row.
  Future<bool> updateDestination(
    StreamingDestinationsTableCompanion companion,
  ) => update(streamingDestinationsTable).replace(companion);

  /// Delete a destination by id.
  Future<int> deleteById(String id) =>
      (delete(streamingDestinationsTable)..where((d) => d.id.equals(id))).go();

  /// Reconstruct a [StreamingConfig] from the flat columns stored in [row].
  ///
  /// Uses an exhaustive Dart 3 switch on [row.configType] so the compiler
  /// will flag any future config type additions that aren't handled here.
  ///
  /// Throws [StateError] for unknown configType values (defensive — should
  /// never happen if all writes go through this DAO).
  static StreamingConfig configFromRow(StreamingDestinationsTableData row) {
    return switch (row.configType) {
      'rtmp' =>
        row.configStreamKey == null || row.configStreamKey!.isEmpty
            ? throw StateError('RTMP destination ${row.id} missing stream key')
            : RtmpConfig(url: row.configUrl, streamKey: row.configStreamKey!),
      'rtsp' => RtspConfig(
        url: row.configUrl,
        username: row.configUsername,
        password: row.configPassword,
      ),
      final unknown => throw StateError(
        'Unknown configType: "$unknown" for destination ${row.id}',
      ),
    };
  }
}
