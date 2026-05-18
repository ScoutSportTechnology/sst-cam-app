---
title: "fix: Showcase demo readiness — three workflow bug fixes"
type: fix
status: completed
date: 2026-05-18
origin: docs/brainstorms/2026-05-18-showcase-demo-readiness-requirements.md
---

# fix: Showcase demo readiness — three workflow bug fixes

## Summary

Three targeted fixes restore the end-to-end demo flow in mock mode (`APP_ENV=dev kUseMockData=true`): replace the stale `async*` team-only stream in `upcomingMatchesProvider` with a Drift JOIN that watches both `teamsTable` and `teamMatchesTable`; add a `kAppEnv.isDevBackend` bypass to the match setup screen's "Start match" button; and seed realistic player rosters from a new `players.json` fixture.

---

## Problem Frame

The app cannot be fully demonstrated without a physical camera. Three issues block the showcase flow: the Match tab landing never updates after a match is added or removed because `upcomingMatchesProvider` only watches `teamsTable`; the Setup → Session transition is permanently disabled without a connected BLE device; and every team's Roster tab is empty because `MockDataSeeder.seed()` never inserts players. (see origin: `docs/brainstorms/2026-05-18-showcase-demo-readiness-requirements.md`)

---

## Requirements

- R1. `upcomingMatchesProvider` re-emits whenever a `TeamMatch` row is inserted or deleted, not only when team rows change.
- R2. In dev-backend mode (`kAppEnv.isDevBackend`), the "Start match" button on the setup screen is always enabled and the transition to the session screen succeeds without a BLE-connected camera.
- R3. Mock teams have realistic player rosters after `MockDataSeeder.seed()` runs.

**Origin acceptance examples:** AE1 (covers R1 — add match appears on landing), AE2 (covers R1 — ended match leaves landing), AE3 (covers R2 — session opens without camera), AE4 (covers R3 — Roster tab populated)

---

## Scope Boundaries

- Session screen (`_SessionScreen`) is unchanged — it already works without further camera commands.
- Production and stage builds are unaffected — R2 is gated exclusively on `kAppEnv.isDevBackend`.
- No schema migration — `playersTable` already exists; no `schemaVersion` bump.
- No `gen-db` run required — the new DAO method is hand-written (mirrors `watchPastMatchesForLibrary`), not code-generated.
- `TeamRecord.roster` in `upcomingMatchesProvider` output is `const []` — the Match tab display never shows roster, so the JOIN omits `playersTable`.
- Only teams and matches are joined in the new DAO stream; a separate players subscription (as in `TeamsController`) is not added to this provider — roster-free `TeamRecord`s are sufficient for the landing, setup, and session screens.
- No changes to `DiscoveryPage`, recordings flow, `TeamsController`, or `libraryProvider`.

### Deferred to Follow-Up Work

- `_upcomingMatchesProvider` reactivity to player mutations (roster display in the upcoming-match list is not a current requirement).
- Production build flavor excluding `assets/mock/` from release APK/IPA — separate Gradle/Xcode config.

---

## Context & Research

### Relevant Code and Patterns

- `lib/db/daos/teams_dao.dart:118–144` — `watchPastMatchesForLibrary()` and `LibraryMatchRow`: the canonical JOIN `.watch()` pattern to mirror exactly.
- `lib/state/app_data.dart:882–885` — `libraryProvider`: the canonical one-liner `StreamProvider` that maps a DAO watch stream; `upcomingMatchesProvider` rewrite target shape.
- `lib/state/app_data.dart:658–696` — `upcomingMatchesProvider` current `async*` implementation to be replaced.
- `lib/widgets/live_preview_view.dart:52` — `if (kAppEnv.isDevBackend)` guard: the established pattern for dev-mode bypasses.
- `lib/db/mock_data_seeder.dart:39–52` — `_insertTeams`: pattern to follow for `_insertPlayers`.
- `lib/db/tables/teams_table.dart` — `PlayersTable` schema (PK: teamId+number; FK: teamId cascade-deletes on team delete).
- `lib/pages/debug_page.dart:49` — `db.delete(db.playersTable).go()`: already present; debug reset handles players correctly, no change needed.

### Institutional Learnings

