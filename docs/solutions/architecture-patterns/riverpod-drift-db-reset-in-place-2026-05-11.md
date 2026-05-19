---
title: "Resetting a Drift database with Riverpod: wipe in-place, never close"
date: 2026-05-11
category: architecture-patterns
module: Database + State management
problem_type: architecture_pattern
component: database
severity: high
applies_when:
  - Adding a debug reset screen that clears and re-seeds the Drift database
  - Implementing a "factory reset" or "sign out" flow that wipes local data
  - Any code path that needs to clear all DB rows while the app stays running
tags: riverpod, drift, sqlite, database-reset, provider, flutter, state-management, debug-screen
---

# Resetting a Drift database with Riverpod: wipe in-place, never close

## Context

When building a debug reset screen (or any "clear all data" flow), the intuitive approach is to close the database, delete the file, and reopen it. This approach **breaks every Riverpod provider** derived from `appDatabaseProvider` for the rest of the app's lifetime — streams stop emitting, DAO calls throw `database is closed`, and the app becomes unusable without a full process restart.

The underlying cause: `appDatabaseProvider` is a non-disposable Riverpod `Provider<AppDatabase>`. The singleton it returns is shared by all downstream providers (`teamsDaoProvider`, `clipsDaoProvider`, etc.). Closing the underlying database object does not update the provider's reference. After the close, every provider still hands out the old, closed `AppDatabase` instance.

## Guidance

**Keep the database connection open. Wipe the tables in a single transaction, then re-seed.**

```dart
// lib/pages/debug_page.dart — the correct reset pattern
Future<void> _reset() async {
  setState(() => _resetting = true);
  try {
    final db = ref.read(appDatabaseProvider);  // live, open connection

    // Delete in FK dependency order: children before parents.
    // CASCADE is active but we delete explicitly for clarity and safety.
    await db.transaction(() async {
      await db.delete(db.clipsTable).go();       // cascade-deletes thumbnails
      await db.delete(db.teamMatchesTable).go();
      await db.delete(db.playersTable).go();
      await db.delete(db.teamsTable).go();
      await db.delete(db.streamingDestinationsTable).go();
      await db.delete(db.sportPresetsTable).go();
      await db.delete(db.usersTable).go();
    });

    // Re-seed base data (default user + built-in sport presets).
    await db.seedBaseData();

    // Optionally re-seed mock fixtures.
    if (kUseMockData) {
      await MockDataSeeder(db).seed();
    }
  } catch (e) {
    // surface error to UI
  } finally {
    if (mounted) setState(() => _resetting = false);
  }
}
```

The provider definition for reference — note it is a plain `Provider`, not `AutoDisposeProvider`:

```dart
// lib/state/db_providers.dart
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});
```

For `seedBaseData()` to be callable from outside the database class, expose it as a public method:

```dart
// lib/db/app_database.dart
/// Re-seeds the default user and built-in sport presets.
/// Public so the debug screen can call it after wiping the DB.
Future<void> seedBaseData() => _seedBaseData();

Future<void> _seedBaseData() async {
  await usersDao.insertUser(
    UsersTableCompanion.insert(id: _kDefaultUserId, name: 'Coach'),
  );
  await sportPresetsDao.seedBuiltInsForUser(_kDefaultUserId);
}
```

## Why This Matters

**The broken approach** (close + delete + reopen):

```dart
// DON'T DO THIS — breaks all Riverpod providers
await db.close();
final file = File(p.join(dir.path, kDbName));
if (file.existsSync()) file.deleteSync();
final newDb = AppDatabase();  // local variable — provider never learns about it
await newDb.seedBaseData();
// → appDatabaseProvider still returns the closed `db`
// → every DAO call from here on throws: "database is closed"
// → the app must be restarted to recover
```

**Additional problems with the close approach:**
- SQLite WAL and SHM files (`scout_camera.sqlite-wal`, `scout_camera.sqlite-shm`) are left on disk if only the main file is deleted, causing corruption or unexpected WAL replay on the next open.
- The `newDb` instance is a local variable — it is garbage collected when `_reset()` returns, so even if you could somehow patch the provider, the new instance is gone.
- `ref.invalidate(appDatabaseProvider)` does not work on plain non-disposable `Provider` — it only works on `AutoDisposeProvider`.

**The in-place approach is correct because:**
- The `appDatabaseProvider` singleton stays valid — all downstream providers continue to reference a live, open connection.
- Drift's watch streams on wiped tables immediately emit empty lists — widgets update reactively without any manual refresh.
- The `db.transaction()` wrapper makes the wipe atomic — if the process dies mid-wipe, the database rolls back to its pre-wipe state rather than landing in a partially-wiped inconsistency.
- WAL and SHM files remain consistent because one connection manages all changes.

## When to Apply

- Building a debug or developer screen with a "Reset Database" button
- Implementing "sign out" that must clear all user-owned local data
- Factory-resetting the app state for reproducible testing or demo preparation
- Any flow where you need to clear and re-seed the database while the app continues running

## Examples

**Correct FK deletion order for this app's schema:**

The order must delete children before parents to satisfy `PRAGMA foreign_keys = ON`:

```
clips          → references team_matches (cascade also deletes thumbnails)
team_matches   → references teams
players        → references teams
teams          → references users
streaming_destinations → references users
sport_presets  → references users
users          → root table; delete last
```

A wrong order (e.g., deleting `users` before `teams`) will throw a `FOREIGN KEY constraint failed` error and roll back the entire transaction.

**Verifying the reset worked:**

After `_reset()` returns, the reactive streams from all watch providers will have already emitted updated (empty or re-seeded) values. No manual invalidation is needed:

```dart
// These all update automatically after the transaction completes:
ref.watch(teamsControllerProvider)    // emits [] then re-seeded teams
ref.watch(libraryProvider)            // emits [] then re-seeded matches
ref.watch(usersControllerProvider)    // emits [defaultUser]
```

## Related

- `lib/pages/debug_page.dart` — implementation of the reset screen using this pattern
- `lib/db/app_database.dart` — `seedBaseData()` public method and `_seedBaseData()` private implementation
- `lib/state/db_providers.dart` — `appDatabaseProvider` singleton definition
- `docs/solutions/architecture-patterns/app-source-of-truth-drift-sqlite-2026-05-06.md` — broader Drift/SQLite architecture patterns, including watch stream setup and FK pragma configuration
