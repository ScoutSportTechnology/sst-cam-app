---
title: App as Source of Truth — Drift SQLite + Stateless BLE Executor
date: 2026-05-06
category: docs/solutions/architecture-patterns/
module: data-persistence
problem_type: architecture_pattern
component: database
severity: high
applies_when:
  - Deciding where business data (teams, users, matches, presets) lives in a BLE-connected embedded-system companion app
  - Choosing between device-side and phone-side persistence
  - Designing a BLE service interface for a stateless hardware executor
  - Implementing Riverpod state management backed by a local reactive database
  - Adding multi-phone data portability to a local-first app without a server
tags:
  - drift
  - sqlite
  - local-first
  - ble
  - riverpod
  - source-of-truth
  - backup-restore
  - watch-stream
related_components:
  - testing_framework
  - development_workflow
---

# App as Source of Truth — Drift SQLite + Stateless BLE Executor

## Context

The original ScoutCamera app was designed as a thin BLE client: all business data — teams,
rosters, players, sport presets, streaming destinations, and match history — lived on the
camera. The phone displayed whatever the camera reported and issued CRUD commands in response
to user actions.

This created compounding friction as the feature set grew:

- Data was inaccessible when the camera was off or out of BLE range
- Historical match results could not be browsed between sessions
- Moving to a new phone meant losing everything; no export path existed
- Forms could not be pre-populated or validated without a live BLE connection
- Camera firmware carried schema complexity that belonged in the app
- `BleService` had 20+ abstract CRUD methods, making the interface unwieldy

