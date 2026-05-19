---
date: 2026-05-12
topic: mock-system-bug-fixes
---

# Mock System Bug Fixes

## Summary

Five defects in the current mock-system implementation prevent the full dev workflow from running cleanly: a VLC interference bug that blocks the mock video preview, stale camera-connection gates on two pages that are now fully DB-backed, a stale default-user name in existing SQLite files, a single-team fixture gap that forces "Other" in the match form, and phase-transition noise in the event log.

---

## Problem Frame

The mock system (implemented in the `feat/mock-system-dev-tooling` branch) introduced a two-flag architecture (`AppEnv` + `kUseMockData`), JSON fixture assets, and Drift-backed providers for teams and matches. Several regressions were introduced or left unfixed during that work:

- `LivePreviewView` was not updated to short-circuit VLC when running in dev-backend mode. Because `wifiHandoffProvider` auto-connects the mock WiFi group on BLE connect, a fake RTSP descriptor URL reaches the widget and causes VLC to show its loading placeholder for several seconds before erroring out and yielding to the mock video player.
- `TeamsPage` and the `MatchPage` landing/setup screens still carry a blanket camera-connection gate written when teams and matches lived on the firmware. Both are now fully DB-backed; the gate is stale and blocks the Teams and Match tabs in mock mode unless the developer manually connects a mock device first.
- The `_seedBaseData()` function seeds the user with `name: 'Coach'`, but existing SQLite files created before the rename still carry `name: 'default'`. No migration path updates them.
- The `teams.json` fixture has only one team. The match form filters opponents to registered teams of the same sport, so it always shows "No other Soccer teams on camera" and forces the developer to pick "Other (custom name)". The mock experience also has an inconsistency: the form prepends `"vs "` to opponent names, but the fixture entries do not carry that prefix.
- `LiveMatchController` adds `kind: 'phase'` events (Kickoff, End period N, End match) alongside user-logged highlights. Both kinds appear in the on-screen event log. The intended UX is that the event log shows only highlights — goals, fouls, cards — that serve as clip starting points. Phase events have no business being visible there.

---

## Requirements

**Live preview**

- R1. When `kAppEnv.isDevBackend` is `true`, `LivePreviewView` must not create or activate a VLC controller regardless of whether a `PreviewStreamDescriptor` URL is present. The looping mock video asset is the only rendered content in dev-backend mode.

**Connection gates**

- R2. `TeamsPage` renders its team list and all team-level CRUD actions (add, edit roster, view match history, delete) regardless of BLE connection state. The existing `if (!connected)` guard and `_ConnectCameraEmptyState` are removed from `TeamsPage`.
- R3. `MatchPage` renders the upcoming-matches landing screen and the setup screen regardless of BLE connection state. The `if (!connected) return _ConnectCameraScreen()` guard in `MatchPage.build()` is removed.
- R4. Entering the live session (`_SessionScreen`) still requires a connected camera. If no camera is connected when the user attempts to start a session from the setup screen, the "Start match" button is disabled or an inline prompt directs the user to connect first.

**Default user name**

- R5. A DB migration updates `name` from `'default'` to `'Coach'` for the row where `id = 'default-user'` and `name = 'default'`. Fresh installs are unaffected (already seeded with `'Coach'`).

**Fixture data**

- R6. `assets/mock/fixtures/teams.json` includes a second registered team — `id: 'mock-team-efc-u14'`, `name: 'Eastfield FC'`, `shortName: 'EFC'`, `sport: 'Soccer'`, `userId: 'default-user'` — so the match form's opponent dropdown shows a selectable team in mock mode.
- R7. All `opponent` values in `assets/mock/fixtures/matches.json` carry the `"vs "` prefix (e.g., `"vs Eastfield FC"`) to match the string format produced by the form when a match is added manually.

**Event log**

- R8. The event log `ListView` in `_SessionScreen` renders only events where `kind != 'phase'`. Phase events (`kind == 'phase'`) remain in `LiveMatchState.events` for internal use — score derivation, phase tracking, clip offsets — but are not displayed to the user.

---

## Acceptance Examples

- AE1. **Covers R1.** Given the app is running in dev-backend mode and a mock BLE device is connected (triggering `wifiHandoffProvider`), when the user enters the live session screen, `LivePreviewView` shows the mock video asset — not VLC's loading ThumbPlaceholder.

