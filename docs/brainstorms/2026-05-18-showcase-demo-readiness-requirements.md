---
date: 2026-05-18
topic: showcase-demo-readiness
---

# Showcase Demo Readiness — Three Workflow Bug Fixes

## Summary

Three confirmed bugs prevent the app from running end-to-end in showcase/demo mode:
the Match tab landing does not react to new or deleted upcoming matches; the match setup
screen is blocked without a BLE camera; and mock teams have empty rosters. Fixing these
three issues makes the full match workflow — schedule → setup → session → end — runnable
with mock data and no real hardware.

---

## Problem Frame

The app is intended to be demonstrable with mock data and no physical camera (`APP_ENV=dev
kUseMockData=true`). Three workflows remain broken:

1. **Match landing does not update after "Add match"** — `upcomingMatchesProvider` watches
   only `teamsTable`. Adding an upcoming match only touches `teamMatchesTable`, so the landing
   list never reacts. The data is saved (it appears immediately in the Teams tab → Matches
   sub-tab, which uses `teamMatchesProvider`), but the Match tab stays stale. The same
   root cause also means a just-played and deleted upcoming match lingers on the landing.

2. **"Start match" is blocked without a real camera** — `_SetupScreen` disables the
   "Start match" button whenever `!connected` (`activeCameraIdProvider == null` or
   connection state is not `connected`). `_startMatch()` also returns early when
   `deviceId == null`. In dev mode no camera is auto-connected, so the Setup → Session
   transition is permanently blocked for demo purposes.

3. **Team rosters are empty** — `MockDataSeeder.seed()` inserts teams, matches, and
   streaming destinations, but not players. The `players` table stays empty; the Roster
   sub-tab shows "No players yet" for all mock teams.

---

## Requirements

### R1 — `upcomingMatchesProvider` reacts to match mutations

`upcomingMatchesProvider` must re-emit whenever any `TeamMatch` row is inserted or deleted
for the active user's teams, not only when team rows change.

- **Fix**: Replace the `async*` generator (which only loops on `dao.watchForUser(userId)`)
  with a single Drift JOIN query that watches both `teamsTable` and `teamMatchesTable`.
  Add `TeamsDao.watchUpcomingMatchesForUser(String userId)` — a SELECT on
  `teamMatchesTable` joined to `teamsTable` WHERE `kind = 'upcoming'` AND
  `teams.hidden = 0` AND `teams.userId = userId`, using `.watch()`. Drift's reactive
  queries watch every table involved in the join, so any insert or delete to either table
  triggers a new emission.
- Rewrite `upcomingMatchesProvider` as a `StreamProvider` that maps this single DAO
  stream to `List<UpcomingMatch>`, removing the nested `await for` + one-shot fetch
  pattern.

### R2 — Match setup screen is fully navigable in dev mode without a camera

When `kAppEnv.isDevBackend` is `true`:

- The "Start match" button on the setup screen is enabled regardless of camera
  connection state.
- `_startMatch()` uses a fallback device ID (`'SST-CAM-001'` — the first mock device)
  when `activeCameraIdProvider` is null, then calls `MockBleService.pushSessionConfig`
  normally. The mock service accepts any device ID and succeeds, transitioning the user
  to the session screen.
- The "Connect a camera to start the match" helper text is hidden in dev mode (it
  misleads the user when the button is intentionally enabled).
- The live session itself (`_SessionScreen`) is unchanged — it already works without
  requiring further camera commands.

In stage/prod (`!kAppEnv.isDevBackend`), the existing behaviour is preserved: button
disabled when `!connected`, early return if `deviceId == null`.

### R3 — Mock teams have realistic player rosters

`assets/mock/fixtures/players.json` is added with players for both mock teams:
`mock-team-nr-u14` (Northridge U14) and `mock-team-efc-u14` (Eastfield FC). Each team
gets 10–13 players with realistic jersey numbers, names, positions, and one captain.

`MockDataSeeder.seed()` is extended to load and insert players from `players.json` using
the same `_loadFixture` / `insertOnConflictUpdate` pattern as teams and matches.

---

## Acceptance Examples

- **AE1 (R1).** Given no camera is connected and both mock teams exist, when the user
  opens the Match tab (which shows the seeded upcoming match), fills the form to add a
  second upcoming match, and taps "Add" — the new match appears in the Match landing
  within one render cycle without the user navigating away.

