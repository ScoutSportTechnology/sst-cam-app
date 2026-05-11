import 'package:drift/drift.dart';

import 'teams_table.dart';

class TeamMatchesTable extends Table {
  @override
  String get tableName => 'team_matches';

  TextColumn get id => text()();
  TextColumn get teamId =>
      text().references(TeamsTable, #id, onDelete: KeyAction.cascade)();
  TextColumn get opponent => text()();
  TextColumn get date => text()();
  TextColumn get result => text()();

  /// 'past' | 'upcoming'
  TextColumn get kind => text()();
  IntColumn get numPeriods => integer()();
  IntColumn get periodLengthSeconds => integer()();
  IntColumn get clips => integer().withDefault(const Constant(0))();
  IntColumn get sizeMb => integer().withDefault(const Constant(0))();
  /// JSON-encoded list of match events: [{timeSeconds, label, team, kind}].
  /// Empty array '[]' when no events recorded.
  TextColumn get eventsJson =>
      text().withDefault(const Constant('[]'))();

  @override
  Set<Column> get primaryKey => {id};
}
