import 'package:drift/drift.dart';

import 'team_matches_table.dart';

class ClipsTable extends Table {
  @override
  String get tableName => 'clips';

  TextColumn get id => text()();
  TextColumn get matchId =>
      text().references(TeamMatchesTable, #id, onDelete: KeyAction.cascade)();
  /// Start offset in seconds from the beginning of the source video.
  IntColumn get startSeconds => integer().withDefault(const Constant(0))();
  IntColumn get durationSeconds => integer()();
  IntColumn get sizeBytes => integer()();
  TextColumn get startedAt => text()();
  TextColumn get label => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
