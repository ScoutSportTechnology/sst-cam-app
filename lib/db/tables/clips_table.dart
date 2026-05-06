import 'package:drift/drift.dart';

import 'team_matches_table.dart';

class ClipsTable extends Table {
  @override
  String get tableName => 'clips';

  TextColumn get id => text()();
  TextColumn get matchId =>
      text().references(TeamMatchesTable, #id, onDelete: KeyAction.cascade)();
  IntColumn get durationSeconds => integer()();
  IntColumn get sizeBytes => integer()();
  TextColumn get startedAt => text()();

  @override
  Set<Column> get primaryKey => {id};
}
