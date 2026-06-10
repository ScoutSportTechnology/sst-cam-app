import 'package:drift/drift.dart';

import 'team_matches_table.dart';

/// App-owned metadata for raw dual-camera capture files (the YOLO training
/// footage). One row per per-camera file; the two files of a session share a
/// [captureGroupId] (app-minted) and differ by [cameraIndex] (0/1) — the same
/// identity keys the firmware stamps onto each file's RecordingMetadata.
///
/// This is deliberately a dedicated table, not an overload of `team_matches`
/// (which assumes one file per id): a raw session is two files, and the app
/// owns this metadata while the camera owns only the on-disk files.
class RawRecordingsTable extends Table {
  @override
  String get tableName => 'raw_recordings';

  /// Stable local id (e.g. the firmware recording_id / file stem).
  TextColumn get id => text()();

  /// App-minted id shared by both per-camera files of one raw session.
  TextColumn get captureGroupId => text()();

  /// Physical sensor index (0 = primary, 1 = secondary).
  IntColumn get cameraIndex => integer()();

  /// Optional association to a match; cascades on match delete.
  TextColumn get matchId => text()
      .nullable()
      .references(TeamMatchesTable, #id, onDelete: KeyAction.cascade)();

  /// On-disk path of the downloaded file (mirrors clips/thumbnails).
  TextColumn get localPath => text().nullable()();

  IntColumn get sizeBytes => integer().withDefault(const Constant(0))();

  /// Always true for rows in this table; kept explicit so the column mirrors the
  /// contract field and a future non-raw use can't silently reinterpret rows.
  BoolColumn get isRaw => boolean().withDefault(const Constant(true))();

  /// Whether both files of the pair downloaded successfully. A recovered single
  /// file is marked incomplete rather than saved as if whole.
  BoolColumn get isComplete => boolean().withDefault(const Constant(false))();

  TextColumn get startedAt => text()();

  @override
  Set<Column> get primaryKey => {id};
}
