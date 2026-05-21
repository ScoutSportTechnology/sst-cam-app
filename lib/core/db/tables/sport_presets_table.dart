import 'package:drift/drift.dart';

import 'users_table.dart';

class SportPresetsTable extends Table {
  @override
  String get tableName => 'sport_presets';

  TextColumn get id => text()();
  TextColumn get userId =>
      text().references(UsersTable, #id, onDelete: KeyAction.cascade)();
  TextColumn get name => text()();
  TextColumn get sport => text()();
  IntColumn get numPeriods => integer()();
  IntColumn get periodLengthSeconds => integer()();
  BoolColumn get builtIn => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id, userId};
}
