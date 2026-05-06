// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'teams_dao.dart';

// ignore_for_file: type=lint
mixin _$TeamsDaoMixin on DatabaseAccessor<AppDatabase> {
  $UsersTableTable get usersTable => attachedDatabase.usersTable;
  $TeamsTableTable get teamsTable => attachedDatabase.teamsTable;
  $PlayersTableTable get playersTable => attachedDatabase.playersTable;
  $TeamMatchesTableTable get teamMatchesTable =>
      attachedDatabase.teamMatchesTable;
  TeamsDaoManager get managers => TeamsDaoManager(this);
}

class TeamsDaoManager {
  final _$TeamsDaoMixin _db;
  TeamsDaoManager(this._db);
  $$UsersTableTableTableManager get usersTable =>
      $$UsersTableTableTableManager(_db.attachedDatabase, _db.usersTable);
  $$TeamsTableTableTableManager get teamsTable =>
      $$TeamsTableTableTableManager(_db.attachedDatabase, _db.teamsTable);
  $$PlayersTableTableTableManager get playersTable =>
      $$PlayersTableTableTableManager(_db.attachedDatabase, _db.playersTable);
  $$TeamMatchesTableTableTableManager get teamMatchesTable =>
      $$TeamMatchesTableTableTableManager(
        _db.attachedDatabase,
        _db.teamMatchesTable,
      );
}
