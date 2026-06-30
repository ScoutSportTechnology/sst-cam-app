---
module: lib/core/db
date: 2026-06-29
problem_type: convention
component: testing_framework
severity: medium
tags:
  - drift
  - sqlite
  - migration
  - schema-version
  - onupgrade
  - oncreate
  - in-memory-test
  - testing
  - database
applies_when: >
  Adding or changing a Drift onUpgrade migration in lib/core/db/app_database.dart
  (an `if (from < N)` ALTER/createTable block). Tests that build the DB through
  test/test_helpers.dart `useInMemoryDb()` / `AppDatabase.forTesting(NativeDatabase.memory())`
  open a fresh DB at the current schemaVersion and run only onCreate (`m.createAll()`)
  — they never exercise onUpgrade, so a migration ships uncovered and a broken
  ALTER passes CI green yet crashes on-device upgrade of existing installs.
---

# Test Drift onUpgrade migrations with raw SQL — the in-memory helper only runs onCreate

## Context

App tests build the database through `useInMemoryDb()` in `test/test_helpers.dart`:

```dart
ref._db = AppDatabase.forTesting(
  DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true),
);
```

A fresh in-memory `AppDatabase` opens at the **current** `schemaVersion` (5) and so runs
**only** the `onCreate` branch of the `MigrationStrategy` — `m.createAll()` builds every
table at its latest shape in one shot. `onUpgrade` is never reached, because the DB was
never at an older version. The whole `onUpgrade` ladder in `lib/core/db/app_database.dart`
therefore ships **uncovered**:

```dart
onUpgrade: (m, from, to) async {
  await transaction(() async {
    ...
    if (from < 5) {
      // v4→v5: per-match streaming credential. Nullable — existing matches have none.
      await customStatement('ALTER TABLE team_matches ADD COLUMN rtmp_url TEXT');
      await customStatement('ALTER TABLE team_matches ADD COLUMN stream_key TEXT');
    }
  });
},
```

Every DAO test, widget test, and the streaming round-trip tests pass — they all run against
a freshly `createAll()`'d v5 schema where `rtmp_url`/`stream_key` already exist as columns.
None exercises the `ALTER TABLE`. A typo in the migration SQL (wrong column/table, a
`NOT NULL` add without a default) is invisible to CI and crashes on the first launch of an
existing install after the app update. Two reviewers flagged exactly this gap when the v4→v5
schema bump landed.

## Guidance

For every new `onUpgrade` branch, add a focused test that runs the migration's **actual SQL**
against a **hand-built prior-schema table** seeded with a pre-existing row, then asserts the
new columns exist and the old data survives. Drift in-memory DBs can't help (they only run
`onCreate`), so drop to raw `package:sqlite3` — already pulled in transitively by drift.

`test/core/db/match_streaming_migration_test.dart`:

```dart
// hide isNull: drift exports an isNull query helper that collides with the
// matcher of the same name used below.
import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';
// sqlite3 is transitive via drift; used here only to drive the raw migration SQL.
// ignore: depend_on_referenced_packages
import 'package:sqlite3/sqlite3.dart';

test('v4→v5 ALTER adds nullable creds + preserves existing rows', () {
  final raw = sqlite3.openInMemory();
  // team_matches as it existed at schemaVersion 4 (no credential columns).
  raw.execute('''
    CREATE TABLE team_matches (
      id TEXT NOT NULL PRIMARY KEY, team_id TEXT NOT NULL, opponent TEXT NOT NULL,
      date TEXT NOT NULL, result TEXT NOT NULL, kind TEXT NOT NULL,
      num_periods INTEGER NOT NULL, period_length_seconds INTEGER NOT NULL,
      clips INTEGER NOT NULL DEFAULT 0, size_mb INTEGER NOT NULL DEFAULT 0,
      events_json TEXT NOT NULL DEFAULT '[]'
    )''');
  raw.execute(
    "INSERT INTO team_matches (id, team_id, opponent, date, result, kind, "
    "num_periods, period_length_seconds) "
    "VALUES ('m1','t1','Foo','2026-01-01','-','upcoming',2,2100)",
  );

  // The EXACT statements from app_database.dart onUpgrade `if (from < 5)`.
  raw.execute('ALTER TABLE team_matches ADD COLUMN rtmp_url TEXT');
  raw.execute('ALTER TABLE team_matches ADD COLUMN stream_key TEXT');

  final rows = raw.select(
    'SELECT rtmp_url, stream_key, opponent FROM team_matches WHERE id = ?', ['m1']);
  expect(rows, hasLength(1));
  expect(rows.first['rtmp_url'], isNull);   // new column, null on old row
  expect(rows.first['stream_key'], isNull);
  expect(rows.first['opponent'], 'Foo');    // existing data preserved
  // ignore: deprecated_member_use
  raw.dispose();
});
```

