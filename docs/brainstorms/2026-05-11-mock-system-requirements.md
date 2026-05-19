---
date: 2026-05-11
topic: mock-system-and-dev-tooling
---

# Mock System & Dev Tooling

## Summary

Introduce a two-level data flag system (`AppEnv` for environment behavior, `kUseMockData` for fixture injection), a committed asset-backed mock fixture layer, on-device DB inspection tooling, standardized file paths, a single-video mock source for all playback and live-stream scenarios, highlight trimming via DB-stored event timestamps, a compact live-score section on the live preview page, documented data contracts for every major screen, and a cleanup pass to erase all "Phase 7" labels from code and docs while ensuring mock coverage for every affected surface.

---

## Problem Frame

Development and testing of the Scout Camera app currently require a physical camera or a partially-wired mock that cannot walk through the full app without dead buttons or missing data. Several compounding issues make the dev experience fragile:

- The single `AppEnv` enum conflates environment-level behavior (logging, API endpoints) with data concerns (which mock data to load), making it impossible to run in "real device, no extra fixtures" mode or to reset cleanly to a known mock state.
- Downloads save to `/tmp`, which is device-transient, not portable, and invisible to the app's own file management.
- The live preview page has no compact score display — developers must dig through an event log to know the current score while testing live-match UI.
- "Phase 7" placeholder comments and `UnimplementedError` throws are scattered across `ble_service_impl.dart`, `wifi_service_impl.dart`, and `app_data.dart`, misleading contributors about the current implementation status.
- The `ClipsTable` is deferred and unused, even though the app's highlight model (store event timestamps, trim on demand) is now settled.
- There is no way to inspect DB state from an emulator without external tooling or a manual `adb pull`.

---

## Actors

- A1. **Developer** — runs the app on an emulator or device, toggles mock mode, inspects DB state, tests all screens without a real camera.
- A2. **End user** — creates, views, and shares match highlights; watches live-stream preview; reviews event logs.

---

## Key Flows

- F1. **App launch in mock mode**
  - **Trigger:** App starts with `kUseMockData=true`.
  - **Actors:** A1.
  - **Steps:** (1) App checks for existing DB. (2) If DB does not exist or a reset was requested, it seeds base data (default user, sports, formats). (3) It then loads mock fixture JSON files from the asset bundle into the DB (teams, matches, events, recordings, streaming destinations). (4) App lands on the main screen with all mock data visible.
  - **Outcome:** Every screen shows realistic data; no dead buttons; no empty states.
  - **Covered by:** R2, R3, R4, R5, R6.

- F2. **Reset app state**
  - **Trigger:** Developer taps "Reset" in the in-app debug screen.
  - **Actors:** A1.
  - **Steps:** (1) DB is dropped and rebuilt with base seed. (2) If `kUseMockData=true`, mock fixtures are re-loaded from assets. (3) App navigates to root.
  - **Outcome:** App is back to a clean known state — either base-only or base+mock depending on the flag.
  - **Covered by:** R3, R6.

- F3. **View or share a highlight**
  - **Trigger:** A2 opens a match in the library and taps a specific event.
  - **Actors:** A2.
  - **Steps:** (1) App reads the event's timestamp and desired clip duration from the DB. (2) App trims the full match MP4 (cut-only, no re-encode) to produce a clip file in the app-private directory. (3) App plays the clip in-app or presents a system share sheet.
  - **Outcome:** A standalone MP4 clip exists on disk; user can play or share it.
  - **Covered by:** R14, R15, R16.

- F4. **Live preview with score**
  - **Trigger:** A1 or A2 opens the live preview page while connected to a camera (real or mock).
  - **Actors:** A1, A2.
  - **Steps:** (1) App receives the raw low-quality WiFi stream and renders it in a video player. (2) App polls match state and updates the event log. (3) A compact score section (derived from event log) is always visible on the page. (4) In mock mode, the mock-video asset loops in place of the real stream.
  - **Outcome:** Developer or user can follow match state at a glance without scrolling the event log.
  - **Covered by:** R11, R12, R13.

---

## Requirements

**Environment & flags**

- R1. `AppEnv` (dev / stage / prod) controls environment-level behavior only: log verbosity, diagnostic output, and similar. It does NOT gate mock data loading or base seeding. The existing `kAppEnv.isMock` getter is removed or repurposed to reflect environment level, not data level.
- R2. A separate boolean build flag `kUseMockData` (dart-define, default `false`) controls whether mock fixture data is loaded into the DB on first launch or after a reset. When `false`, only base seed data is present.
- R3. Reset behavior respects `kUseMockData`: reset with the flag true restores base + mock fixtures; reset with the flag false restores base data only.

**Base seed (always-on)**

- R4. On every fresh DB initialization — regardless of any flag — the app seeds a default user, all supported sport presets (covering every value in `kSports`), and default match formats. This is unconditional and not configurable.

**Mock fixtures**

