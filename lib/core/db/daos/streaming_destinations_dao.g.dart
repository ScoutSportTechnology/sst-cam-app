// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'streaming_destinations_dao.dart';

// ignore_for_file: type=lint
mixin _$StreamingDestinationsDaoMixin on DatabaseAccessor<AppDatabase> {
  $UsersTableTable get usersTable => attachedDatabase.usersTable;
  $StreamingDestinationsTableTable get streamingDestinationsTable =>
      attachedDatabase.streamingDestinationsTable;
  StreamingDestinationsDaoManager get managers =>
      StreamingDestinationsDaoManager(this);
}

class StreamingDestinationsDaoManager {
  final _$StreamingDestinationsDaoMixin _db;
  StreamingDestinationsDaoManager(this._db);
  $$UsersTableTableTableManager get usersTable =>
      $$UsersTableTableTableManager(_db.attachedDatabase, _db.usersTable);
  $$StreamingDestinationsTableTableTableManager
  get streamingDestinationsTable =>
      $$StreamingDestinationsTableTableTableManager(
        _db.attachedDatabase,
        _db.streamingDestinationsTable,
      );
}
