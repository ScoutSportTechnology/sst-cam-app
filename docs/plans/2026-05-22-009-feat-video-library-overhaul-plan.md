---
title: "feat: Video Library Overhaul"
type: feat
status: active
date: 2026-05-22
origin: docs/brainstorms/2026-05-22-video-library-overhaul-requirements.md
---

# feat: Video Library Overhaul

## Summary

Ten ordered units replace the team-grouped video page with a flat, searchable match list; fix four active bugs; wire up a fully emulated camera-app video contract (UUID-based recordings, OverlayState model, WifiService extensions in both MockWifiService and WifiServiceImpl); and deliver end-to-end download, phone-side highlight clipping, and live-stream playback — all exercisable in dev mode using the mock video asset.

---

## Problem Frame

The current video landing page groups matches by team, producing phantom team entries and hiding cross-team matches from search. Bugs compound the problem: short names appear where full names should, match titles repeat "vs", and the overlay toggle controls all layers at once. Mock data leaves EFC without any match records. The WiFi service contract for video retrieval (recording UUID, download, overlay model) is undefined, blocking both user-facing features and firmware team design. (See origin: `docs/brainstorms/2026-05-22-video-library-overhaul-requirements.md`)

---

## Requirements

- R1. Team badge uses short name; title uses full name
- R2. Match title: "FullTeamName vs OpponentName" (no double "vs")
- R3. Score and Events overlay toggles are independently controllable
- R4. Both NR and EFC have 2–4 past match records with event logs
- R5. Mock data covers both on-device and on-camera-only states per team
- R6. Video landing page is a flat, time-ordered match list
- R7. Sport and Team filter chips; Team set drawn from tracked team records only
- R8. Search matches primary team name/shortName OR opponent string
- R9. NR vs EFC and EFC vs NR are distinct rows in the unfiltered list
- R10. On-device check: file exists at UUID-derived device storage path
- R11. Not on device → app auto-initiates WiFi and streams from camera
- R12. Mock video asset used for all playback instances in dev mode
- R13. Simplified overlay (score + events) always rendered on the video surface
- R14. Full-game download with live progress; cancellable
- R15. Download completion saves file to recording path; on-device check then passes
- R16. Highlight clip requires full match on device; prompts download if missing
- R17. Clip = FFmpeg trim ±15 s around selected event timestamp
- R18. Any event in the event list can trigger clip creation; multiple clips per match supported
- R19. Camera recordings identified by match UUID only
- R20. WifiService extended with `checkCameraHasRecording`, `downloadRecording`, `downloadRecordingWithOverlays`
- R21. `OverlayState` is a named contract type shared across all overlay surfaces
- R22. Live stream: `WifiService` provides `overlayStateStream` at ~1 Hz
- R23. Recorded playback: `List<OverlayState>` derived from DB events; scrubber-synced
- R24. Download-with-overlays contract defined and mocked

**Origin actors:** A1 (App User), A2 (Flutter App), A3 (SST Cam — mocked)
**Origin flows:** F1 (browse/filter), F2 (play on device), F3 (play from camera), F4 (download), F5 (create clip)
**Origin acceptance examples:** AE1 (R1), AE2 (R2), AE3 (R3), AE4 (R8, R9), AE5 (R10, R11), AE6 (R10, R15), AE7 (R16), AE8 (R17)

---

## Scope Boundaries

- All `WifiService` calls go through `MockWifiService` (dev mode) or `WifiServiceImpl` (non-dev). Both are fully implemented with emulated behavior; neither throws `UnimplementedError`. Swapping to real hardware requires only replacing emulated behavior inside `WifiServiceImpl` method bodies.
- Camera-side overlay rendering (burning OverlayState onto video on-device at the camera) is not implemented; the contract is defined and mocked only.
- Half-game (1st / 2nd half) download is not in scope; only full-game download.
- `VideoTeamMatchesPage` is deleted; no backward navigation to it is retained.
- Social sharing, cloud sync, export to external apps not included.
- iOS builds not in scope (Linux devcontainer only).
- No Drift schema changes → no migration needed.
- Player-level filtering, playlists, or tagging are deferred.

---

## Context & Research

### Relevant Code and Patterns

- `lib/core/wifi/wifi_service.dart` — abstract interface to extend (4 new methods)
- `lib/core/wifi/wifi_service_impl.dart` — currently all stubs; every method needs a full emulated implementation
- `lib/mock/mock_wifi_service.dart` — full working implementation; pattern to mirror in WifiServiceImpl
- `lib/core/ble/ble_providers.dart` — provider selection pattern (`kAppEnv.isDevBackend ? Mock() : Impl()`) to mirror for WiFi
- `lib/mock/mock_data_seeder.dart` — fixture loading + `insertAllOnConflictUpdate` pattern; `Future.wait` parallel load
- `assets/ble/fixtures/matches.json` — all 4 matches belong to NR; all `sizeMb > 0`; opponent strings have `"vs "` prefix
- `assets/ble/fixtures/teams.json` — NR and EFC records
- `lib/features/video/video_state.dart` — `LibraryMatch`, `libraryProvider`, `filteredLibraryTeamsProvider`; `downloadState` derived from `sizeMb > 0`
- `lib/features/video/video_page.dart` — team-grouped list; both avatar and title use `team.shortName`
- `lib/features/video/video_team_matches_page.dart` — DELETE this file
- `lib/features/video/playback/video_match_detail_page.dart` — single `_overlaysOn` bool; hardcoded overlay values; clip creation uses scrubber position
- `lib/features/video/playback/download_sheet.dart` — existing progress UI; calls `bleService.requestDownload` then `wifi.startDownload`
- `lib/core/services/clip_service.dart` — `trim(matchId, sourcePath, startSeconds, durationSeconds)` with FFmpeg `-c copy`; throws `ClipTrimException` on missing file
- `lib/core/services/video_path_service.dart` — `recordingPath(id)` and `clipPath(id, clipId)` under `getApplicationSupportDirectory()/videos/`
- `lib/core/state/db_providers.dart` — `videoPathServiceProvider`, `clipServiceProvider` wiring pattern

