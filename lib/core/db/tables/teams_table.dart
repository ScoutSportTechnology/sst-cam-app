import 'package:drift/drift.dart';

import 'users_table.dart';

class TeamsTable extends Table {
  @override
  String get tableName => 'teams';

  TextColumn get id => text()();
  TextColumn get userId =>
      text().references(UsersTable, #id, onDelete: KeyAction.cascade)();
  TextColumn get name => text()();
  TextColumn get shortName => text()();
  TextColumn get sport => text()();
  TextColumn get colorHex => text().nullable()();
  BoolColumn get hidden => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

class PlayersTable extends Table {
  @override
  String get tableName => 'players';

  TextColumn get teamId =>
      text().references(TeamsTable, #id, onDelete: KeyAction.cascade)();
  IntColumn get number => integer()();
  TextColumn get name => text()();
  TextColumn get position => text()();
  BoolColumn get captain => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {teamId, number};
}
