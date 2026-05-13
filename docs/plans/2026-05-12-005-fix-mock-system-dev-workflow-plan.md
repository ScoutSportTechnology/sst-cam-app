---
title: "fix: Mock system dev workflow — seven targeted defect fixes"
type: fix
status: active
date: 2026-05-12
origin: docs/brainstorms/2026-05-12-mock-system-bug-fixes-requirements.md
---

# fix: Mock system dev workflow — seven targeted defect fixes

## Summary

Seven self-contained fixes restore the full mock-mode developer workflow: short-circuit VLC in `LivePreviewView` so the mock video plays immediately, remove stale camera-connection gates from `TeamsPage` / `MatchPage` / `SettingsPage` while keeping the gate at the live-session entry point, wire `recordings.json` into `MockBleService`, update fixture JSON for a second team and consistent opponent prefixes, and filter phase-transition events from the session event log.

---

## Problem Frame

The mock-system feature branch left several regressions: VLC intercepts the mock video path whenever the WiFi group auto-connects; three pages gate DB-backed content behind a camera connection that is never present on a fresh dev launch; `MockBleService` serves generic hardcoded recordings instead of the fixture data; and the event log mixes phase transitions with user-logged highlights. See `docs/brainstorms/2026-05-12-mock-system-bug-fixes-requirements.md` for the full narrative.

---

## Requirements

- R1. In dev-backend mode, `LivePreviewView` shows the mock video asset without a VLC loading phase.
- R2. `TeamsPage` renders team list and all team CRUD without a camera connection.
- R3. `MatchPage` landing and setup screens render without a camera connection; the Start button is disabled when no camera is connected.
- R4. `SettingsPage` shows User, Sport setups, Streaming, and App sections without a camera connection; `_CameraCard` is the only element that requires connection.
- R5. The debug reset already correctly wipes and re-seeds with `'Coach'` — no code change required.
- R6. `assets/mock/fixtures/teams.json` includes Eastfield FC so the match-form opponent dropdown works.
- R7. All `opponent` values in `assets/mock/fixtures/matches.json` carry the `"vs "` prefix.
- R8. `MockBleService.listRecordings()` returns data from `assets/mock/fixtures/recordings.json` rather than hardcoded generic stubs.
- R9. The `_SessionScreen` event log shows only highlight events (`kind != 'phase'`); `_EventLogRow` dead code removed.

**Origin acceptance examples:** AE1 (R1), AE2 (R2), AE3 (R3), AE4 (R3), AE6 (R6), AE7 (R7), AE8 (R9)

---

## Scope Boundaries

- `schemaVersion` stays at 2 — no schema bump; R5 is handled by the existing debug-screen reset (already correct).
- `_EventLogRow`'s `isPhase` logic is removed entirely; the widget is simplified, not refactored into a separate file.
- `DiscoveryPage` connection logic is left unchanged — it legitimately requires BLE.
- Video pages (`VideoPage`, `VideoTeamMatchesPage`, `VideoMatchDetailPage`) confirmed gate-free — no change needed.
- `recordings.json` content (IDs, durations, sizes) is used as-is; the fixture schema is already documented in the file header.

### Deferred to Follow-Up Work

- Production build flavor excluding `assets/mock/` from release APK/IPA — separate Gradle/Xcode config.
- `recordings.json` → `MockDataSeeder` DB path (recording progress/download-state in `teamMatchesTable`) — separate feature.

---

## Context & Research

### Relevant Code and Patterns

