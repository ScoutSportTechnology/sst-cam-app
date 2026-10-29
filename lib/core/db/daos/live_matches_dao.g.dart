// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'live_matches_dao.dart';

// ignore_for_file: type=lint
mixin _$LiveMatchesDaoMixin on DatabaseAccessor<AppDatabase> {
  $LiveMatchesTableTable get liveMatchesTable =>
      attachedDatabase.liveMatchesTable;
  LiveMatchesDaoManager get managers => LiveMatchesDaoManager(this);
}

class LiveMatchesDaoManager {
  final _$LiveMatchesDaoMixin _db;
  LiveMatchesDaoManager(this._db);
  $$LiveMatchesTableTableTableManager get liveMatchesTable =>
      $$LiveMatchesTableTableTableManager(
        _db.attachedDatabase,
        _db.liveMatchesTable,
      );
}