### Institutional Learnings

- **App-source-of-truth (Drift)**: use `dao.watchX().listen()` + `ref.onDispose` not `FutureProvider` with manual refresh; add `onError:` to every stream listener; avoid N+1 queries
- **isDevBackend must not bypass connection guards**: never write `kAppEnv.isDevBackend || connected`; compute state from real provider; pass null callbacks to buttons when disconnected
- **BackupService silent column omission**: no new DB tables in this sprint → BackupService unchanged; note this explicitly if schema ever changes
- **activeTabProvider one-way binding bug**: use `AppTab.video` constant at call sites; verify `app_shell.dart` has bidirectional sync before wiring any "Go to Library" cross-tab navigation

### External References

None needed — all patterns are well-established in the codebase.

---

## Key Technical Decisions

- **`downloadState` replaced by `isOnDeviceProvider`**: The current `sizeMb > 0` heuristic is inaccurate. On-device state is computed from `File.existsSync()` at the UUID-derived path. Because this is async (`getApplicationSupportDirectory()` is async), it lives in a `FutureProvider.family<bool, String>(matchId)`. The provider is invalidated explicitly when a download completes so the UI updates without a reload.

- **MockDataSeeder writes a 1-byte placeholder for on-device matches**: Copying 99 MB per seeded match is impractical. The `isOnDevice` check only needs file existence. The video player in dev mode always uses `VideoPlayerController.asset('assets/ble/mock-video.mp4')` regardless of the recording path file content.

- **No `UnimplementedError` anywhere in the app**: Every `*Impl` class (`WifiServiceImpl`, `BleServiceImpl`) must have complete, working method bodies. `MockWifiService` is the emulated implementation selected by `kAppEnv.isDevBackend` and injected in tests. `WifiServiceImpl` and `BleServiceImpl` carry identical emulated behavior for now — "wiring to real hardware" means replacing method bodies, not adding missing implementations. A grep for `UnimplementedError` in `lib/` must return zero results after U4.

- **`OverlayState` derived from DB events for recorded playback**: The `overlayStateStream` (R22) is a live-match concern (Match/Live tab). For recorded video review (F2/F3), overlay is always derived from `LibraryMatch.events` — scores accumulated per goal event, period from `timeSeconds / periodLengthSeconds`. No WiFi round-trip needed for recorded overlay.

- **Opponent field stored without "vs " prefix**: Fixtures are corrected to store `"Eastfield FC"`, not `"vs Eastfield FC"`. The UI assembles the title as `"${teamName} vs ${match.opponent}"`. Simpler than stripping the prefix at the model layer.

- **`VideoTeamMatchesPage` deleted, not preserved**: The flat `VideoPage` makes it redundant. No routes remain that reference it.

- **Video player stack**: `video_player` for all mock playback (local asset + placeholder file). `flutter_vlc_player` is reserved for real RTSP streams (`WifiServiceImpl` live preview); the video detail page in dev mode doesn't use it.

---

## Open Questions

### Resolved During Planning

- **MockWifiService.downloadRecording file I/O**: writes a 1-byte placeholder at `recordingPath(uuid)` on completion; video player uses asset path in dev mode — see Key Technical Decisions
- **ffmpeg_kit_flutter availability**: confirmed in `pubspec.yaml` as `ffmpeg_kit_flutter_new_full ^2.0.0`; `ClipService.trim()` already uses it; no changes to the command shape needed
- **OverlayState file location**: `lib/core/models/overlay.dart` — confirmed no naming collision

### Deferred to Implementation

- **`isOnDeviceProvider` invalidation timing**: resolved — see U9 Approach for the exact call site (`onDone` callback in `_DownloadSheetState` progress listener, after confirming `DownloadStatus.completed`)
- **`VideoPlayerController` lifecycle in `ConsumerStatefulWidget`**: dispose timing and rebuilding controller when source changes (local → stream or vice versa) — standard `video_player` lifecycle, address during U7 implementation
- **OverlayState score accumulation edge cases**: event kinds that don't affect score (foul, card, sub, save) just emit a new OverlayState with unchanged scores and the event label; no complex logic needed but verify against fixture event data

---

## High-Level Technical Design

> *This illustrates the intended approach and is directional guidance for review, not implementation specification. The implementing agent should treat it as context, not code to reproduce.*

```
OverlayState { timeSeconds, homeScore, awayScore, period, recentEventLabel? }
OverlayConfig { showScore, showEvents }

WifiService (abstract)
  + checkCameraHasRecording(uuid) → Future<bool>
  + downloadRecording(deviceId, uuid) → Future<VideoDownloadHandle>
  + downloadRecordingWithOverlays(deviceId, uuid, overlays, config) → Future<VideoDownloadHandle>
  + overlayStateStream(deviceId) → Stream<OverlayState>

MockWifiService implements WifiService          ← dev mode / test injection
WifiServiceImpl implements WifiService          ← non-dev mode (fully emulated until hardware)

Fixture fix:
  matches.json  →  opponent: "Eastfield FC"   (no "vs " prefix)
                   NR: 4 matches (2 sizeMb>0, 2 sizeMb=0)
                   EFC: 3 matches (1 sizeMb>0, 2 sizeMb=0)

MockDataSeeder.seed():
  write 1-byte placeholder → recordingPath(matchId)  for sizeMb>0 matches

isOnDeviceProvider(matchId):  FutureProvider.family<bool, String>
  → File(await videoPathSvc.recordingPath(matchId)).existsSync()
  → invalidated after downloadRecording completes

VideoPage (new):
  filteredLibraryMatchesProvider → filtered List<LibraryMatch>
  search: teamName OR shortName OR opponent  (R8)
  Team chip filter: teamId match OR opponent string match  (R7, AE4)
  Team filter chips: from teamsControllerProvider  (existing provider)

VideoMatchDetailPage (updated):
  _scoreOverlayOn: bool  (R3)
  _eventsOverlayOn: bool  (R3)
  overlayStates: List<OverlayState>  derived from match.events  (R23)
  scrubber position → binary search overlayStates → render current OverlayState
```