- `lib/widgets/live_preview_view.dart` — `_initMockPlayer` in `initState` already guarded by `kAppEnv.isDevBackend`; the VLC URL block at the top of `build` is not; wrap with same guard.
- `lib/pages/teams_page.dart` lines 21–35 — `connected` variable + `if (!connected)` block; `_ConnectCameraEmptyState` at lines 132–192 becomes dead code.
- `lib/pages/match_page.dart` lines 95–100 — `if (!connected) return _ConnectCameraScreen()`; `_ConnectCameraScreen` at lines 132–195 becomes dead code; `_SetupScreen` Start button at lines 719–730 calls `_startMatch`.
- `lib/pages/settings_page.dart` lines 56–120 — the `if (connected) ... else _ConnectCameraBanner` block; `_DataSection` already always visible below it; only `_CameraCard` needs the connection guard.
- `lib/ble/mock_ble_service.dart` — `_fakeRecordings` static list (lines 238–263); `listRecordings` at line 443 returns it; `sendCommand` at line 417 also references `_fakeRecordings` for `ListRecordingsCommand`.
- `lib/db/mock_data_seeder.dart` — `_loadFixture(name)` async helper strips `//` comment lines and parses JSON from `assets/mock/fixtures/$name.json`; reuse this pattern for BLE-side fixture loading.
- `lib/pages/match_page.dart` `_SessionScreen.build` lines 1253–1263 — `state.events` list; `_EventLogRow` at lines 1950–1999 has `isPhase` branch.
- `lib/env.dart` — `kAppEnv.isDevBackend` extension getter; `kUseMockData` compile-time const.

### Institutional Learnings

- **Never close + delete + reopen the DB** (`docs/solutions/architecture-patterns/riverpod-drift-db-reset-in-place-2026-05-11.md`) — the debug screen reset already follows the correct in-place wipe pattern; confirmed no change needed there.
- **FK pragma must be ON** — `PRAGMA foreign_keys = ON` fires in `beforeOpen`; already wired; no regression risk here since no schema changes.
- **`kAppEnv.isDevBackend` is the correct gate** for dev-mode mock behaviour; use the extension getter, not a raw enum comparison.
- `MockDataSeeder._loadFixture()` — the `//`-comment-stripping + `jsonDecode` pattern is the established way to read fixture assets; mirror it exactly in `MockBleService`.

---

## Key Technical Decisions

- **VLC block wrapped, not restructured**: `_swapVlcController` call site is wrapped with `if (!kAppEnv.isDevBackend)` because the surrounding `build` method already has the mock-video `else if` branch in the right position — moving code would risk regressions in the real-device path.
- **`_SetupScreen` derives `connected` itself**: adding a `connected` parameter to `_SetupScreen` would require threading it through `MatchPage.build` and wiring it in every call site. The widget is already a `ConsumerStatefulWidget` and can watch the same providers directly.
- **Settings page restructured, not split**: `_ConnectCameraBanner` stays as the camera-info placeholder; the remaining sections are hoisted above the `else` branch so they render unconditionally without changing the visual hierarchy.
- **`MockBleService` loads fixtures at construction**: the fixture JSON is small (< 1 KB) and the service is created once at provider init; eager loading avoids async complexity in `listRecordings`. The data is stored as an instance field replacing `_fakeRecordings`.
- **`_EventLogRow.isPhase` branch fully removed**: once `_SessionScreen` filters phase events, no `LiveEvent` with `kind == 'phase'` ever reaches `_EventLogRow`. Keeping the branch would be misleading dead code.
- **`sendCommand` also updated**: `ListRecordingsCommand` in `MockBleService.sendCommand` returns `_fakeRecordings`; this must be updated to the new instance field to stay consistent with `listRecordings`.

---

## Open Questions

### Resolved During Planning

- *R5 — needs DB migration?* No. `debug_page.dart` reset already wipes and re-seeds with `'Coach'`. Developers reset once via the debug screen; no migration code required.
- *Which pages have stale connection gates?* `TeamsPage`, `MatchPage`, `SettingsPage`. Video pages confirmed gate-free.
- *Where does `recordings.json` wire to?* `MockBleService._fakeRecordings` — BLE-side, not the Drift DB.
- *Is the debug reset already correct?* Yes — confirmed in-place wipe pattern, FK-ordered deletes, `seedBaseData()` + `MockDataSeeder`.

### Deferred to Implementation

- Exact failure UX when `recordings.json` fails to parse in `MockBleService` — log and fall back to the existing hardcoded list, or throw. Pick during implementation based on how other fixture load failures are handled in `MockDataSeeder`.

---

## Implementation Units

### U1. LivePreviewView — skip VLC in dev-backend mode