- **AE2 (R1).** Given the user plays through an upcoming match to completion and taps
  the back arrow on the ended session, when they return to the Match landing — the
  just-played match is absent (it was deleted by `removeMatch`).

- **AE3 (R2).** Given `APP_ENV=dev` and `kUseMockData=true` with no BLE device
  connected, when the user selects an upcoming match from the landing and taps
  "Start match" on the setup screen — the session screen opens without error.

- **AE4 (R3).** Given `kUseMockData=true`, when the user opens the Teams tab, taps
  Northridge U14, and selects the Roster sub-tab — a player list with realistic names and
  jersey numbers is shown (not the "No players yet" empty state).

---

## Success Criteria

- A developer running `flutter run --dart-define=kUseMockData=true` can complete the
  full match workflow — schedule a match, proceed through setup, run the session, and
  end the match — without connecting or even having a physical camera.
- The Match tab landing updates within a single frame after adding or removing an
  upcoming match.
- Both mock teams show populated Roster sub-tabs.
- `flutter analyze` and `flutter test` pass without new failures.

---

## Scope Boundaries

**In scope:**
- `lib/state/app_data.dart` — rewrite `upcomingMatchesProvider`
- `lib/db/daos/teams_dao.dart` — add `watchUpcomingMatchesForUser`
- `lib/pages/match_page.dart` — dev-mode bypass in `_SetupScreen`
- `assets/mock/fixtures/players.json` — new fixture file
- `lib/db/mock_data_seeder.dart` — extend `seed()` to include players

**Out of scope:**
- Changing the session screen (`_SessionScreen`) — it already works correctly
- Production builds — R2 is gated on `kAppEnv.isDevBackend`; no prod behaviour changes
- Adding more mock sports/teams beyond the two existing ones
- Seeding video/clip data into `teamMatchesTable.sizeMb` for newly added matches

---

## Key Decisions

- **R1 — Single JOIN stream vs. dual stream merge.** A JOIN query is cleaner and
  requires no fan-out logic in the provider. Drift's `.watch()` on a join automatically
  re-emits when any of the joined tables change. The current `async*` + `await for` +
  one-shot `getTeamMatchesForTeams` pattern has a fundamental reactivity gap; replacing
  it with a single stream is a net simplification.

- **R2 — Dev-mode bypass, not removing the connection requirement.** The session screen
  still relies on the real camera for recording/streaming. Only the setup-to-session
  transition is bypassed in dev mode. Stage/prod behaviour is unchanged. Using
  `kAppEnv.isDevBackend` (not `kUseMockData`) is the correct gate since it controls
  whether the BLE backend is the mock — and therefore whether BLE calls without a real
  device are safe.

- **R2 — Fallback device ID `'SST-CAM-001'` (not null skip).** Skipping `pushSessionConfig`
  entirely in dev mode would lose the coverage that the session config is wired up at all.
  Using the first mock device ID is the safer choice: it exercises the full call path
  through `MockBleService.pushSessionConfig`, which already handles any device ID without
  throwing.

- **R3 — `players.json` separate fixture file.** Following the established pattern from
  `teams.json`, `matches.json`, and `streaming_destinations.json`. Keeps the seeder
  modular and the fixture file easy to read/extend independently.

---

## Dependencies / Assumptions

- `TeamsDao` is a `DatabaseAccessor` with access to both `teamsTable` and
  `teamMatchesTable`; adding a join query there requires no structural changes.
- `MockBleService.pushSessionConfig('SST-CAM-001', config)` succeeds in all cases where
  `failNextPushSessionConfig` is false (verified from source).
- The `_kDefaultUserId = 'default-user'` constant is stable; all fixture player rows
  use team IDs already present in the seeded DB.
- The `players` table schema (columns: `teamId`, `number`, `name`, `position`, `captain`)
  is already defined in `lib/db/tables/teams_table.dart` — no migration needed.

---

## Outstanding Questions

### Resolve Before Planning

- None — all product decisions are captured above.

### Deferred to Planning

- [R1][Technical] Confirm whether `watchUpcomingMatchesForUser` should order results by
  `date ASC` or preserve insertion order. The current provider yields matches in the
  order the teams stream emits them; a JOIN query can specify an `orderBy`.
- [R3][Content] Decide on the exact number of players per team and realistic position
  distribution (e.g., 1 keeper, 4 defenders, 4 mids, 2 forwards for soccer).