---

## Implementation Units

### U1. OverlayState and OverlayConfig models

**Goal:** Define the `OverlayState` and `OverlayConfig` contract types and a helper that derives a `List<OverlayState>` from a match's event log. These are the foundational types all other units depend on.

**Requirements:** R21, R23, R24

**Dependencies:** None

**Files:**
- Create: `lib/core/models/overlay.dart`
- Test: `test/core/models/overlay_test.dart`

**Approach:**
- `OverlayState` is an immutable value type: `timeSeconds`, `homeScore`, `awayScore`, `period`, `recentEventLabel` (nullable)
- `OverlayConfig` is a simple value type: `showScore`, `showEvents` — used as a parameter in `downloadRecordingWithOverlays`
- Add a static `OverlayState.fromEvents(List<LibraryEvent> events, {required int periodLengthSeconds, required String homeShortName})` factory that builds a chronologically ordered list by scanning events, accumulating scores on goal events, and computing period from `event.timeSeconds ~/ periodLengthSeconds + 1`
- Add a static `OverlayState.atTime(List<OverlayState> states, int timeSeconds)` helper that binary-searches for the largest `timeSeconds <= currentPosition` — returns the baseline state (scores 0, period 1) if the list is empty or the position is before the first event

**Patterns to follow:**
- `lib/core/models/match.dart` — immutable value types with named fields
- `lib/features/video/video_state.dart` `LibraryEvent` — the event type consumed here

**Test scenarios:**
- Happy path: given 3 goal events at 10 s (home), 25 s (away), 40 s (home), `fromEvents` returns 4 states — initial + one per event with cumulative scores [0-0, 1-0, 1-1, 2-1]
- Edge case: empty event list → `fromEvents` returns a single baseline state `{0, 0, 0, period: 1, null}`
- Edge case: goal event for a team whose shortName doesn't match homeShortName → increments awayScore
- Edge case: non-goal event (foul, card) → recentEventLabel updated, scores unchanged
- Edge case: `atTime(states, 0)` before any events → returns baseline
- Edge case: `atTime(states, 10)` exactly at first event → returns first event's state
- Edge case: `atTime(states, 99999)` after all events → returns last state

**Verification:**
- `just test` passes for all new test cases
- `OverlayState` and `OverlayConfig` are importable from `lib/core/models/overlay.dart`
- No existing model files reference `overlay.dart` yet (confirmed no naming collision)

---

### U2. Fixture data correction and mock seeding

**Goal:** Fix the three fixture data bugs (double "vs", EFC has no matches, all NR matches appear "on device"), add EFC match records, and make `MockDataSeeder` write placeholder files so the `isOnDeviceProvider` check works correctly in dev mode.

**Requirements:** R4, R5, R9, R19 (UUID-based identity)

**Dependencies:** None (data-only; U5 and U6 consume the corrected data)

**Files:**
- Modify: `assets/ble/fixtures/matches.json`
- Modify: `lib/mock/mock_data_seeder.dart`
- Test: `test/mock/mock_data_seeder_test.dart`

**Approach:**
- In `matches.json`, strip `"vs "` prefix from all `opponent` fields (e.g. `"vs Eastfield FC"` → `"Eastfield FC"`)
- Set two NR past matches to `sizeMb: 0` (on camera only); keep two with `sizeMb > 0` (on device)
- Add 3 EFC past match records with realistic event logs (goals, cards), with 1 `sizeMb > 0` (on device) and 2 `sizeMb: 0`
- NR opponent list should include `"Eastfield FC"` in at least one match, and EFC opponent list should include `"Northridge U14"` in at least one match, so AE4 (cross-search) passes
- In `MockDataSeeder.seed()`, after inserting matches, iterate matches where `sizeMb > 0` and write a 1-byte placeholder file at `await videoPathService.recordingPath(match.id)` using `File.writeAsBytes([0])` with `recursive: true` directory creation
- `MockDataSeeder` constructor receives a `VideoPathService` dependency (or resolves it via `path_provider`)
- Do not copy 99 MB mock-video.mp4; the placeholder only needs to exist for `File.existsSync()` to return true
- **Transaction ordering:** `File.writeAsBytes()` calls must run in a second `Future.wait` AFTER `await _db.transaction()` completes — not inside the transaction closure. Drift transactions run in the database executor context; mixing `dart:io` async file writes inside them can cause deadlocks. Pattern: `await _db.transaction(() async { /* inserts */ }); await Future.wait([ /* file writes */ ]);`

**Patterns to follow:**
- `lib/mock/mock_data_seeder.dart` — `Future.wait` parallel fixture load, `insertAllOnConflictUpdate`
- `lib/core/services/video_path_service.dart` — `recordingPath()` for path derivation

**Test scenarios:**
- Happy path: after `seed()`, all match records exist in DB; NR has 4, EFC has 3
- Happy path: after `seed()`, file exists at `recordingPath(matchId)` for every match with `sizeMb > 0`
- Happy path: after `seed()`, no file exists at `recordingPath(matchId)` for matches with `sizeMb: 0`
- Edge case: `seed()` called twice (idempotent) — fixture rows are upserted; placeholder files are overwritten without error
- Edge case: opponent strings contain no `"vs "` prefix in fixture JSON after this change — verify by reading back from DB

**Verification:**
- Running the app in dev mode: Video tab shows 7 total matches (4 NR + 3 EFC); some show on-device indicator, some do not
- `just test` passes for seeder tests

---

### U3. WifiService interface extension

**Goal:** Add four new abstract method declarations to the `WifiService` interface to cover the camera recording contract: `checkCameraHasRecording`, `downloadRecording`, `downloadRecordingWithOverlays`, and `overlayStateStream`. Both `MockWifiService` and `WifiServiceImpl` must implement them (covered in U4).

