---
title: "BackupService silently drops new Drift columns not added to serializers"
date: 2026-05-19
category: docs/solutions/database-issues/
module: database
problem_type: database_issue
component: database
severity: high
symptoms:
  - "After export→import, a column's data reverts to its DEFAULT value for all rows"
  - "No error is thrown; data loss is silent and only visible by inspecting rows post-restore"
  - "Column exists in Drift schema and the SQLite file, but backup JSON omits it"
root_cause: missing_workflow_step
resolution_type: code_fix
tags:
  - backup-restore
  - drift
  - sqlite
  - schema-migration
  - data-loss
related_components:
  - database
---

# BackupService silently drops new Drift columns not added to serializers

## Problem

`BackupService` serializes the entire Drift database to JSON (export) and restores it from JSON (import) using raw `Map<String, dynamic>` serialization. It is not derived from the Drift schema automatically — every column must be explicitly listed in both the export method and the import companion.

When schema v2 added `eventsJson TEXT NOT NULL DEFAULT '[]'` to the `team_matches` table, `BackupService._rowToMatchJson` and `_parseMatches` were not updated. Any export→import cycle silently discarded the `events_json` column data. No exception was thrown; the column simply reverted to `'[]'` for every match after a restore.

## Symptoms

- After a backup/restore cycle, specific column data (e.g., match events) disappears from all rows.
- The app shows no error; the affected data simply reverts to its default value.
- The Drift schema and SQLite file are correct (column exists), but the backup JSON omits it.
- The fallback `as String? ?? defaultValue` style in `_parseMatches` swallows the missing key silently.

## What Didn't Work

There is no compile-time or runtime enforcement that `BackupService` covers all columns. Drift's generated code knows about the column; `BackupService` does not. Adding the Drift migration step alone (table definition + `onUpgrade`) compiles and runs cleanly with no warnings. The omission is only discovered after a user performs an export followed by a restore.

Searching for the column name in `backup_service.dart` would have revealed the omission immediately — but there was no checklist or test enforcing this.

## Solution

Two edits to `lib/services/backup_service.dart` whenever a column is added to a table that `BackupService` serializes:

**Export — add the new column to the row-to-map method:**
```dart
// Inside _rowToMatchJson (or the equivalent method for the affected table):
{
  // ... existing columns ...
  'events_json': m.eventsJson,  // add this
}
```

**Import — add the new column to the Companion construction:**
```dart
// Inside _parseMatches (or the equivalent method for the affected table):
TeamMatchesTableCompanion.insert(
  // ... existing columns ...
  eventsJson: Value(m['events_json'] as String? ?? '[]'),  // add this
)
```

The `?? '[]'` fallback handles backward compatibility: backup files exported before schema v2 will not have the key, so they restore cleanly with the default value rather than crashing.

## Why This Works

`BackupService` uses manual JSON serialization — it mirrors the schema rather than deriving from it. The Drift-generated `TeamMatchesTableCompanion` accepts a `Value<T>` for each column; any column omitted from the companion receives its `DEFAULT` value (`'[]'` for `eventsJson`). This is correct for new rows but wrong for restored rows that had non-default data.

## Prevention

**Rule:** Every new non-nullable column added to any Drift table that `BackupService` serializes must be added to `BackupService` in the same commit — both the export map and the import companion.

**Checklist for migration PRs:**
1. Add column to Drift table definition (`lib/db/tables/`)
2. Add migration step in `AppDatabase.migration` (`lib/db/app_database.dart`)
3. Add column to the export method in `BackupService` (e.g., `_rowToMatchJson`)
4. Add column to the import companion in `BackupService` (e.g., `_parseMatches`)
5. Add or update a round-trip test in `test/services/backup_service_test.dart`

**Round-trip test pattern:**
```dart
test('match export/import round-trips eventsJson', () async {
  const eventsJson = '[{"type":"goal","team":"home","minute":23}]';
  await dao.insertMatch(TeamMatchesTableCompanion.insert(
    // ... required fields ...
    eventsJson: Value(eventsJson),
  ));

  final backup = await backupService.exportToJson();
  await dao.deleteAll();
  await backupService.importFromJson(backup);

  final restored = await dao.allMatches();
  expect(restored.first.eventsJson, equals(eventsJson));
});
```

This test would have caught the regression immediately. Add one per non-trivial column added to any backed-up table.

## Related Issues

- `lib/services/backup_service.dart` — serializer; all tables must be kept in sync
- `lib/db/app_database.dart` — migration where new columns are added
- `docs/solutions/architecture-patterns/app-source-of-truth-drift-sqlite-2026-05-06.md` — architectural overview of the backup/restore design
