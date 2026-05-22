import 'package:drift/drift.dart';

class UsersTable extends Table {
  @override
  String get tableName => 'users';

  TextColumn get id => text()();
  TextColumn get name => text()();

  @override
  Set<Column> get primaryKey => {id};
}