**Requirements:** R19, R20, R21, R22, R24

**Dependencies:** U1 (OverlayState + OverlayConfig types)

**Files:**
- Modify: `lib/core/wifi/wifi_service.dart`

**Approach:**
- Add a `// Recordings` section after the Downloads section in the interface
- `Future<bool> checkCameraHasRecording(String uuid)` — returns whether the camera has a raw recording for this UUID; replaces the need for any BLE round-trip for library state
- `Future<VideoDownloadHandle> downloadRecording(String deviceId, String uuid)` — initiates a full-game download identified by UUID; returns the same progress handle type as `startDownload`
- `Future<VideoDownloadHandle> downloadRecordingWithOverlays(String deviceId, String uuid, List<OverlayState> overlays, OverlayConfig config)` — same as above but sends the overlay manifest with the request; mock returns raw video; contract is defined for firmware
- `Stream<OverlayState> overlayStateStream(String deviceId)` — live stream of current overlay state at ~1 Hz; for use by live-match surfaces; video review page does not use this (derives from DB)
- Import `overlay.dart` at the top of `wifi_service.dart`
- Document each method with a doc comment explaining its role in the camera-app contract

**Patterns to follow:**
- Existing abstract methods in `lib/core/wifi/wifi_service.dart`

**Test scenarios:**
- Test expectation: none — this unit adds abstract declarations only; behavior is tested in U4

**Verification:**
- `just analyze` passes (no missing overrides in MockWifiService or WifiServiceImpl, since U4 adds them)
- Each new method is documented in the interface

---

### U4. MockWifiService, WifiServiceImpl, and BleServiceImpl — implement all stubs

**Goal:** Eliminate every `UnimplementedError` in the app. This sprint's scope adds four new `WifiService` methods, but also clears the two pre-existing stubs in `BleServiceImpl` (`sendCommand`, `pushSessionConfig`) and the three pre-existing stubs in `WifiServiceImpl` (`connectGroup`, `disconnectGroup`, `startDownload`). After this unit, no `*Impl` class may throw `UnimplementedError` for any method.

`MockWifiService` is the emulated implementation selected in dev mode (`kAppEnv.isDevBackend`) and injected in tests via Riverpod overrides. `WifiServiceImpl` is the production-class that carries the same emulated behavior until real hardware is wired — method bodies are replaced, not stubbed.

**Requirements:** R19, R20, R22, R24

**Dependencies:** U1, U3

**Files:**
- Modify: `lib/mock/mock_wifi_service.dart`
- Modify: `lib/core/wifi/wifi_service_impl.dart`
- Modify: `lib/core/ble/ble_service_impl.dart`
- Test: `test/mock/mock_wifi_service_test.dart`

**Approach:**

*MockWifiService — new methods:*
- `checkCameraHasRecording(uuid)`: returns `true` for any UUID; simulates the camera always having the recording
- `downloadRecording(deviceId, uuid)`: reuses the existing tick-loop pattern from `startDownload`; on completion, writes a 1-byte placeholder at `await videoPathService.recordingPath(uuid)` so `isOnDeviceProvider` passes after download; returns a `VideoDownloadHandle` with progress stream
- `downloadRecordingWithOverlays(deviceId, uuid, overlays, config)`: same as `downloadRecording`; ignores overlays and config in mock mode (documented in a comment for firmware team)
- `overlayStateStream(deviceId)`: `Stream.periodic(Duration(seconds: 1))` emitting a synthetic `OverlayState` (scores 0-0, period 1, null label)

*WifiServiceImpl — replace ALL stubs with emulated behavior:*
- `connectGroup`: `Future.delayed` + returns a hardcoded `WifiDirectGroup` with fake SSID/PSK/IPs
- `disconnectGroup`: `Future.delayed` then completes normally
- `connectionStateStream`: emits `WifiDirectState.connected` after a brief delay
- `startDownload`: same tick-loop as `MockWifiService`
- `checkCameraHasRecording`, `downloadRecording`, `downloadRecordingWithOverlays`, `overlayStateStream`: identical emulated behavior to `MockWifiService`
- `previewFrames`, `previewStats`: synthetic frames/stats at same rate as mock

*BleServiceImpl — replace ALL stubs with emulated behavior:*
- `sendCommand<T>(deviceId, command)`: returns an error-state `BleCommandResponse<T>` with a message like `"not implemented — pending firmware wiring"`. Do NOT copy response-construction logic from `MockBleService`; that belongs in the mock layer only. The error-state response keeps the type contract satisfied without producing fake data in non-dev builds.
- `pushSessionConfig(deviceId, config)`: completes normally (noop emulation); documents that real implementation sends proto-encoded config over BLE characteristic

**Patterns to follow:**
- `lib/mock/mock_wifi_service.dart` — tick-loop download, stream controllers, dispose pattern

**Test scenarios:**
- Happy path: `MockWifiService().checkCameraHasRecording('any-uuid')` returns `true`
- Happy path: `downloadRecording` progress stream emits increasing bytesReceived, completes with file path
- Happy path: after `downloadRecording` completes, `File(recordingPath).existsSync()` returns true
- Happy path: `overlayStateStream` emits an `OverlayState` within 1.5 seconds
- Happy path: `downloadRecordingWithOverlays` completes with same behavior as `downloadRecording`
- Edge case: cancel handle during `downloadRecording` — progress stream closes without error, placeholder file not written
- Integration: `WifiServiceImpl` satisfies the same scenarios as `MockWifiService`; no `UnimplementedError` thrown for any method
- Integration: `BleServiceImpl.sendCommand` returns a `BleCommandResponse` (error-state, not success) without throwing
- Integration: `BleServiceImpl.pushSessionConfig` completes without throwing