**Goal:** Prevent VLC controller creation when `kAppEnv.isDevBackend` is true so the mock video asset is the only rendered content.

**Requirements:** R1

**Dependencies:** None

**Files:**
- Modify: `lib/widgets/live_preview_view.dart`
- Test: `test/widgets/live_preview_view_test.dart` (new)

**Approach:**
- Wrap the VLC URL block in `build` (the `if (url != null && url != _vlcUrl) { _swapVlcController(url); } else if ...` block) with `if (!kAppEnv.isDevBackend)`. When true, the block is skipped entirely; `_vlc` stays null; the `else if` mock-video branch renders.
- No change to `_initMockPlayer`, `_onVlcChange`, or the `dispose` cleanup — those paths remain correct.

**Patterns to follow:**
- `initState` in the same file — `if (kAppEnv.isDevBackend) _initMockPlayer()` is the exact pattern to mirror.

**Test scenarios:**
- Happy path (dev backend): widget built with a device ID; `previewDescriptorProvider` returns a non-null URL; `_vlc` is never created; mock video renders after init.
- Happy path (non-dev backend): widget built with a device ID; descriptor URL present; `_swapVlcController` is called; VLC renders (or falls back to placeholder on error).
- Edge case: `deviceId` is null — `ThumbPlaceholder` renders regardless of backend mode.
- Edge case: `kAppEnv.isDevBackend` true, `_mock` not yet initialized — `ThumbPlaceholder` shows until init completes, then mock video shows.

**Verification:**
- In dev mode with a mock device connected, navigating to the session screen shows the mock video without any VLC loading phase.
- `grep -n '_swapVlcController\|VlcPlayerController' lib/widgets/live_preview_view.dart` — the call site is inside the `!isDevBackend` guard.

---

### U2. TeamsPage — remove camera-connection gate

**Goal:** Remove the `if (!connected)` early-return and the `_ConnectCameraEmptyState` widget so teams render from the local DB without a camera connection.

**Requirements:** R2

**Dependencies:** None

**Files:**
- Modify: `lib/pages/teams_page.dart`
- Test: `test/pages/teams_page_test.dart` (new or extend)

**Approach:**
- Delete the `connected` / `activeId` variable declarations and the `if (!connected)` block.
- Delete the `_ConnectCameraEmptyState` widget class — it will have no remaining call sites.
- Remove `connectionStateProvider` and `CameraConnectionState` imports if no longer referenced.
- Leave `activeCameraIdProvider` import intact only if referenced elsewhere in the file (e.g., the refresh menu item or future use); otherwise remove it too.

**Patterns to follow:**
- `lib/pages/video_page.dart` — shows DB-backed content without a connection gate.

**Test scenarios:**
- Happy path: `TeamsPage` widget test with no `activeCameraIdProvider` set — team list renders with seeded teams.
- Happy path: FAB tap opens `TeamFormSheet` regardless of connection state.
- Edge case: empty DB — `_NoTeamsYet` widget shown (not a connection empty state).
- Regression: connecting a mock device and navigating to Teams — list still shows (no double-render issue).

**Verification:**
- App launched with `kUseMockData=true`, no mock device connected — Teams tab shows Northridge U14.
- `grep -n '_ConnectCameraEmptyState\|!connected' lib/pages/teams_page.dart` returns zero hits.

---

### U3. MatchPage — remove landing/setup gate; gate Start button on connection

**Goal:** Remove the `if (!connected) return _ConnectCameraScreen()` early-return from `MatchPage.build`. Disable the Start button in `_SetupScreen` when no camera is connected.

**Requirements:** R3

**Dependencies:** None

**Files:**
- Modify: `lib/pages/match_page.dart`
- Test: `test/pages/match_page_test.dart` (new or extend)

**Approach:**
- In `MatchPage.build`: delete the `connected` derivation and the `if (!connected) return _ConnectCameraScreen()` guard. The landing and setup screens now render unconditionally.
- Delete `_ConnectCameraScreen` — it has no remaining call sites.
- In `_SetupScreen.build` (it is a `ConsumerStatefulWidget`): watch `activeCameraIdProvider` and `connectionStateProvider(activeId)` to derive `connected`. Pass `connected` as the enablement guard to the Start button's `onPressed`. When `connected` is false, set `onPressed` to null (disabled) or show a brief inline note `'Connect a camera to start'`.
- Keep `activeId` in `MatchPage.build` only if it feeds `_SessionScreen` or another consumer; remove otherwise.