- **Gotcha #2 / app-source-of-truth doc** (`docs/solutions/architecture-patterns/app-source-of-truth-drift-sqlite-2026-05-06.md`): Using a single-table watch (`watchForUser`) misses mutations on joined tables — the prescribed fix is a Drift JOIN watch so a single stream covers all relevant tables. `watchPastMatchesForLibrary()` already demonstrates this fix.
- **Gotcha #3 / same doc**: Any `.listen()` or `.watch()` chain in a Riverpod provider must include an `onError:` handler to avoid silently swallowed DB errors.
- **`kAppEnv.isDevBackend` is the correct gate** for dev-mode bypasses — used in `ble_providers.dart`, `wifi_providers.dart`, `live_preview_view.dart`, and `settings_page.dart`.
- **`MockDataSeeder` idempotency**: `insertOnConflictUpdate` is used throughout; the `_insertPlayers` method must use the same call so repeated seeds overwrite rather than fail.

---

## Key Technical Decisions

- **JOIN `teamsTable + teamMatchesTable` only (no `playersTable`)**: The upcoming-match display uses only `team.shortName`, `team.name`, `team.sport`, `match.opponent`, `match.date`, `match.numPeriods`, `match.periodLengthSeconds`. Roster data is never displayed in the Match tab. Adding a players left-join would produce duplicate rows per player and require grouping logic. Omitting it keeps the query simple and correct. (see origin: Key Decision — R1)
- **`Stream.value(const [])` when user is null**: Matches the existing null-guard in the `async*` body; preserves the same observable behavior for the null case without the `async*` overhead.
- **Fallback device ID `'SST-CAM-001'` in dev mode**: Exercises the full `pushSessionConfig` call path through `MockBleService` rather than skipping the push. `MockBleService.pushSessionConfig` accepts any device ID and always succeeds (unless `failNextPushSessionConfig` is set). (see origin: Key Decision — R2)
- **`kAppEnv.isDevBackend` OR-ed onto the existing `connected` boolean**: The smallest change with the least blast radius. Does not restructure `_SetupScreen`; the existing `_startMatch` logic runs unchanged with the fallback device ID.
- **Players fixture for both teams**: Both `mock-team-nr-u14` (Northridge U14) and `mock-team-efc-u14` (Eastfield FC) get realistic soccer rosters so the Teams tab is fully explorable.

---

## Open Questions

### Resolved During Planning

- **Does `debug_page.dart` already handle `playersTable` in reset?** Yes — line 49 explicitly deletes `db.playersTable` before `db.teamsTable`. No change needed.
- **Does the new DAO method require `gen-db`?** No — it follows `watchPastMatchesForLibrary()`'s hand-written join pattern; Drift code-gen only covers annotated query methods.
- **Is a separate players watch subscription needed in `upcomingMatchesProvider`?** No — the Match tab landing never displays roster data; `TeamRecord.roster = const []` is correct for this provider.

### Deferred to Implementation

- **Exact ordering `orderBy` for `watchUpcomingMatchesForUser`**: The current `async*` provider preserves natural insertion order. The new JOIN query should add `orderBy([OrderingTerm.asc(teamMatchesTable.date)])` to match the fixture data ordering, but the implementer should confirm this against the existing test expectations in `active_user_providers_test.dart`.
- **`_upcomingMatchesProvider` timing in `active_user_providers_test.dart`**: The `'excludes matches for hidden teams'` test uses two `Future.delayed(Duration.zero)` waits to let the `async*` stream propagate. After the rewrite to a direct Drift stream, the timing may differ — confirm and adjust the test if needed.

---

## Implementation Units

### U1. Add `watchUpcomingMatchesForUser` JOIN watch to `TeamsDao`

**Goal:** Give the provider a single Drift stream that fires on mutations to either `teamsTable` or `teamMatchesTable` for the active user's upcoming visible matches.

**Requirements:** R1

**Dependencies:** None

**Files:**
- Modify: `lib/db/daos/teams_dao.dart`

**Approach:**
- Add a `UpcomingMatchRow` result class at the bottom of the file, parallel to `LibraryMatchRow`: holds `TeamMatchesTableData match` and `TeamsTableData team`.
- Add `watchUpcomingMatchesForUser(String userId)` method to `TeamsDao`, modeled directly on `watchPastMatchesForLibrary()` (lines 118–136):
  - `select(teamMatchesTable).join([innerJoin(teamsTable, teamsTable.id.equalsExp(teamMatchesTable.teamId))])`
  - `.where()`: `teamMatchesTable.kind.equals('upcoming')` AND `teamsTable.hidden.equals(false)` AND `teamsTable.userId.equals(userId)`
  - `.orderBy([OrderingTerm.asc(teamMatchesTable.date)])` — ascending date so soonest match is first
  - `.watch().map((rows) => rows.map((r) => UpcomingMatchRow(match: r.readTable(teamMatchesTable), team: r.readTable(teamsTable))).toList())`
