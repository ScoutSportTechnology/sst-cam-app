// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'clips_dao.dart';

// ignore_for_file: type=lint
mixin _$ClipsDaoMixin on DatabaseAccessor<AppDatabase> {
  $UsersTableTable get usersTable => attachedDatabase.usersTable;
  $TeamsTableTable get teamsTable => attachedDatabase.teamsTable;
  $TeamMatchesTableTable get teamMatchesTable =>
      attachedDatabase.teamMatchesTable;
  $ClipsTableTable get clipsTable => attachedDatabase.clipsTable;
  ClipsDaoManager get managers => ClipsDaoManager(this);
}

class ClipsDaoManager {
  final _$ClipsDaoMixin _db;
  ClipsDaoManager(this._db);
  $$UsersTableTableTableManager get usersTable =>
      $$UsersTableTableTableManager(_db.attachedDatabase, _db.usersTable);
  $$TeamsTableTableTableManager get teamsTable =>
      $$TeamsTableTableTableManager(_db.attachedDatabase, _db.teamsTable);
  $$TeamMatchesTableTableTableManager get teamMatchesTable =>
      $$TeamMatchesTableTableTableManager(
        _db.attachedDatabase,
        _db.teamMatchesTable,
      );
  $$ClipsTableTableTableManager get clipsTable =>
      $$ClipsTableTableTableManager(_db.attachedDatabase, _db.clipsTable);
}
