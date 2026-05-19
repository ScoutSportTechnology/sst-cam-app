---
title: SQLite filename rename causes silent data loss on upgrade
date: 2026-05-11
category: database-issues
module: Database initialization
problem_type: database_issue
component: database
symptoms:
  - App starts fresh with no data after an update
  - Old SQLite file exists on disk but is never opened
  - Users report all their data was deleted after an app update
  - No error message or migration prompt appears
root_cause: config_error
resolution_type: code_fix
severity: critical
tags: sqlite, drift, flutter, data-loss, migration, filename, upgrade, lazy-database
---

# SQLite filename rename causes silent data loss on upgrade

## Problem

Changing the SQLite database filename constant (`kDbName`) causes a fresh empty database to be created at the new path on existing installs. The old database file remains on disk but is never opened, silently abandoning all user data with no error or warning.

## Symptoms

- App starts with a completely blank state after updating — users see only the base seed data (default user, built-in sport presets)
- Old database file (e.g., `scout_camera.sqlite`) still exists in `getApplicationSupportDirectory()` but the app never reads it
- No crash, no error message, no data migration prompt — the app appears to work normally
- Problem is invisible in development (fresh installs work fine) but catastrophic for existing users

## What Didn't Work

- Relying on Drift's `onUpgrade` migration — `onUpgrade` only fires when the same file is opened with a higher `schemaVersion`. If the file doesn't exist at all, `onCreate` runs instead, producing a fresh empty database.
- Assuming SQLite or Flutter automatically migrates data across filenames — they do not. Each filename is an independent file on disk.
- Bumping `schemaVersion` — this is irrelevant when the file path changes; Drift opens whatever file it is given.

## Solution

In `_openConnection()`, check for the old filename before opening the new one. If the old file exists and the new one does not, rename it atomically:

```dart
// lib/db/app_database.dart
LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationSupportDirectory();
    // One-time migration: rename the old file to kDbName so existing installs
    // keep their data. File.rename() is an atomic POSIX move on the same
    // filesystem — zero data loss on success.
    final oldFile = File(p.join(dir.path, 'scout_camera.sqlite'));
    final file = File(p.join(dir.path, kDbName));
    if (oldFile.existsSync() && !file.existsSync()) {
      await oldFile.rename(file.path);
    }
    return NativeDatabase.createInBackground(file);
  });
}
```

The filename constant lives in `lib/app_config.dart` as a single source of truth:

```dart
// lib/app_config.dart
const String kDbName = 'sst_cam.sqlite';
```

For a chain of renames (e.g., a second rename in the future), add another check before the existing one:

```dart
// Rename v1 → v2
final v1File = File(p.join(dir.path, 'scout_camera.sqlite'));
final v2File = File(p.join(dir.path, 'sst_cam.sqlite'));
if (v1File.existsSync() && !v2File.existsSync()) {
  await v1File.rename(v2File.path);
}
// Rename v2 → v3 (hypothetical future rename)
final v3File = File(p.join(dir.path, kDbName));
if (v2File.existsSync() && !v3File.existsSync()) {
  await v2File.rename(v3File.path);
}
```

## Why This Works

`LazyDatabase` defers the actual file open to the first query. By placing the rename check inside the `LazyDatabase` factory, the migration runs at the correct moment — after the support directory is resolved, before Drift opens any connection. The guard `oldFile.existsSync() && !file.existsSync()` makes the rename idempotent: if the old file is gone or the new file already exists, nothing happens. On POSIX systems (Android, iOS), `File.rename()` within the same filesystem is an atomic metadata operation — there is no window where neither file exists.

Because the rename happens before `NativeDatabase.createInBackground(file)` is called, Drift sees the renamed file as the database to open. Its `schemaVersion`, migration history, and all data are intact. Drift's normal `onCreate`/`onUpgrade` logic then runs against the renamed file as expected.

## Prevention

- **Define the DB filename as a named constant** (`kDbName` in `lib/app_config.dart`) — never hardcode the string in `_openConnection()`. When you change the constant, the rename check is the only other place to update.
- **Add a rename check when changing `kDbName`** — treat it the same way you treat a schema migration: write the shim at the same time as the constant change.
- **Never remove old rename checks** — leave them in place indefinitely. A user who skipped multiple updates may arrive at the current version from any previous state; the chain of renames must remain complete.
- **Test upgrade scenarios locally** — before shipping a rename, manually create an old-named file in the simulator's support directory and verify the app opens it correctly at the new name.
- **Document the rename history in a comment** — add a comment block above the rename chain noting when each rename was introduced and why (e.g., `// 2026-05-11: renamed scout_camera.sqlite → sst_cam.sqlite during app rebrand`).

## Related Issues

- `lib/app_config.dart` — `kDbName` constant (single source of truth for the filename)
- `lib/db/app_database.dart` — `_openConnection()` implementation
- `docs/solutions/architecture-patterns/app-source-of-truth-drift-sqlite-2026-05-06.md` — broader Drift/SQLite architecture patterns for this app