**Verification:**
- `grep -rn "UnimplementedError" lib/` returns zero results
- `just analyze` clean
- `just test` passes for mock wifi service tests
- Non-dev build (`--dart-define=APP_ENV=stage`) launches and all service methods complete without throw

---

### U5. LibraryMatch + video_state providers

**Goal:** Add `teamName` to `LibraryMatch`, replace the `sizeMb`-based `downloadState` with a file-existence `isOnDeviceProvider`, broaden search to include opponent string, and remove providers that were specific to the team-grouped UI.

**Requirements:** R1, R6, R7, R8, R10

**Dependencies:** U2 (fixture data has corrected opponent strings)

**Files:**
- Modify: `lib/features/video/video_state.dart`
- Test: `test/features/video/video_state_test.dart`

**Approach:**
- Add `teamName: String` to `LibraryMatch`; populate from `row.team.name` in `_rowToLibraryMatch`
- Add `teamShortName: String` to `LibraryMatch`; populate from `row.team.shortName` in `_rowToLibraryMatch` — needed by U7 for `OverlayState.fromEvents(homeShortName:)` and by U6 for the badge
- Add `periodLengthSeconds: int` to `LibraryMatch`; populate from `match.periodLengthSeconds` in `_rowToLibraryMatch` — needed by U7 for period computation in `OverlayState.fromEvents(periodLengthSeconds:)`
- Keep `downloadState` field on `LibraryMatch` unchanged (`'all-local'` / `'remote'`) — it is a camera-state signal indicating whether the camera has the recording; do NOT rename it; U7 and U9 already reference `match.downloadState`
- Add `isOnDeviceProvider(matchId)` as `FutureProvider.family<bool, String>`: resolves `videoPathServiceProvider`, calls `File(await svc.recordingPath(matchId)).existsSync()`; this is the authoritative check for R10
- Create `filteredLibraryMatchesProvider` as a new `Provider<List<LibraryMatch>>` that watches `libraryProvider`, `librarySearchQueryProvider`, `librarySportFilterProvider`, and a new `libraryTeamFilterProvider` (`StateProvider<String?>`); applies all three filters; search is case-insensitive against `teamName`, `teamShortName`, and `opponent` string (all three, same as R8)
- Team filter in `filteredLibraryMatchesProvider`: matches any match where `match.teamId` equals the selected team's id OR `match.opponent.toLowerCase()` contains the selected team's `shortName.toLowerCase()` — identical to search bar behavior per AE4
- Remove `libraryStatsByTeamProvider` — no longer consumed after VideoPage refactor
- Keep `librarySearchQueryProvider` and `librarySportFilterProvider` unchanged
- **Do NOT add a new `trackedTeamsProvider`** — use the already-imported `teamsControllerProvider` (from `lib/features/teams/teams_state.dart`) directly in VideoPage for Team filter chips; `video_state.dart` already imports it for `filteredLibraryTeamsProvider`

**Patterns to follow:**
- `lib/features/video/video_state.dart` — `_rowToLibraryMatch`, `libraryProvider` pattern
- `lib/core/state/db_providers.dart` — FutureProvider with `videoPathServiceProvider`

**Test scenarios:**
- Happy path: `LibraryMatch.teamName` equals `team.name` (not shortName)
- Happy path: searching "NR" in `filteredLibraryMatchesProvider` returns matches where NR is teamShortName AND matches where "Northridge" appears in opponent string
- Covers AE4. Happy path: given NR match vs EFC AND EFC match vs NR in DB, searching "NR" returns both
- Happy path: `isOnDeviceProvider('mock-match-001')` returns `true` after placeholder file written by seeder
- Happy path: `isOnDeviceProvider('mock-match-002')` returns `false` when no file at recording path
- Edge case: sport filter "Soccer" + team filter "NR" — returns only NR soccer matches
- Edge case: empty search query → all matches returned

**Verification:**
- `just test` passes
- `just analyze` clean

---

### U6. VideoPage — flat match list with filters and search

**Goal:** Replace the team-grouped `VideoPage` with a flat, searchable match list. Delete `VideoTeamMatchesPage`. Fix R1 (full name in title) and R2 (no double "vs") in the new page. Implement sport/team filter chips and search bar per F1.

**Requirements:** R1, R2, R6, R7, R8, R9

**Dependencies:** U2 (corrected fixture data), U5 (teamName on LibraryMatch, broadened search)

**Files:**
- Modify: `lib/features/video/video_page.dart`
- Delete: `lib/features/video/video_team_matches_page.dart`
- Test: `test/features/video/video_page_test.dart`

**Approach:**
- `VideoPage` consumes `filteredLibraryMatchesProvider` (filtered flat match list from U5)
- Layout: search bar at top → sport chip row → team chip row → `ListView` of match cards
- Sport chips built from `availableLibrarySportsProvider`; Team chips built from `teamsControllerProvider` (short names as labels); selecting a chip writes to `libraryTeamFilterProvider`
- Team chip filter: includes matches where the team is the recording team OR appears as opponent — matches AE4; same logic as the search bar
- Each match card shows: `[ShortNameBadge]` + `"${match.teamName} vs ${match.opponent}"` + date + result + on-device indicator
- Badge uses `match.teamShortName`; title text uses `match.teamName` → fixes R1
- Opponent is stored without `"vs "` prefix (fixed in U2), so `"${match.teamName} vs ${match.opponent}"` renders correctly → fixes R2
- **On-device indicator states:** use a `ref.watch(isOnDeviceProvider(match.id))` inside the card. Loading: render a fixed-width `SizedBox(width: 48, height: 16)` placeholder to prevent card layout jank. Resolved-true: show a small label/chip ("On device"). Resolved-false: render nothing (or "Camera" if space allows).
- **libraryProvider async states:** `filteredLibraryMatchesProvider` derives from a `StreamProvider`; wrap the top-level `ListView` in an `AsyncValue` handler — loading shows a centered `CircularProgressIndicator`; error shows an inline error message with a retry affordance.
- **Filter-empty state:** when the filtered list is empty but `libraryProvider` has data, show a "No matches for this filter" message with a "Clear filters" button that resets `librarySportFilterProvider` and `libraryTeamFilterProvider`. This is distinct from the zero-library empty state (which shows "Connect camera").
- Tapping a card navigates to `VideoMatchDetailPage(matchId: match.id)`
- `VideoTeamMatchesPage` is deleted; remove any import or route reference to it across the codebase