- No `@DriftAccessor` annotation change needed; the method is a hand-written join.
- No `gen-db` run needed.

**Patterns to follow:**
- `watchPastMatchesForLibrary()` and `LibraryMatchRow` in `lib/db/daos/teams_dao.dart:118–144`

**Test scenarios:**
- Happy path: given user A has one visible team with one upcoming match, `watchUpcomingMatchesForUser(userAId)` emits a list of 1 `UpcomingMatchRow` with the correct match and team data.
- Reactivity on match insert: given an initial emission of 1 upcoming match, when a second upcoming match is inserted into `teamMatchesTable` for the same team, the stream emits a second list containing 2 rows without any team mutation.
- Reactivity on match delete: given an initial emission of 1 upcoming match, when that match row is deleted, the stream emits an empty list.
- Scoping: given user A and user B each have a team with an upcoming match, `watchUpcomingMatchesForUser(userAId)` only includes user A's matches.
- Hidden teams excluded: given user A has a visible team and a hidden team, each with an upcoming match, the stream emits only the visible team's match.
- `kind = 'past'` excluded: given a team has one past match and one upcoming match, the stream emits only the upcoming match.
- Ordering: given two upcoming matches with different dates, the stream emits them ordered ascending by date.

**Verification:**
- `flutter test test/db/teams_dao_test.dart` passes with the new test group.
- No `gen-db` run required; `flutter analyze` reports no errors.

---

### U2. Rewrite `upcomingMatchesProvider` as a single reactive `StreamProvider`

**Goal:** Remove the `async*` + teams-only watch pattern and replace it with a direct mapping of the new `watchUpcomingMatchesForUser` stream, so the Match tab landing updates whenever any upcoming match row is inserted or deleted.

**Requirements:** R1

**Dependencies:** U1

**Files:**
- Modify: `lib/state/app_data.dart`
- Modify: `test/state/active_user_providers_test.dart`

**Approach:**
- Replace the `async*` body of `upcomingMatchesProvider` (lines 658–696) with a plain `StreamProvider` modeled on `libraryProvider` (lines 882–885):
  - Watch `activeUserProvider` and return `Stream.value(const [])` when `userId` is null (preserves existing null-guard behavior).
  - Watch `teamsDaoProvider` and call `dao.watchUpcomingMatchesForUser(userId)`.
  - Map each `UpcomingMatchRow` to `UpcomingMatch` via a new private helper `_rowToUpcomingMatch(UpcomingMatchRow row)` that calls `_rowToTeamRecord` with an empty players list: `_rowToTeamRecord(row.team, const [])`.
  - The existing `_rowToTeamMatch` helper is reused for the match side.
- Remove the now-unused `getTeamMatchesForTeams` and `getPlayersForTeams` calls from this provider (they were one-shot queries inside the old `async*` loop).
- Add `onError` handling if `.watch()` does not already propagate errors through Riverpod's `StreamProvider` error path (Drift's `.watch()` stream propagates errors natively; Riverpod `StreamProvider` surfaces them as `AsyncError` — verify this is sufficient or add explicit `onError` wrapping).
- Update `test/state/active_user_providers_test.dart`:
  - Verify the three existing `upcomingMatchesProvider` tests (`returns upcoming without camera`, `returns empty when null user`, `excludes hidden teams`) still pass. Adjust any `Future.delayed(Duration.zero)` timing that was specific to the `async*` propagation pattern if needed.
  - Add a new test: "re-emits when a team match row is inserted" — insert an upcoming match into the in-memory DB for an existing visible team and verify the provider emits the updated list without any team mutation.
  - Add a new test: "re-emits when a team match row is deleted" — delete a seeded upcoming match and verify the provider emits the shortened list.

**Patterns to follow:**
- `libraryProvider` at `lib/state/app_data.dart:882–885` — the exact one-liner `StreamProvider` shape to adopt.
- `_rowToLibraryMatch` at `lib/state/app_data.dart:887–916` — helper pattern for mapping DAO result rows.

**Test scenarios:**
- Covers AE1. Happy path: after the provider is active with an empty upcoming match list, inserting a `kind='upcoming'` row into `teamMatchesTable` for a visible team causes the provider to emit a list containing that match — without any change to `teamsTable`.
- Covers AE2. Happy path: after the provider emits a list with one upcoming match, deleting that row from `teamMatchesTable` causes the provider to emit an empty list.
- Happy path: when `activeUserProvider` is null, the provider emits `[]` immediately.
- Happy path: existing seeded upcoming matches are present in the initial emission on first subscription.
- Integration: `UpcomingMatch.team.shortName` and `UpcomingMatch.match.opponent` reflect the correct team and match data from the JOIN.
- Regression: existing tests for `returns empty when null user` and `excludes hidden teams` continue to pass.