**Patterns to follow:**
- `lib/pages/settings_page.dart` `_ConnectCameraBanner` — minimal connection-check pattern for actionable UI.
- `lib/pages/match_page.dart` `_SessionScreen` — `activeCameraIdProvider` watch already used there; same approach for `_SetupScreen`.

**Test scenarios:**
- Happy path: `MatchPage` widget test with no connected device — landing screen with upcoming match list renders.
- Happy path: tapping an upcoming match navigates to setup screen; no connection required.
- Covers AE3: setup screen visible without connection.
- Covers AE4: Start button disabled when no camera connected; tapping does not start the session.
- Happy path: Start button enabled when mock device is connected; tapping proceeds to session.
- Regression: `_ConnectCameraScreen` is no longer reachable — confirm it is deleted.

**Verification:**
- App with `kUseMockData=true`, no mock device: Match tab shows upcoming match list; tapping shows setup; Start button is disabled.
- After connecting a mock device: Start button becomes active.
- `grep -n '_ConnectCameraScreen\|if (!connected)' lib/pages/match_page.dart` returns zero hits.

---

### U4. SettingsPage — show DB-backed sections without camera connection

**Goal:** Restructure the `if (connected) ... else _ConnectCameraBanner` block so only `_CameraCard` is gated; User, Sport setups, Streaming destinations, and App sections render regardless of connection.

**Requirements:** R4

**Dependencies:** None

**Files:**
- Modify: `lib/pages/settings_page.dart`
- Test: `test/pages/settings_page_test.dart` (new or extend)

**Approach:**
- Replace the current `if (connected) [ everything ] else [ _ConnectCameraBanner ]` pattern with:
  ```
  if (connected) _CameraCard else _ConnectCameraBanner
  _UserSection       (always)
  Sport setups nav   (always)
  _StreamingSection  (always)
  App section        (always)
  _DataSection       (always — was already always)
  ```
- `_ConnectCameraBanner` becomes a slim slot for the camera-hardware card only; its existing behaviour (one-tap reconnect, push DiscoveryPage) is unchanged.
- `_StreamingSection` already takes `deviceId` as a parameter for the streaming count watch. When not connected, `deviceId` is null — pass `activeId` which is nullable; `_StreamingSection` should handle a null `deviceId` gracefully (watch `streamingDestinationsControllerProvider` unconditionally; the `deviceId` is only used for camera-specific push, not for reading the destinations list).

**Patterns to follow:**
- `lib/pages/video_page.dart` — no connection gate; content always renders.
- `lib/pages/settings_page.dart` existing `_DataSection` — always-visible pattern within the same file.

**Test scenarios:**
- Covers AE2 (implicit): no camera connected — Settings shows User section, Sport setups nav, Streaming section, App section, Data section.
- Happy path: `_ConnectCameraBanner` shown in place of `_CameraCard` when not connected.
- Happy path: `_CameraCard` shown when connected; rest of sections still present.
- Edge case: `activeId` is null — `_StreamingSection` renders streaming destinations list from DB without error.
- Regression: `_DataSection` still visible in both connected and disconnected states.

**Verification:**
- App with `kUseMockData=true`, no mock device: Settings page shows user name `'Coach'`, sport setups link, streaming destinations, App section.
- `grep -n 'if (connected)' lib/pages/settings_page.dart` returns at most one hit (for `_CameraCard` only).

---

### U5. Fixture data — add Eastfield FC team and "vs " opponent prefixes

**Goal:** Add a second registered team to `teams.json` so the match form's opponent dropdown offers a real pick. Prefix all `opponent` values in `matches.json` with `"vs "` to match the format produced by the form.

**Requirements:** R6, R7

**Dependencies:** None

**Files:**
- Modify: `assets/mock/fixtures/teams.json`
- Modify: `assets/mock/fixtures/matches.json`
- Test: `test/db/mock_data_seeder_test.dart` (extend existing)