**Patterns to follow:**
- `lib/features/video/video_page.dart` — existing filter chip row pattern, `WfChip` for chips
- `lib/core/widgets/wf_card.dart` — `WfCard`, `ThumbPlaceholder`, widget composition patterns

**Test scenarios:**
- Covers AE1. Given NR match card, badge text is "NR", title text is "Northridge U14 vs Eastfield FC"
- Covers AE2. Given opponent stored as "Eastfield FC" (no "vs" prefix), rendered title is "Northridge U14 vs Eastfield FC" not "... vs vs ..."
- Covers AE4. Given NR match vs EFC and EFC match vs NR both in library, unfiltered list shows both rows; selecting Team chip "NR" also returns both rows (NR as recording team AND NR as opponent)
- Happy path: Sport filter → Soccer → only soccer matches shown
- Happy path: Team chip "NR" → returns NR's own matches AND matches where NR is the opponent string
- Happy path: search "NR" → same result as Team chip "NR" — covers R8
- Happy path: libraryProvider loading state → `CircularProgressIndicator` shown instead of list
- Happy path: libraryProvider error state → inline error message shown with retry
- Happy path: Sport filter applied with no matches → filter-empty state shown with "Clear filters" CTA (not the "Connect camera" zero-library state)
- Happy path: empty library (no data at all) → zero-library empty state shown
- Happy path: tapping a match card navigates to `VideoMatchDetailPage`
- Edge case: `isOnDeviceProvider` in loading state → card renders with fixed-size placeholder, no layout jank

**Verification:**
- `just test` passes
- `just analyze` clean — no import of deleted `VideoTeamMatchesPage`
- Manually: Video tab shows flat list with search and filter chips; both NR and EFC match cards are visible

---

### U7. Video playback — on-device detection and video player

