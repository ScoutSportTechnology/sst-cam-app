// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sport_presets_dao.dart';

// ignore_for_file: type=lint
mixin _$SportPresetsDaoMixin on DatabaseAccessor<AppDatabase> {
  $UsersTableTable get usersTable => attachedDatabase.usersTable;
  $SportPresetsTableTable get sportPresetsTable =>
      attachedDatabase.sportPresetsTable;
  SportPresetsDaoManager get managers => SportPresetsDaoManager(this);
}

class SportPresetsDaoManager {
  final _$SportPresetsDaoMixin _db;
  SportPresetsDaoManager(this._db);
  $$UsersTableTableTableManager get usersTable =>
      $$UsersTableTableTableManager(_db.attachedDatabase, _db.usersTable);
  $$SportPresetsTableTableTableManager get sportPresetsTable =>
      $$SportPresetsTableTableTableManager(
        _db.attachedDatabase,
        _db.sportPresetsTable,
      );
}