**Approach:**
- Add to `teams.json`:
  ```json
  {
    "id": "mock-team-efc-u14",
    "userId": "default-user",
    "name": "Eastfield FC",
    "shortName": "EFC",
    "sport": "Soccer",
    "hidden": false
  }
  ```
- Prefix every `opponent` value in `matches.json` with `"vs "` — e.g. `"Eastfield FC"` → `"vs Eastfield FC"`, `"Riverdale Utd"` → `"vs Riverdale Utd"`, etc.
- No other fixture changes needed; existing match IDs and event log data are correct.

**Patterns to follow:**
- Existing `teams.json` entry for `mock-team-nr-u14` — mirror field order exactly.

**Test scenarios:**
- Happy path (R6): after `MockDataSeeder.seed()`, `teamsDao.allTeams()` returns 2 teams; `mock-team-efc-u14` is present with `sport: 'Soccer'`.
- Happy path (R7): all four match rows in DB have `opponent` starting with `"vs "`.
- Integration (Covers AE6): `TeamMatchFormSheet` for Northridge U14 shows Eastfield FC in the opponent dropdown.
- Integration (Covers AE7): match tile in Teams detail page shows `"vs Eastfield FC"`.
- Edge case: `MockDataSeeder.seed()` called twice — idempotent; no duplicate team rows.

**Verification:**
- App with `kUseMockData=true`: Teams tab shows two teams; match form opponent dropdown offers Eastfield FC.
- Match history rows show `"vs Eastfield FC"` / `"vs Riverdale Utd"` etc.

---

### U6. MockBleService — wire recordings.json fixture

**Goal:** Replace the hardcoded `_fakeRecordings` static list in `MockBleService` with data loaded from `assets/mock/fixtures/recordings.json`, so `listRecordings()` returns fixture-consistent data.

**Requirements:** R8

**Dependencies:** U5 (fixture files are in place; recordings.json already present and consistent with teams)

**Files:**
- Modify: `lib/ble/mock_ble_service.dart`
- Test: `test/ble/mock_ble_service_test.dart` (extend existing)

**Approach:**
- Add an async factory or late-init pattern: load `recordings.json` via `rootBundle.loadString` (same `//`-comment-stripping + `jsonDecode` pattern as `MockDataSeeder._loadFixture`); parse into `List<RecordingMetadata>`.
- Store as an instance field `List<RecordingMetadata> _recordings` (not static), initialized lazily or in a `Future<void> _loadRecordings()` called from `startScan` or on first `listRecordings` call.
- Update `listRecordings()` to return `_recordings` (or the loaded list).
- Update the `ListRecordingsCommand` branch in `sendCommand` to use the same instance field.
- On parse failure, fall back to the existing hardcoded list and log a warning; do not crash the mock service.

**Patterns to follow:**
- `lib/db/mock_data_seeder.dart` `_loadFixture` — identical JSON-loading pattern; reuse verbatim.
- `lib/ble/mock_ble_service.dart` existing `_fakeRecordings` static field — the replacement target.

**Test scenarios:**
- Happy path: `MockBleService.listRecordings('any-id')` returns 2 entries with IDs `rec-mock-001` and `rec-mock-002`; `teams` fields are `'NR vs EFC'` and `'NR vs RU'`.
- Happy path: `sendCommand(ListRecordingsCommand())` returns the same 2 entries.
- Error path: simulate fixture load failure — falls back to non-empty list (hardcoded); no exception propagates.
- Integration: `recordingsProvider('SST-CAM-001')` emits the fixture recordings in the full app widget test.

**Verification:**
- With a mock device connected, the Recordings tab or equivalent shows `NR vs EFC` and `NR vs RU` entries rather than `Reds vs Blues` / `Eagles vs Lions`.

---

### U7. EventLog — filter phase events; clean up _EventLogRow

**Goal:** Filter `kind == 'phase'` events out of the `_SessionScreen` event list. Remove the now-unreachable `isPhase` conditional from `_EventLogRow`.

**Requirements:** R9

