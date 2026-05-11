import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/users_table.dart';

part 'users_dao.g.dart';

@DriftAccessor(tables: [UsersTable])
class UsersDao extends DatabaseAccessor<AppDatabase> with _$UsersDaoMixin {
  UsersDao(super.db);

  /// Watch all users — emits on every mutation.
  Stream<List<UsersTableData>> watchAll() => select(usersTable).watch();

  /// One-shot fetch of all users.
  Future<List<UsersTableData>> getAll() => select(usersTable).get();

  /// One-shot fetch of a single user, or null if not found.
  Future<UsersTableData?> getUserById(String id) =>
      (select(usersTable)..where((t) => t.id.equals(id))).getSingleOrNull();

  /// Insert or update a user row (upsert on primary key).
  Future<void> insertUser(UsersTableCompanion companion) =>
      into(usersTable).insertOnConflictUpdate(companion);

  /// Update an existing user row (matched by id in the companion).
  Future<bool> updateUser(UsersTableCompanion companion) =>
      update(usersTable).replace(companion);

  /// Delete a user by id. FK cascade removes all owned rows.
  Future<int> deleteById(String id) =>
      (delete(usersTable)..where((t) => t.id.equals(id))).go();
}
