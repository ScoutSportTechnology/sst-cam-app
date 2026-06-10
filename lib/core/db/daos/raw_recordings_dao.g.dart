// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'raw_recordings_dao.dart';

// ignore_for_file: type=lint
mixin _$RawRecordingsDaoMixin on DatabaseAccessor<AppDatabase> {
  $UsersTableTable get usersTable => attachedDatabase.usersTable;
  $TeamsTableTable get teamsTable => attachedDatabase.teamsTable;
  $TeamMatchesTableTable get teamMatchesTable =>
      attachedDatabase.teamMatchesTable;
  $RawRecordingsTableTable get rawRecordingsTable =>
      attachedDatabase.rawRecordingsTable;
  RawRecordingsDaoManager get managers => RawRecordingsDaoManager(this);
}

class RawRecordingsDaoManager {
  final _$RawRecordingsDaoMixin _db;
  RawRecordingsDaoManager(this._db);
  $$UsersTableTableTableManager get usersTable =>
      $$UsersTableTableTableManager(_db.attachedDatabase, _db.usersTable);
  $$TeamsTableTableTableManager get teamsTable =>
      $$TeamsTableTableTableManager(_db.attachedDatabase, _db.teamsTable);
  $$TeamMatchesTableTableTableManager get teamMatchesTable =>
      $$TeamMatchesTableTableTableManager(
        _db.attachedDatabase,
        _db.teamMatchesTable,
      );
  $$RawRecordingsTableTableTableManager get rawRecordingsTable =>
      $$RawRecordingsTableTableTableManager(
        _db.attachedDatabase,
        _db.rawRecordingsTable,
      );
}