**Verification:**
- `flutter test test/state/active_user_providers_test.dart` passes including new reactivity tests.
- Manually (or via integration test): adding an upcoming match via the Match tab FAB makes it appear on the landing within one render cycle.

---

### U3. Dev-mode bypass for "Start match" in `_SetupScreen`

**Goal:** Allow the full match setup → session flow to complete in `APP_ENV=dev` without a BLE-connected camera.

**Requirements:** R2

**Dependencies:** None (independent of U1/U2)

**Files:**
- Modify: `lib/pages/match_page.dart`

**Approach:**
- Add `import '../env.dart';` to the import block in `match_page.dart`.
- In `_SetupScreenState.build()`, change the `connected` derivation so it is `true` whenever `kAppEnv.isDevBackend`:
  ```
  final connected = kAppEnv.isDevBackend || (activeId != null && connectionStateProvider(activeId).valueOrNull == CameraConnectionState.connected)
  ```
- In `_startMatch()`, update the early-return guard:
  - When `deviceId` is null and `kAppEnv.isDevBackend`, assign the fallback ID `'SST-CAM-001'` instead of returning.
  - When `deviceId` is null and NOT in dev backend, keep the existing `return` behavior.
- Gate the "Connect a camera to start the match." helper text: only render when `!kAppEnv.isDevBackend && !connected`.
- Gate the Retry button similarly: `onPressed: (connected || kAppEnv.isDevBackend) ? () => _startMatch(...) : null`.
- `_userUuid` guard (`if (userUuid == null) return`) is unchanged — the active user must still exist.

**Patterns to follow:**
- `lib/widgets/live_preview_view.dart:52` — `if (kAppEnv.isDevBackend)` guard structure.
- `lib/ble/ble_providers.dart:18` — `kAppEnv.isDevBackend` backend selection.

**Test scenarios:**
- Covers AE3. Integration: given `kAppEnv.isDevBackend` and no camera connected (`activeCameraIdProvider == null`), when the user selects an upcoming match and taps "Start match", the session screen (`_SessionScreen`) is rendered — no error, no disabled button.
- Edge case: given `kAppEnv.isDevBackend` and a camera IS connected, the existing connected path still works (no regression in `match_page_test.dart`).
- Happy path (prod/stage): given `!kAppEnv.isDevBackend` and no camera, the "Start match" button is disabled and the "Connect a camera" hint is visible.
- Regression: all existing `test/pages/match_page_test.dart` tests pass — they already inject a connected camera state, so the bypass does not affect them.

**Verification:**
- `flutter analyze` passes (no missing import, no type error on the fallback device ID).
- `flutter test test/pages/match_page_test.dart` passes without modification.
- Manually: in `APP_ENV=dev`, selecting an upcoming match and tapping "Start match" transitions to the session screen.

---

### U4. Players fixture data in `MockDataSeeder`

**Goal:** Seed realistic player rosters for both mock teams so the Teams tab Roster sub-tab shows populated lists after `kUseMockData=true` startup or debug reset.

**Requirements:** R3

**Dependencies:** None (independent of U1–U3; `playersTable` FK depends on `teamsTable` which is seeded first)

**Files:**
- Create: `assets/mock/fixtures/players.json`
- Modify: `lib/db/mock_data_seeder.dart`

**Approach:**
- **`players.json`**: Create with players for both teams. Soccer-appropriate data — 11–13 players per team, one captain per team, positions from `kPlayerPositions` (`Keeper`, `Defender`, `Mid`, `Forward`). Field schema matches `PlayersTable`: `teamId` (String), `number` (int), `name` (String), `position` (String), `captain` (bool, optional — omit for false). Use the comment-header convention from other fixtures.
- **`MockDataSeeder.seed()`**: Add `_loadFixture('players')` to the `Future.wait` list (4th future). Add `await _insertPlayers(results[3])` inside the transaction, between `_insertTeams` and `_insertMatches` (players FK-depend on teams; matches have no dependency on players).
- **`_insertPlayers` method**: follows `_insertTeams` exactly — iterate rows, call `_db.into(_db.playersTable).insertOnConflictUpdate(PlayersTableCompanion.insert(...))`. The `captain` field uses `Value(row['captain'] as bool? ?? false)`.
- **`debug_page.dart`**: Already deletes `db.playersTable` at line 49 before `db.teamsTable` — no change needed (confirmed).
- **`pubspec.yaml`**: No change needed — `assets/mock/fixtures/` is already declared as a Flutter asset directory.