*(auto memory [claude]: the memory entry "teams/rosters/match history are camera-side;
phone is a thin BLE client" describes this pre-refactor state — it is now stale.)*

The refactor resolved this by inverting ownership: the app owns all persistent data via a
local Drift SQLite database, and the camera becomes a stateless executor configured fresh at
the start of each session.

---

## Guidance

### Ownership boundary

Divide data into two strict categories and never let them cross:

**App owns (persisted in Drift SQLite across sessions):**
- Users (UUID-keyed, no authentication, used to scope all other records)
- Teams, rosters, players
- Matches (scheduled and historical results)
- Sport format config (type, period count, period duration)
- Streaming credentials (RTMP URL + stream key per platform)
- Clip and thumbnail metadata + references to on-device file paths

**Camera owns (in-memory only, forgotten at session end):**
- Current active match UUID and output paths
- Active sport config and streaming keys for the running session
- File system recordings at `/data/video/{user_uuid}/{match_uuid}/...`

The camera never writes back to the app database. Files are the only output it produces.

### Session flow

At session start the app pushes everything the camera needs via a single `pushSessionConfig`
BLE call:

```dart
await ble.pushSessionConfig(deviceId, PushSessionConfig(
  matchUuid: uuid.v4(),
  userUuid: activeUser.id,
  sport: matchConfig.sport,
  numPeriods: matchConfig.numPeriods,
  periodLengthSeconds: matchConfig.periodLengthSeconds,
  rtmpUrl: streamingDest?.rtmpUrl,
  streamKey: streamingDest?.streamKey,
  videoOutputPath: '/data/video/$userUuid/$matchUuid/',
  thumbnailOutputPath: '/data/thumbnail/$userUuid/$matchUuid/',
));
```

The camera acknowledges, records/streams with those parameters, and forgets them on
disconnect. `pushSessionConfig` replaces all 20+ former BLE CRUD methods.

### Controller pattern: watch streams instead of pull + refresh

Before, controllers used `AsyncNotifier` with an explicit `_refresh()` that fetched from BLE
on every mutation. After, controllers subscribe to Drift watch streams, which emit
automatically on any DB write — no manual refresh needed.

**Before (BLE pull model):**
```dart
class TeamsController extends AsyncNotifier<List<TeamRecord>> {
  @override
  Future<List<TeamRecord>> build() async {
    final deviceId = ref.watch(activeCameraIdProvider);
    if (deviceId == null) return const [];
    return ref.watch(bleServiceProvider).listTeams(deviceId);
  }

  Future<void> create(TeamDraft draft) async {
    await ref.read(bleServiceProvider).createTeam(_requireDevice(), draft);
    await _refresh(); // manual round-trip required
  }
}
```

**After (Drift watch-stream model):**
```dart
class TeamsController extends AsyncNotifier<List<TeamRecord>> {
  @override
  Future<List<TeamRecord>> build() async {
    final userId = ref.watch(activeUserProvider);
    if (userId == null) return const [];
    final dao = ref.watch(teamsDaoProvider);
    // Subscribe; Drift emits on every mutation — no _refresh() anywhere
    final sub = dao.watchForUser(userId).skip(1).listen(
      (rows) => state = AsyncValue.data(_rowsToRecords(rows)),
      onError: (Object e, StackTrace st) => state = AsyncValue.error(e, st),
    );
    ref.onDispose(sub.cancel);
    return _rowsToRecords(await dao.getForUser(userId));
  }

  Future<void> create(TeamDraft draft) async {
    await ref.read(teamsDaoProvider).insertTeam(_toCompanion(draft));
    // No _refresh() — watch stream fires automatically
  }
}
```

No `activeCameraIdProvider` dependency in data controllers. Data is always available,
even offline.

### Multi-phone (v1): no server required

Backup/Restore lives in Settings and is accessible regardless of camera connection.

- **Export** — serializes full Drift DB to `sst-backup-YYYY-MM-DD-HHmm.json` in the app's
  documents directory. Optionally embeds `device.uuid` via `GetDeviceInfoCommand` if a camera
  is connected; omits it if not.

- **Restore** — parses the JSON, validates `backup_version == 1`, and when `device.uuid` is
  present in the backup it must match the currently connected camera (prevents cross-team
  restore). Import runs in a single `db.transaction()` — full DELETE + INSERT — so failure
  never leaves partial data:

```dart
await db.transaction(() async {
  // Delete in FK order (children first)
  await db.delete(db.thumbnailsTable).go();
  await db.delete(db.clipsTable).go();
  await db.delete(db.teamMatchesTable).go();
  // ... other tables ...
  // Bulk insert from backup JSON
  await db.batch((b) {
    b.insertAll(db.usersTable, userCompanions);
    b.insertAll(db.teamsTable, teamCompanions);
    // ...
  });
});
```

---

## Why This Matters

**Availability** — App data is available without a camera connection. Coaches browse rosters,
review match history, and configure upcoming matches between sessions.

**Reliability** — Drift streams mean the UI is always consistent with the database. No cache
invalidation, no stale state after BLE disconnect, no need to coordinate refresh calls across
screens.

**Correct ownership semantics** — Business data (team names, sport configs, streaming keys)
is app data, not camera data. The camera is a recording device. Storing business data on it
was a category error that inflated BLE protocol surface area and firmware complexity.

**Firmware simplicity** — The camera no longer needs to persist, index, or serve business
objects. It receives a config blob, acts on it, and forgets it. `BleService` went from 20+
CRUD methods to 1 session-push method.

---

## When to Apply

Use this pattern when:

- The external device is a **data producer** (recordings, sensor readings) but not a data
  owner
- Business entities are created and managed in the app, not on the device
- Users expect data to survive across device connections, app restarts, or hardware
  replacements
- The device has no persistent storage guarantees or its storage model is opaque to the app
- Multiple phones may need to share or transfer data (export/restore covers this without a
  server)

Do **not** apply if the device is the canonical source of truth (e.g., a heart rate monitor
that owns its own history, or firmware that enforces its own config schema and rejects
external pushes).

---

## Examples

### Schema: FK cascade enforces ownership

```dart
class TeamsTable extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text().references(UsersTable, #id,
      onDelete: KeyAction.cascade)(); // delete user → all teams deleted
  TextColumn get name => text()();
  // ...
  @override
  Set<Column> get primaryKey => {id};
}
```

**Critical:** SQLite disables FK enforcement by default. Enable it in `beforeOpen`:
```dart
beforeOpen: (db) async {
  await db.customStatement('PRAGMA foreign_keys = ON');
  await db.customStatement('PRAGMA journal_mode = WAL');
},
```
Without `PRAGMA foreign_keys = ON`, cascade deletes silently do nothing.

### Test harness: in-memory Drift replaces DevDataStore

```dart
// test/test_helpers.dart
AppDatabase useInMemoryDb() {
  late AppDatabase db;
  setUp(() async {
    db = AppDatabase.forTesting(
      // closeStreamsSynchronously prevents lingering timer failures in widget tests
      DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true),
    );
    await _seedTestData(db); // same user/team/preset data as the old DevDataStore.reset()
  });
  tearDown(() => db.close());
  return db;
}

// In any test:
final db = useInMemoryDb();
ProviderScope(
  overrides: [appDatabaseProvider.overrideWithValue(db)],
  child: const ScoutCameraApp(),
)
```

---

## Gotchas

These bugs were caught during code review of the initial implementation. Each is a
non-obvious trap specific to this pattern:

**1. Preset ID collision with shared-PK seeding**
`seedBuiltInsForUser()` used hardcoded IDs (`'preset-soccer-std'`) as the sole primary key.
`insertOnConflictUpdate` on a 2nd user silently reassigned all 7 built-in preset rows to
the new `userId`. User 1 ended up with 0 built-in presets — no error.
Fix: composite PK `{id, userId}` with per-user IDs (e.g., `'$userId-preset-soccer-std'`).

**2. watchForUser only watches one table**
A `TeamsDao.watchForUser()` backed by a single-table `SELECT FROM teams WHERE userId = ?`
watch does not fire when `players` rows change. Roster mutations leave the UI stale.
Fix: use a Drift join watch across both tables, or subscribe to a second stream on the
`players` table and combine with `combineLatest`.

**3. Missing onError on stream listeners**
`.listen((rows) { state = ...; })` without `onError:` silently swallows Drift stream errors
(DB closed, schema migration failure). UI shows stale data with no indication.
Fix: always add `onError: (Object e, StackTrace st) { state = AsyncValue.error(e, st); }`.

**4. Non-atomic player update**
`updatePlayer` implemented as `deletePlayer(id)` + `insertPlayer(...)` without a wrapping
transaction. A failure between the two permanently deletes the player.
Fix: `await db.transaction(() async { await dao.deletePlayer(...); await dao.insertPlayer(...); })`.

**5. N+1 queries in watch-stream handlers**
Calling `getPlayersForTeam(teamId)` inside a `for` loop over teams fires O(N) sequential
queries on every DB mutation. With 10 teams, that's 10 SQLite round-trips per event.
Fix: add a bulk DAO method (`getPlayersForTeams(List<String> teamIds)`) and group in Dart.

**6. Path traversal in restore UI**
Passing a user-typed file path directly to `File(path).readAsString()` allows reading
arbitrary files on rooted/jailbroken devices.
Fix:
```dart
final canonical = p.canonicalize(path);
final docsDir = (await getApplicationDocumentsDirectory()).path;
if (!canonical.startsWith(docsDir)) {
  // reject — show error
  return;
}
```

---

## Related

- `docs/brainstorms/app-as-source-of-truth-requirements.md` — upstream requirements doc
- `docs/plans/2026-05-05-003-refactor-app-source-of-truth-plan.md` — implementation plan (completed)
- Drift 2.20 docs — https://drift.simonbinder.eu