- R5. Mock fixture data is defined as JSON files committed under `assets/mock/` and declared in `pubspec.yaml`. At minimum the fixture set covers: 1 team, 3 past matches with realistic event logs, 1 upcoming match, 2 recording entries, and 1 streaming destination.
- R6. The live SQLite database file is gitignored. It is always generated at runtime from seed + fixtures, never checked in.
- R7. Each fixture file has a documented schema comment at its top describing the fields and their types, so a developer can extend the fixture set without reading the DB code.

**File path standardization**

- R8. Video files downloaded from the device (full match recordings) are stored in the app-private support directory under a `videos/` subfolder, never in `/tmp` or any transient location. The mock download path in `MockWifiService` is updated to match.
- R9. Highlight clips produced by trimming are stored in the same app-private `videos/` subfolder with a filename that encodes the source recording ID and the clip's start time, making them identifiable without querying the DB.
- R10. Exports (DB backups, user-initiated file shares) continue to use the Documents directory as they do today.

**DB inspection**

- R11. An in-app debug screen is accessible only in non-prod builds (when `kAppEnv != AppEnv.prod`). It shows all major DB tables as browsable lists and exposes a "Reset" action. Access is via a hidden route — long-pressing the version label in Settings opens it.
- R12. Drift DevTools integration is added as a dev-dependency so the DB can be queried live from a Flutter DevTools browser tab during development. No runtime UI is added; the integration is transparent to non-dev builds.

**Mock video asset**

- R13. `mock-video.mp4` is declared as a Flutter asset in `pubspec.yaml` and bundled with the app. It is the single video source for all mock scenarios: full match playback, live stream preview, and highlight trim input. No other mock video files are introduced.

**Live preview page**

- R14. The live preview page shows the raw low-quality WiFi stream as a video player (or the looping mock asset in mock mode). It does not render the broadcast output or any firmware-side overlays.
- R15. A compact score section is always visible on the live preview page. It displays home team name, home score, away team name, and away score — derived live from the event log. It is not a full scoreboard; other match info is already present elsewhere on the page.
- R16. The event log on the live preview page shows all events in reverse-chronological order with timestamp, label, and team. Events are app-tracked; their content also drives the banners the firmware overlays on the broadcast stream, but the app does not receive or render those banners.

**Video playback**

- R17. Full match playback shows the raw video (no embedded overlays). An event timeline and a scoreboard overlay are independently toggleable by the user. Both are app-rendered.
- R18. In mock mode, the mock video asset is used as the playback source for every library match. The event data for each mock match is loaded from the mock fixtures so the timeline and score overlay reflect realistic events.

**Highlight trimming**

- R19. The `ClipsTable` in the DB stores highlight clip records: source recording ID, start offset (seconds), duration (seconds), and optional label. It replaces the pattern of saving multiple pre-cut video files per match.
- R20. When a user requests a highlight, the app trims the full match MP4 using the clip's start offset and duration (cut-only, no re-encode). The output is an MP4 file saved in the app-private `videos/` folder.
- R21. A trimmed clip can be played back in-app or shared via the system share sheet. The file format is always MP4; format conversion is the user's responsibility after export.

**Data contracts**

- R22. Every major screen that renders data has its input contract documented as a named type (or annotated parameter list) so mock fixtures can fully satisfy it without guessing. The minimum set of contracts to document:

  | Screen | Contract fields |
  |---|---|
  | Camera card (discovery) | `id: String, name: String, model: String, firmwareVersion: String, batteryPercent: int, rssi: int, connectionState: CameraConnectionState` |
  | Live preview | `deviceId: String, streamUrl: String, scoreSection: {homeTeam, awayTeam, homeScore, awayScore}, eventLog: [{timeSeconds, label, team, kind}]` |
  | Library match tile | `matchId: String, teamName: String, date: DateTime, opponentName: String, result: String, downloadState: DownloadState, totalBytes: int` |
  | Match playback | `matchId: String, videoPath: String, homeTeam: String, awayTeam: String, events: [{timeSeconds, label, team, kind}]` |
  | Recordings list (from device) | `id: String, durationSeconds: int, sizeBytes: int, startedAt: DateTime, sport: String` |
  | Clip row | `clipId: String, matchId: String, startSeconds: int, durationSeconds: int, label: String?` |

**Phase 7 cleanup**

- R23. All "Phase 7" labels, `TODO (Phase 7)` comments, and `StateError("Phase 7: ...")` throws are removed from `ble_service_impl.dart`, `wifi_service_impl.dart`, `app_data.dart`, and any plan or requirements documents that reference them. Remaining stubs are re-labeled as plain `UnimplementedError` or `TODO: wire to firmware` without phase numbering.
- R24. Every method in `MockBleService` and `MockWifiService` that was previously a stub or "Phase 7 not yet implemented" has a working mock implementation backed by the fixture layer or the mock video asset.
- R25. The comment in `app_data.dart` that says "library will move to BLE in Phase 7" is removed. The library provider either reads from the real BLE service (already implemented) or falls back to the mock fixture data in mock mode.

---

## Acceptance Examples