What makes it work:

- **Build the *prior* schema by hand** — the `CREATE TABLE` here is the v4 shape, deliberately
  omitting the new columns. That is the snapshot the migration upgrades.
- **Seed a pre-existing row before the ALTER.** Without it you only prove columns can be added
  to an *empty* table; the `opponent == 'Foo'` assertion is the data-survival check.
- **Run the *exact* ALTER SQL** copied from the `if (from < N)` block — not a paraphrase, or the
  test stops protecting the production statement.
- **Two import gotchas:** `hide isNull` (drift's query helper vs `flutter_test`'s matcher) and
  `// ignore: depend_on_referenced_packages` (sqlite3 is only a transitive dep).

The companion `useInMemoryDb()` tests in the same file verify *current-version* behavior; by
construction they never touch the ALTER path — which is why the raw-sqlite3 test exists.

**Durable alternative:** drift's schema-fixture tooling (`drift_dev schema dump` → versioned
`drift_schema_vN.json` → `SchemaVerifier`/`verifySelfMigration`) generates prior schemas for
you and tests every version step. Prefer it once the migration count grows; the raw-sqlite3
pattern is the lightweight per-migration stopgap.

## Why This Matters

A green CI with an untested migration is a false signal: every test runs against a
`createAll()`'d current schema where the new columns already exist, so 100% of
DAO/widget/round-trip tests pass while the `onUpgrade` ALTER is broken. The break only
manifests for **existing installs on app update** — the users you can't afford to crash, on
the one path no other test covers. The bug is silent in CI and the simulator (both
create-fresh), then surfaces as a hard launch crash in the field after a store update. A few
lines of raw SQL convert an invisible on-device-only failure into a deterministic unit-test
failure.

## When to Apply

Whenever a Drift migration is added — any change that bumps `schemaVersion` and adds an
`if (from < N)` branch to `onUpgrade` (`ALTER TABLE`, `m.createTable(...)`, index creation, data
backfill). For each new branch, add a raw-sqlite3 test that builds the `N-1` schema, seeds a
row, runs the exact `from < N` statements, and asserts the new shape plus old-row survival.
Watch especially for: `NOT NULL` adds (need a `DEFAULT`, else they fail on non-empty tables),
renamed/dropped columns (SQLite's limited `ALTER`), and multi-statement branches where ordering
matters.

## Related

- [[backup-service-silent-column-omission-on-schema-change-2026-05-19]] — sibling: a schema
  change that compiled + migrated clean but went unverified (the backup serializer). Its
  migration-PR checklist is the natural home for a "test the `onUpgrade` migration itself" step.
- [[sqlite-filename-rename-data-loss-2026-05-11]] — explains the `onUpgrade`-vs-`onCreate` trigger
  semantics this convention relies on (`onUpgrade` fires only when an existing file opens at a
  higher `schemaVersion`).
- [[app-source-of-truth-drift-sqlite-2026-05-06]] — the Drift/SQLite architecture umbrella for
  this cluster.
