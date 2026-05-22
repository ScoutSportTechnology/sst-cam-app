import 'package:drift/drift.dart';

import 'clips_table.dart';

class ThumbnailsTable extends Table {
  @override
  String get tableName => 'thumbnails';

  TextColumn get clipId =>
      text().references(ClipsTable, #id, onDelete: KeyAction.cascade)();
  TextColumn get localPath => text()();

  @override
  Set<Column> get primaryKey => {clipId};
}
