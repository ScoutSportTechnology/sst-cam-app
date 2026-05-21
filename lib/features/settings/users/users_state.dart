// Users state — active user selection, controller, and provider.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../../core/db/app_database.dart'
    show UsersTableData, UsersTableCompanion;
import '../../../core/models/user.dart';
import '../../../core/state/db_providers.dart';
import '../../match/session/session_state.dart'
    show isLiveMatchRunning, liveMatchProvider;

export '../../../core/models/user.dart';

// ---------------------------------------------------------------------------
// Active user — single source of truth on the app side. Hydrated from
// SharedPreferences in `UsersController.build()`. Per-user-scoped controllers
// (teams, sport presets, streaming destinations) watch this provider so they
// rebuild on user switch.
// ---------------------------------------------------------------------------

final activeUserProvider = StateProvider<String?>((_) => null);

const _kActiveUserIdKey = 'active_user_id';

const _uuid = Uuid();

/// Typed exception for `UsersController` UI-rule pre-checks. Surfaced to the
/// UI so the user / form layers can render an inline message rather than
/// letting the BLE call fail noisily.
class UsersControllerException implements Exception {
  const UsersControllerException(this.message);
  final String message;

  @override
  String toString() => 'UsersControllerException: $message';
}

class UsersController extends AsyncNotifier<List<UserRecord>> {
  @override
  Future<List<UserRecord>> build() async {
    final dao = ref.watch(usersDaoProvider);

    // Hydrate active user from SharedPreferences.
    final prefs = await SharedPreferences.getInstance();
    final savedId = prefs.getString(_kActiveUserIdKey);
    if (savedId != null) {
      final exists = await dao.getUserById(savedId);
      if (exists != null) {
        ref.read(activeUserProvider.notifier).state = savedId;
      } else {
        await prefs.remove(_kActiveUserIdKey);
      }
    }

    // Auto-select the only user on first launch or after the saved user was
    // deleted — avoids a blank-screen state where all per-user data is empty.
    if (ref.read(activeUserProvider) == null) {
      final all = await dao.getAll();
      if (all.length == 1) {
        final onlyId = all.first.id;
        ref.read(activeUserProvider.notifier).state = onlyId;
        await prefs.setString(_kActiveUserIdKey, onlyId);
      }
    }

    // Subscribe to watch stream for all mutations. The listener may fire once
    // with the same data as the initial snapshot below; that is acceptable.
    final sub = dao.watchAll().listen(
      (rows) {
        state = AsyncValue.data(_toUserRecords(rows));
      },
      onError: (Object e, StackTrace st) {
        state = AsyncValue.error(e, st);
      },
    );
    ref.onDispose(sub.cancel);

    // Return initial snapshot.
    return _toUserRecords(await dao.getAll());
  }

  static List<UserRecord> _toUserRecords(List<UsersTableData> rows) =>
      rows.map((r) => UserRecord(id: r.id, name: r.name)).toList();

  Future<UserRecord> create(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw const UsersControllerException('User name is required');
    }
    final userId = _uuid.v4();
    final dao = ref.read(usersDaoProvider);
    await dao.insertUser(UsersTableCompanion.insert(id: userId, name: trimmed));

    // Seed built-in sport presets for this user.
    await ref.read(sportPresetsDaoProvider).seedBuiltInsForUser(userId);

    // If no active user yet, auto-activate the first user.
    if (ref.read(activeUserProvider) == null) {
      ref.read(activeUserProvider.notifier).state = userId;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kActiveUserIdKey, userId);
    }

    return UserRecord(id: userId, name: trimmed);
  }

  Future<void> rename(String userId, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw const UsersControllerException('User name is required');
    }
    await ref
        .read(usersDaoProvider)
        .updateUser(UsersTableCompanion.insert(id: userId, name: trimmed));
  }

  /// Switch the active user. Writes SharedPreferences then updates the
  /// provider. `upcomingMatchesProvider` rebuilds automatically because
  /// TeamsController (which feeds it) watches `activeUserProvider`.
  Future<void> setActive(String userId) async {
    if (userId == ref.read(activeUserProvider)) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kActiveUserIdKey, userId); // persist first
    ref.read(activeUserProvider.notifier).state =
        userId; // then update in-memory
  }

  /// Restore the active user after a backup import. Writes to SharedPreferences
  /// and updates [activeUserProvider]. Pass null to clear the active user.
  ///
  /// Fix 11: Centralises the SharedPreferences write that was previously
  /// duplicated in settings_page.dart's restore handler.
  Future<void> restoreActive(String? userId) async {
    final prefs = await SharedPreferences.getInstance();
    if (userId != null) {
      ref.read(activeUserProvider.notifier).state = userId;
      await prefs.setString(_kActiveUserIdKey, userId);
    } else {
      ref.read(activeUserProvider.notifier).state = null;
      await prefs.remove(_kActiveUserIdKey);
    }
  }

  /// Delete a user. UI-rule pre-checks raise [UsersControllerException]
  /// BEFORE touching the DB so the form can render an inline message and
  /// no DB state is touched on a UI-rule violation.
  Future<void> delete(String userId) async {
    final users = state.valueOrNull ?? const [];
    final activeUserId = ref.read(activeUserProvider);
    if (userId == activeUserId) {
      throw const UsersControllerException('Cannot delete the active user');
    }
    if (users.length <= 1) {
      throw const UsersControllerException('At least one user must remain');
    }
    // Block delete while any match is live.
    if (isLiveMatchRunning(ref.read(liveMatchProvider))) {
      throw const UsersControllerException(
        'End the live match before deleting',
      );
    }

    // FK cascade removes all owned teams / presets / destinations.
    await ref.read(usersDaoProvider).deleteById(userId);
  }
}

final usersControllerProvider =
    AsyncNotifierProvider<UsersController, List<UserRecord>>(
      UsersController.new,
    );