**Patterns to follow:**
- `_insertTeams` in `lib/db/mock_data_seeder.dart:39–52`.
- `PlayersTableCompanion.insert` parameter list (from `lib/db/tables/teams_table.dart`).
- Comment-header convention in existing `.json` fixture files.

**Test scenarios:**
- Covers AE4. Happy path: after `MockDataSeeder(db).seed()` runs on an in-memory DB with the default user and both mock teams pre-seeded, querying `db.select(db.playersTable).get()` returns at least 10 rows.
- Happy path: players for `mock-team-nr-u14` and `mock-team-efc-u14` are both present — at least one row per team ID.
- Happy path: exactly one player per team has `captain = true`.
- Idempotency: calling `seed()` twice does not throw (each insert uses `insertOnConflictUpdate`).
- Integration: after `debug_page.dart`'s `_reset()` followed by `MockDataSeeder.seed()`, `db.playersTable` is populated (not empty).

**Verification:**
- `flutter test` passes (no new fixture-loading errors).
- Manually: in the Teams tab, tapping a mock team and navigating to the Roster sub-tab shows the player list.

---

## System-Wide Impact

- **`upcomingMatchesProvider` consumers**: `_LandingScreen` (Match tab), `_SetupScreen` (match setup). Both watch the provider reactively — no call-site changes needed.
- **`liveMatchProvider.loadFromUpcoming`**: Receives `UpcomingMatch` with a roster-empty `TeamRecord`. `loadFromUpcoming` uses only `team.shortName` and `match.*` fields — unaffected.
- **`TeamsController` and `teamMatchesProvider`**: Unchanged — these already watch the correct tables independently.
- **`libraryProvider`**: Unchanged — uses `watchPastMatchesForLibrary` which is not touched.
- **Unchanged invariants**: `TeamsController` write methods (`addMatch`, `removeMatch`) remain the sole writers to `teamMatchesTable`. The new DAO method is read-only. `upcomingMatchesProvider` remains a read-only `StreamProvider` — no mutation surface added.
- **Error propagation**: Drift `.watch()` propagates errors through the stream; Riverpod `StreamProvider` surfaces them as `AsyncError` to the UI. The existing `async.when(error: ...)` handler in `_LandingScreen.build()` already handles this.
- **State lifecycle**: The `ref.onDispose` cancel on the `teamSub` / `playerSub` subscriptions in `TeamsController` is unrelated to the provider rewrite — `StreamProvider` manages its own subscription lifecycle.

---

## Risks & Dependencies

| Risk | Mitigation |
|------|------------|
| `active_user_providers_test.dart` timing assumptions break after `async*` → `StreamProvider` rewrite | Tests use `Future.delayed(Duration.zero)` to yield. Drift in-memory watch streams emit synchronously in tests. Verify timing on first run; adjust to `await tester.pump()` or stream-first pattern if needed. |
| `orderBy(date ASC)` changes the emission order vs. current provider | Current `async*` yields in teams-stream order (insertion order). New order is ascending date. Verify test fixtures produce the same ordering; update test assertions if they assume insertion order. |
| `kAppEnv` is a compile-time const — `kAppEnv.isDevBackend` evaluates at tree-shake time | This is the intended behavior. Stage/prod builds dead-code-eliminate the bypass path. No runtime risk. |
| `players.json` FK violation if team IDs in the file don't match teams.json | Use only `"mock-team-nr-u14"` and `"mock-team-efc-u14"` — the two IDs present in `teams.json`. Review fixture before committing. |

---

## Sources & References

- **Origin document:** [docs/brainstorms/2026-05-18-showcase-demo-readiness-requirements.md](docs/brainstorms/2026-05-18-showcase-demo-readiness-requirements.md)
- **Architecture learning:** [docs/solutions/architecture-patterns/app-source-of-truth-drift-sqlite-2026-05-06.md](docs/solutions/architecture-patterns/app-source-of-truth-drift-sqlite-2026-05-06.md)
- **DB reset learning:** [docs/solutions/architecture-patterns/riverpod-drift-db-reset-in-place-2026-05-11.md](docs/solutions/architecture-patterns/riverpod-drift-db-reset-in-place-2026-05-11.md)
- Pattern reference: `lib/db/daos/teams_dao.dart:118–144` (`watchPastMatchesForLibrary`)
- Pattern reference: `lib/state/app_data.dart:882–885` (`libraryProvider`)
- Pattern reference: `lib/widgets/live_preview_view.dart:52` (`kAppEnv.isDevBackend` guard)