**Goal:** Wire `VideoMatchDetailPage` to detect whether the match is on device and select the appropriate playback source — local file (mock asset) or WiFi stream (auto-connect + mock asset). Connects overlay derivation from OverlayState list (without independent toggle — that's U8).

**Requirements:** R10, R11, R12, R13, F2, F3

**Dependencies:** U1 (OverlayState), U4 (WifiService new methods), U5 (isOnDeviceProvider)

**Files:**
- Modify: `lib/features/video/playback/video_match_detail_page.dart`
- Test: `test/features/video/playback/video_match_detail_page_test.dart`

**Approach:**
- In `initState` / `didChangeDependencies`, check `isOnDeviceProvider(match.id)` — if true, initialize `VideoPlayerController.asset('assets/ble/mock-video.mp4')`; if false, call `wifiService.connectGroup(activeDeviceId)` then also initialize `VideoPlayerController.asset('assets/ble/mock-video.mp4')` (mock uses the asset regardless of source)
- Show a "Connecting…" loading state while WiFi connection is being established for camera-stream case
- **WiFi connection error state:** if `connectGroup` throws or the connection does not complete within ~10 seconds, transition to an error state showing an inline error message ("Could not connect to camera") and a "Retry" button. The video player is NOT initialized. No crash — errors are caught and displayed.
- After player is initialized, replace `ThumbPlaceholder` with a real `VideoPlayer` widget inside the `Stack`
- Derive `_overlayStates` from `OverlayState.fromEvents(match.events, periodLengthSeconds: match.periodLengthSeconds, homeShortName: match.teamShortName)` on init
- Scrubber position fraction update → compute `currentTimeSeconds = fraction × maxSecs` → `OverlayState.atTime(_overlayStates, currentTimeSeconds)` → current `OverlayState` stored in state
- Score overlay and event overlay widgets read from current `OverlayState` (hardcoded values removed)
- Use `ref.read(videoPathServiceProvider)` instead of `VideoPathService()` direct instantiation
- Use `ref.read(wifiServiceProvider)` for auto-connect

**Patterns to follow:**
- `lib/features/video/playback/video_match_detail_page.dart` — existing `Stack`/`Positioned` overlay structure
- `lib/mock/mock_wifi_service.dart` — `connectGroup` returns a `WifiDirectGroup`

**Test scenarios:**
- Covers AE5. Given match with no local file, opening detail page initiates WiFi connect (mock) and shows mock video player
- Covers AE6. Given match with local placeholder file, opening detail page plays local file without WiFi connect
- Happy path: scrubber at 37 % of a 90-minute match → OverlayState at that timestamp is rendered in overlay
- Happy path: overlay shows scores from OverlayState (not hardcoded "NR · 2 · 1H · 1 · EFC")
- Edge case: match has no events → `_overlayStates` is a single baseline state; overlay shows 0-0 throughout
- Edge case: player init fails (asset not found) → error state shown, no crash
- Edge case: `connectGroup` fails for camera-stream path → error state shown with retry button; no player init
- Edge case: `connectGroup` mock completes successfully → player initialized with mock asset, overlay renders
- Integration: opening a "camera only" match in dev mode → mock WiFi connect completes → mock video plays → overlay renders

**Verification:**
- `just test` passes
- Manually: opening an on-device match plays mock video with correct overlay values; opening a camera-only match shows connecting state then plays mock video

---

### U8. Independent overlay toggles + bug fix R3

**Goal:** Replace the single `_overlaysOn` boolean in `VideoMatchDetailPage` with independent `_scoreOverlayOn` and `_eventsOverlayOn` booleans. Update `_OverlayToggleRow` so each chip is a real interactive toggle. Score overlay and events overlay are independently shown/hidden.

**Requirements:** R3, R13

**Dependencies:** U7 (video player and OverlayState wiring in place)

**Files:**
- Modify: `lib/features/video/playback/video_match_detail_page.dart`

**Approach:**
- Replace `bool _overlaysOn = true` with `bool _scoreOverlayOn = true` and `bool _eventsOverlayOn = true`; also add `bool _lastScoreOn = true` and `bool _lastEventsOn = true`
- `_lastScoreOn` and `_lastEventsOn` are initialized to `true` and are updated ONLY when an individual chip is tapped — never when master toggle forces them off. This preserves last user-set state for restore on master toggle ON.
- `_OverlayToggleRow` receives both bools and two `ValueChanged<bool>` callbacks: `onScoreChanged` and `onEventsChanged`
- Individual chip interaction: wrap each `WfChip` in a `GestureDetector` (since `WfChip` has no `onTap` parameter). `WfChip` has `key, label, active, leading` only — do not pass `onTap` directly to it.
  - Score chip: `GestureDetector(onTap: () => setState(() { _lastScoreOn = !_scoreOverlayOn; _scoreOverlayOn = !_scoreOverlayOn; }), child: WfChip(label: 'Score', active: _scoreOverlayOn))`
  - Events chip: same pattern for `_eventsOverlayOn` / `_lastEventsOn`
- The `WfSwitch` in the toggle row becomes "master toggle" — when toggled off, sets both to false without updating `_last*`; when toggled on, restores `_scoreOverlayOn = _lastScoreOn` and `_eventsOverlayOn = _lastEventsOn`
- In `_Player`, score overlay `Positioned` widget is wrapped in `if (_scoreOverlayOn)` and events overlay in `if (_eventsOverlayOn)`

**Patterns to follow:**
- `lib/features/video/playback/video_match_detail_page.dart` — `_OverlayToggleRow`, `WfChip`, `WfSwitch` usage

**Test scenarios:**
- Covers AE3. Given both overlays ON, toggling Events OFF hides event ticker but score overlay remains visible
- Covers AE3. Given Events OFF, toggling Score OFF hides score overlay; both now hidden
- Happy path: master switch OFF → both hidden; master switch ON → both restored to their pre-off state
- Happy path: toggling Score independently does not affect Events state and vice versa
- Edge case: all off (master), then master on → both chips restored to `true` (initial `_last*` values)
- Edge case: Score individually toggled OFF, then master OFF then master ON → Score stays OFF, Events stays ON (last individual states preserved)

**Verification:**
- `just test` passes
- Manually: Score and Events chips in the match detail page are individually tappable and control their respective overlays independently

---

### U9. Full-game download

**Goal:** Wire the full-game download flow to the new `wifiService.downloadRecording(deviceId, uuid)` method. Show live progress. On completion, invalidate `isOnDeviceProvider` so the UI updates without a reload. The existing progress UI in `DownloadSheet` is reused.

**Requirements:** R14, R15, F4

**Dependencies:** U3, U4 (downloadRecording method), U5 (isOnDeviceProvider to invalidate)

**Files:**
- Modify: `lib/features/video/playback/download_sheet.dart`
- Modify: `lib/features/video/playback/video_match_detail_page.dart` (download trigger + invalidation)
- Test: `test/features/video/playback/download_sheet_test.dart`

**Approach:**
- In `DownloadSheet`, call `wifiService.downloadRecording(activeDeviceId, match.id)` instead of the current `bleService.requestDownload` → `wifi.startDownload` sequence
- **Remove out-of-scope options from `DownloadSheet`**: delete the `h1` (1st half), `h2` (2nd half), `hi` (All highlights), and `hisel` (Selected highlights) `_Opt` entries. Only the `full` (Full game) option remains. The `_selected` default becomes `'full'` unconditionally.
- The returned `VideoDownloadHandle` feeds the existing progress stream listener — no UI changes needed for the progress view
- **Invalidation call site:** inside `handle.progress.listen`'s `onDone` callback in `_DownloadSheetState`, after confirming `_progress?.status == DownloadStatus.completed`, call `ref.invalidate(isOnDeviceProvider(widget.match.id))`. This is the only call site.
- On cancel, close the sheet without invalidating
- The download button is only shown when `!isOnDevice` (checked before showing the sheet)

**Patterns to follow:**
- `lib/features/video/playback/download_sheet.dart` — existing progress listener, `setState` on progress
- `lib/mock/mock_wifi_service.dart` — `downloadRecording` returns a `VideoDownloadHandle`

**Test scenarios:**
- Covers AE6. Happy path: `downloadRecording` completes → `isOnDeviceProvider(matchId)` returns true on next resolution
- Happy path: progress stream emits increasing values → `LinearProgressIndicator` value updates
- Happy path: cancel button during download → progress stream closes, sheet dismisses, file not written
- Happy path: download button is disabled / not shown when match is already on device
- Error path: `downloadRecording` emits an error → sheet shows error state, allows retry
- Integration: complete download flow in dev mode → file placeholder written → video player switches to local source on next open

**Verification:**
- `just test` passes
- Manually: tapping Download on a camera-only match shows progress, completes, and the on-device indicator appears on the match card

---

### U10. Per-event highlight clip creation

**Goal:** Add a "Clip" button to each event row in the `VideoMatchDetailPage` event list. Tapping it checks `isOnDevice`, prompts to download if not, then trims ±15 s around the event timestamp using the existing `ClipService`. Multiple clips per match are supported.

**Requirements:** R16, R17, R18, F5

**Dependencies:** U7 (isOnDevice check in detail page), U9 (download flow for prompt)

**Files:**
- Modify: `lib/features/video/playback/video_match_detail_page.dart`
- Test: `test/features/video/playback/video_match_detail_page_test.dart`

**Approach:**
- Each event row in `_EventList` gains a small "Clip" `WfButton` (size: `sm`, variant: `outline`) placed as the **trailing widget** on the right side of the row, after the event label. The row layout becomes: `[checkbox] [clock] [label (expanded)] [Clip button]`.
- **In-progress state (per-event):** track a `Set<int> _clippingEventIndices` in `VideoMatchDetailPage` state. When `_clipEvent` starts for an event, add its index; remove on completion or error. While an event's index is in `_clippingEventIndices`, its Clip button is replaced with a small `SizedBox`-wrapped `CircularProgressIndicator`. This prevents duplicate taps for the same event while allowing other events to be clipped concurrently.
- `_clipEvent(LibraryEvent event, int index)` async method:
  1. Check `await ref.read(isOnDeviceProvider(match.id).future)` — if false, show snackbar "Download the full match first to create clips" and return
  2. Add `index` to `_clippingEventIndices` via `setState`
  3. Compute `startSeconds = max(0, event.timeSeconds - 15)`, `durationSeconds = 30`
  4. Call `clipSvc.trim(matchId: match.id, sourcePath: await videoPathSvc.recordingPath(match.id), startSeconds: startSeconds, durationSeconds: durationSeconds, label: event.label)` — note: `sourcePath` is `videoPathSvc.recordingPath(match.id)`, the same path where the placeholder was written
  5. On success, show snackbar "Clip saved"
  6. On `ClipTrimException`, show snackbar with error message
  7. Remove `index` from `_clippingEventIndices` via `setState` (in finally block)
- Remove the old footer "Clip" button that used scrubber position; replace with per-event buttons
- Use `ref.read(videoPathServiceProvider)` and `ref.read(clipServiceProvider)` (not direct instantiation)
- Multiple concurrent clip creations are allowed across different events; each runs independently

**Patterns to follow:**
- `lib/features/video/playback/video_match_detail_page.dart` — existing `_createClip` method and snackbar pattern
- `lib/core/services/clip_service.dart` — `trim()` signature and `ClipTrimException`

**Test scenarios:**
- Covers AE7. Given match not on device, tapping "Clip" on any event shows "Download the full match first to create clips" snackbar and does not call `clipSvc.trim`
- Covers AE8. Given match on device with Goal event at 37:22 (= 2242 s), tapping "Clip" calls `trim` with `startSeconds = max(0, 2242 - 15) = 2227`, `durationSeconds = 30`, and `sourcePath = videoPathSvc.recordingPath(match.id)` (the path where the placeholder was written by the seeder or download)
- Happy path: event at timeSeconds = 10 → startSeconds clamped to 0 (not negative)
- Happy path: two events clipped from the same match → two separate clip files created concurrently
- Happy path: while clip is creating, that event's button shows a spinner; other events' buttons remain enabled
- Happy path: successful clip → "Clip saved" snackbar shown, spinner replaced by Clip button
- Error path: `ClipTrimException` thrown → error snackbar shown, no crash, spinner replaced by Clip button

**Verification:**
- `just test` passes
- Manually: tapping "Clip" on a downloaded match's event creates a clip file; tapping on a non-downloaded match shows the download prompt

---

## System-Wide Impact

- **Interaction graph:** `isOnDeviceProvider` is read by `VideoPage` (indicator), `VideoMatchDetailPage` (player source), and `download_sheet.dart` (show/hide button). Invalidation in U9 propagates to all three consumers.
- **Error propagation:** `ClipTrimException` and WiFi errors are caught at the call site and shown as snackbars; they do not propagate to provider layer.
- **State lifecycle risks:** `VideoPlayerController` must be disposed in `dispose()` to avoid memory leaks; multiple rebuild cycles (on-device check resolves) must not reinitialize the controller.
- **API surface parity:** `WifiServiceImpl` and `MockWifiService` must implement identical method signatures; both are verified by the abstract interface at compile time.
- **Integration coverage:** The full F4 flow (download → placeholder written → `isOnDeviceProvider` invalidated → video player uses local source on next open) is an integration scenario that unit tests alone will not prove; U9's integration test scenario covers it.
- **Unchanged invariants:** BLE service, Match tab, Live tab, and Settings tab are unaffected. `video_player` package is already in `pubspec.yaml`; no dependency changes needed.

---

## Risks & Dependencies

| Risk | Mitigation |
|------|------------|
| `VideoPlayerController.asset()` has poor performance on some Android emulators in devcontainer | Acceptable for dev mode; use `ThumbPlaceholder` as fallback if player init fails |
| `File.existsSync()` inside `FutureProvider` called on UI thread may block briefly | Async resolution of `getApplicationSupportDirectory()` is the slow part; `existsSync()` itself is fast once path is known; no UI jank expected |
| `MockWifiService.downloadRecording` placeholder write races with `isOnDeviceProvider` read | Invalidation in U9 fires after the write completes (inside the completion callback), not concurrently |
| Deleting `VideoTeamMatchesPage` without checking all references | `grep -r "VideoTeamMatchesPage"` before deletion; fix any remaining import or route |
| `ffmpeg_kit_flutter_new_full` trim fails on Android API 36 emulator in devcontainer | FFmpeg is already used in `ClipService` and working; no new integration risk |

---

## Sources & References

- **Origin document:** [docs/brainstorms/2026-05-22-video-library-overhaul-requirements.md](docs/brainstorms/2026-05-22-video-library-overhaul-requirements.md)
- `lib/core/wifi/wifi_service.dart` — interface to extend
- `lib/mock/mock_wifi_service.dart` — MockWifiService pattern to mirror in WifiServiceImpl
- `lib/core/services/clip_service.dart` — FFmpeg trim implementation
- `lib/mock/mock_data_seeder.dart` — fixture seeding pattern
- `assets/ble/fixtures/matches.json` — fixture data to correct
- `docs/solutions/architecture-patterns/app-source-of-truth-drift-sqlite-2026-05-06.md`
- `docs/solutions/conventions/isdevbackend-must-not-bypass-connection-state-guards-2026-05-19.md`
- `docs/solutions/logic-errors/activetabprovider-one-way-binding-silent-navigation-failure-2026-05-21.md`
