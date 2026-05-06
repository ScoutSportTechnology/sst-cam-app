import 'package:drift/drift.dart';

import 'users_table.dart';

class StreamingDestinationsTable extends Table {
  @override
  String get tableName => 'streaming_destinations';

  TextColumn get id => text()();
  TextColumn get userId =>
      text().references(UsersTable, #id, onDelete: KeyAction.cascade)();
  TextColumn get name => text()();
  TextColumn get provider => text()();
  TextColumn get protocol => text()();

  /// 'rtmp' | 'rtsp'
  TextColumn get configType => text()();
  TextColumn get configUrl => text()();
  TextColumn get configStreamKey => text().nullable()();
  TextColumn get configUsername => text().nullable()();
  TextColumn get configPassword => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