- AE1. **Covers R2, R3, R4, R5.** Given a fresh install with `kUseMockData=true`, when the app launches, the library screen shows at least 3 past matches, the settings screen shows a default user and teams, and no screen shows an empty state that requires a real camera.
- AE2. **Covers R3, R6.** Given the app is running with `kUseMockData=false` and the developer taps Reset in the debug screen, when the app restarts, only the default user and sport presets are present — no mock teams or matches.
- AE3. **Covers R8.** Given a mock download completes, when the app tries to play the file, the path is under the app-private support directory, not `/tmp`.
- AE4. **Covers R15, R16.** Given a live preview session is active in mock mode and a "Goal — Home" event is logged at 00:32, the score section immediately updates to show Home 1 – 0 Away without the user scrolling the event log.
- AE5. **Covers R20, R21.** Given a match with a "Goal" event at 12:30 exists in the library and its full MP4 is local, when the user requests a 30-second highlight clip starting 10 seconds before the event, an MP4 file appears in the app-private videos folder and can be played or shared.
- AE6. **Covers R23, R24.** Given the app is running in `devDevice` mode, when any BLE method previously guarded by a Phase 7 `StateError` is called, the call either succeeds (if now implemented) or throws a plain `UnimplementedError` — never a string containing "Phase 7".

---

## Success Criteria

- A developer can run `flutter run --dart-define=kUseMockData=true` and walk through every tab and every primary action in the app without encountering a dead button, an empty state that requires a device, or a crash.
- Resetting app state from the in-app debug screen reliably returns the app to a known fixture state or clean state, matching the `kUseMockData` flag.
- No file in the codebase contains the string "Phase 7" after the cleanup pass.
- The compact score section on the live preview page reflects the correct cumulative score derived from logged events at all times during a mock session.

---

## Scope Boundaries

- Actual BLE proto encoding and WiFi download implementation for real devices — stubs remain but are re-labeled. Real firmware wiring is separate work.
- Multiple different mock video files per match scenario — one `mock-video.mp4` is the single source for all mock scenarios.
- Scoreboard or overlay data embedded in or extracted from the video signal — the video is always raw footage; all overlays are app-rendered.
- Cloud sync, remote backup, or export of mock fixture state.
- Video re-encoding on device — trimming is cut-only; output format is always MP4.

---

## Key Decisions

- **`kUseMockData` is a boolean dart-define, not part of `AppEnv`.** Rationale: the two concerns are orthogonal. A developer can run `dev` environment with no mock data (real device, seed only) or `stage` environment with mock data (emulator, full fixture set). An enum would force them to be coupled.
- **Base seed always runs, unconditionally.** Rationale: the app cannot function without at least one user and sport presets. Making this a flag would create a class of launch-time crashes that are hard to diagnose.
- **Single mock video asset, not per-match files.** Rationale: simplicity and repo size. The events in the fixture set carry the semantic content; the video is just playback material. Trimming works identically regardless of which segment of the file is cut.
- **Highlight trimming is cut-only (no re-encode).** Rationale: re-encoding requires FFmpeg or a platform video API, adds significant complexity and latency, and produces a file the user may immediately re-encode anyway. Cut-only is fast, lossless, and portable. Users who need a different format convert after export.
- **Compact score section is always visible on the live preview page, not a toggle.** Rationale: the purpose is quick at-a-glance awareness. A toggle adds friction to the most common case (needing to check the score).
- **`ClipsTable` is repurposed from deferred storage to the active highlight model.** Rationale: the existing schema fields (`matchId`, `durationSeconds`, `startedAt`) map directly onto the start-offset + duration trim model with minimal schema change.

---

## Dependencies / Assumptions

- `mock-video.mp4` is already present in the repo root; it will be moved to `assets/mock/` and declared in `pubspec.yaml`.
- The platform supports MP4 cut-only trimming without FFmpeg (using `VideoTrimmer` or platform channel). This needs validation during planning.
- Drift DevTools extension compatibility with the current `drift: ^2.20.2` version needs to be confirmed during planning.
- `ClipsTable` schema extension (adding `startSeconds` field) requires a DB migration.

---

## Outstanding Questions

### Resolve Before Planning

- None — all product decisions are captured above.

### Deferred to Planning

- [Affects R20][Needs research] Which Flutter package or platform channel handles MP4 cut-only trimming without re-encoding? `video_trimmer`, `ffmpeg_kit_flutter`, or a native `MediaMuxer`/`AVAssetExportSession` call? Each has different dependency weight.
- [Affects R12][Needs research] Confirm that `drift_dev`'s DevTools extension works with the current `drift: ^2.20.2` and Flutter SDK version in the devcontainer. The extension API changed in drift 2.x.
- [Affects R19] Exact schema delta for `ClipsTable` (add `startSeconds: int`, rename or reuse `startedAt`). Minor migration required; determine during planning.
- [Affects R11] Exact gesture and route for accessing the debug screen. Long-pressing the version label in Settings is the current assumption; validate against the existing Settings page layout.