**Dependencies:** None

**Files:**
- Modify: `lib/pages/match_page.dart`
- Test: `test/pages/match_page_test.dart` (extend)

**Approach:**
- In `_SessionScreen.build`, before the `ListView.separated`, derive `final visibleEvents = state.events.where((e) => e.kind != 'phase').toList()`. Use `visibleEvents` for the `isEmpty` check, `itemCount`, and `itemBuilder` index.
- In `_EventLogRow.build`: remove the `isPhase` local variable, remove the `if (isPhase)` branches on font weight/color, remove the `'PHASE'` badge widget and the `'edit'` label (or simplify both to a single consistent style). The widget no longer needs to differentiate event kinds.
- Phase events stay in `LiveMatchState.events` — no change to `LiveMatchController` or score derivation.

**Patterns to follow:**
- Existing `state.events.isEmpty` guard directly above the `ListView` in `_SessionScreen` — extend with the filter in the same local variable block.

**Test scenarios:**
- Covers AE8: after `startPeriod()` (adds `'Kickoff'` phase event) and one `logEvent` call (adds a goal), `_SessionScreen` shows only the goal row.
- Happy path: empty `visibleEvents` after kickoff — "No events yet" placeholder shows (phase events invisible).
- Happy path: multiple goals and fouls logged — all visible; Kickoff, End period, End match events absent.
- Edge case: all events are phase events — list shows "No events yet" (visibleEvents is empty).
- Unit test: `_EventLogRow` built with a goal event — renders without "PHASE" badge or accent styling.

**Verification:**
- Live session: tap Kickoff, log a goal — only the goal appears in the event log.
- `grep -n 'isPhase\|PHASE' lib/pages/match_page.dart` returns zero hits.

---

## System-Wide Impact

- **Interaction graph:** `wifiHandoffProvider` continues auto-connecting WiFi on BLE connect — U1 guards against this in `LivePreviewView.build` without touching the handoff logic itself.
- **Error propagation:** U6 fixture load failure falls back silently; other units have no new async failure surfaces.
- **State lifecycle risks:** None — all units edit display/init logic; no provider lifecycle changes.
- **API surface parity:** `MockBleService.sendCommand(ListRecordingsCommand)` and `listRecordings()` must stay in sync — U6 updates both call sites.
- **Unchanged invariants:** `LiveMatchState.events` still stores all event kinds; `LiveMatchController` is untouched; score derivation is unaffected.

---

## Risks & Dependencies

| Risk | Mitigation |
|------|------------|
| `rootBundle.loadString` unavailable in unit tests for U6 | Use `flutter_test` with `TestWidgetsFlutterBinding.ensureInitialized()` and asset bundle registration, or mock the load; document in test file |
| `_SetupScreen` connection check creates flicker if connection drops mid-setup | Acceptable for dev-mode tooling; the button simply disables; no data loss |
| `_StreamingSection` with null `deviceId` — provider watch may throw if `deviceId` is required | Verify `_StreamingSection` handles null gracefully; adjust the widget signature to accept `String?` if needed |
| Removing `isPhase` styling before confirming no external test reads the "PHASE" label | Run `grep -rn '"PHASE"\|PHASE' test/` before deleting; update any snapshot tests |

---

## Sources & References

- **Origin document:** [docs/brainstorms/2026-05-12-mock-system-bug-fixes-requirements.md](docs/brainstorms/2026-05-12-mock-system-bug-fixes-requirements.md)
- Institutional learning — DB reset: `docs/solutions/architecture-patterns/riverpod-drift-db-reset-in-place-2026-05-11.md`
- Institutional learning — Drift patterns: `docs/solutions/architecture-patterns/app-source-of-truth-drift-sqlite-2026-05-06.md`
- Related plan: `docs/plans/2026-05-11-004-feat-mock-system-and-dev-tooling-plan.md`
- Key files: `lib/widgets/live_preview_view.dart`, `lib/pages/teams_page.dart`, `lib/pages/match_page.dart`, `lib/pages/settings_page.dart`, `lib/ble/mock_ble_service.dart`, `lib/db/mock_data_seeder.dart`