- AE2. **Covers R2.** Given `kUseMockData=true` and no mock BLE device has been connected, when the user navigates to the Teams tab, the seeded team list shows with the FAB available.

- AE3. **Covers R3.** Given `kUseMockData=true` and no mock BLE device has been connected, when the user navigates to the Match tab, the upcoming-matches landing screen shows the seeded upcoming match.

- AE4. **Covers R4.** Given no camera is connected, when the user reaches the setup screen for an upcoming match and taps "Start match", the session does not begin. The app shows a connect-camera prompt or disables the start action.

- AE5. **Covers R5.** Given an existing install where the `default-user` row has `name = 'default'`, when the app opens and the DB migration runs, the Settings screen shows `'Coach'` as the user name.

- AE6. **Covers R6.** Given `kUseMockData=true`, when the user opens the match form sheet for Northridge U14, the opponent picker dropdown shows "Eastfield FC" as a selectable option.

- AE7. **Covers R7.** Given `kUseMockData=true`, when past match entries are displayed in the Teams detail Matches tab or the library, the opponent string reads `"vs Eastfield FC"` not `"Eastfield FC"`.

- AE8. **Covers R8.** Given a live session where the user has tapped "Kickoff" and logged one goal, when the event log is displayed, only the goal entry is visible — the "Kickoff" phase event is absent from the list.

---

## Success Criteria

- A developer running `flutter run --dart-define=kUseMockData=true` can navigate to the Teams tab and Match tab immediately on launch without connecting a mock device first, and sees seeded data in both.
- The live session's preview area shows the mock video looping without any VLC loading period when in dev-backend mode.
- Settings shows `'Coach'` as the user name on any existing or fresh installation.
- The match form's opponent dropdown shows "Eastfield FC" as a selectable option (no longer always forced to "Other").
- The live session event log shows only goals, fouls, cards, and other user-marked highlights — period-start and period-end events are absent from the list.

---

## Scope Boundaries

- Changing how phase events are stored internally — they stay in `LiveMatchState.events`, only the display is filtered.
- Removing the connection requirement from the live session screen itself — connecting a camera is still required to start a session.
- Adding more than one additional team to the fixture set.
- Auditing other pages beyond `TeamsPage` and `MatchPage` for stale connection gates (that is follow-up work).
- Changing the teams-on-camera vs teams-in-DB data ownership model.

---

## Key Decisions

- **R1 — VLC skipped in dev-backend mode.** The fake RTSP URL is a mock artifact; its only effect in dev is blocking the mock video with VLC's loading screen. The mock video is the correct dev preview surface; VLC is irrelevant.
- **R4 — Session still requires connection.** The session screen drives camera hardware (recording start/stop, BLE commands). Landing and setup are read-only DB flows and do not interact with the firmware. Preserving the connection gate only at session entry keeps the dev workflow smooth while preventing undefined behavior when trying to send BLE commands to a disconnected device.
- **R8 — Filter at display, not storage.** Phase events drive score derivation and phase state internally. Removing them from state would require separate tracking for phase transitions. Filtering at render is the simpler, safer change.

---

## Dependencies / Assumptions

- The `'default-user'` ID is stable across all existing installs (seeded by `_seedBaseData()` which uses the constant `_kDefaultUserId = 'default-user'`).
- Adding `mock-team-efc-u14` to `teams.json` does not conflict with any existing fixture IDs (verified: current fixtures only have `mock-team-nr-u14`).

---

## Outstanding Questions

### Resolve Before Planning

- None — all product decisions are captured above.

### Deferred to Planning

- [Affects R5][Technical] The user-name migration is a data update, not a schema change. Determine whether to carry it as a v2→v3 schema bump (with `onUpgrade from < 3: UPDATE users ...`) or as a standalone `beforeOpen` statement that runs only when the target row exists. Either is safe; the choice affects whether `schemaVersion` advances.
- [Affects R4][Technical] Confirm the exact gesture point for the connection check on the setup screen — the "Start match" button in `_SetupScreen`. Verify whether the button has a single `onPressed` callback or uses the `_kickoff` flow, and wire the connection guard at that call site.
