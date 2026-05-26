---
date: 2026-05-22
topic: video-library-overhaul
---

# Video Library Overhaul

## Summary

Replace the team-grouped video landing page with a flat, searchable match list; fix four active bugs (display names, double-"vs", mock data, overlay toggle); wire up full-game download, phone-side highlight cropping, and camera-stream playback; and formally define the camera-app video contract (UUID-based recordings, OverlayState model) with a fully functional mock so the firmware team can model the camera OS around what the app expects.

---

## Problem Frame

The video page currently presents matches grouped by team, which creates two user-visible problems: it shows phantom "team" entries (opponents that are not tracked teams), and it makes any match invisible to users who search by the opposing team's name. A user looking for every match involving Northridge U14 would miss any recording made from Eastfield FC's perspective with NR as the opponent.

Beyond the UX structure, three additional bugs undermine the page: the team short name is used for both the icon badge and the title header (should differ), match titles repeat "vs" twice, and the overlay toggle switches all overlays on or off with no way to show score without events or vice versa. The mock data is also inconsistent — only NR has match records, leaving EFC's filter chip functionally empty.

Separately, the video playback and download workflows are stubbed. Users cannot download a full match to the device, cannot create highlight clips from events, and the app has no contract for requesting footage from the camera. These gaps block both end-user utility and firmware team design work, since the camera's WiFi API shape is not yet specified.

---

## Actors

- A1. **App User** — browses the library, plays matches, downloads recordings, and creates highlight clips.
- A2. **Flutter App** — manages device storage paths, renders simplified overlay on video, drives WiFi communication with the camera.
- A3. **SST Cam** — stores raw recordings identified by UUID, serves them over WiFi Direct (mocked for this sprint; contract defined for firmware implementation).

---

## Key Flows

- F1. **Browse and filter library**
  - **Trigger:** User taps the Video tab.
  - **Actors:** A1, A2
  - **Steps:** App loads all match records across all tracked teams into a flat list. User applies sport filter and/or team filter chips, or types in the search bar. List updates in real time. Each card shows the recording team's badge + full name, the opponent, date, result/upcoming, and an on-device indicator.
  - **Outcome:** User sees matches relevant to their query; no phantom team groups appear.
  - **Covered by:** R4–R9

- F2. **Play a match already on device**
  - **Trigger:** User taps a match card that has been downloaded.
  - **Actors:** A1, A2
  - **Steps:** App checks file existence at the UUID-derived storage path; file present. Video player opens with the local file. App derives an OverlayState array from the match's event log and renders the simplified score + events overlay on top of playback.
  - **Outcome:** Match plays locally; overlay reflects score and events at the scrubber position.
  - **Covered by:** R10, R12, R14

- F3. **Play a match stored on the camera**
  - **Trigger:** User taps a match card that is not downloaded.
  - **Actors:** A1, A2, A3
  - **Steps:** App checks storage path — file absent. App auto-initiates WiFi Direct connection (mocked). On connection, streams raw video from camera via MockWifiService. App fetches current OverlayState and renders simplified overlay over the stream.
  - **Outcome:** Match streams from the camera with app-side overlay; no manual connection step required.
  - **Covered by:** R11, R13, R14

- F4. **Download full match to device**
  - **Trigger:** User taps "Download" from the match detail page.
  - **Actors:** A1, A2, A3
  - **Steps:** App requests the recording file from the camera using the match UUID (mocked). Progress is shown in UI (bytes received, kbps, estimated time). On completion, file is written to the UUID-derived storage path. On-device indicator updates; subsequent playback uses the local file.
  - **Outcome:** Match is on device; WiFi stream no longer needed for this match.
  - **Covered by:** R15, R16

- F5. **Create a highlight clip**
  - **Trigger:** User selects an event from the event list and taps "Clip."
  - **Actors:** A1, A2
  - **Steps:** App verifies the full match is downloaded. If not, user is prompted to download first. FFmpeg trims ±15 seconds around the event timestamp. Clip is saved to device storage and tracked in the DB. Clip is immediately available for local playback.
  - **Outcome:** A short clip around the selected event is saved to the device.
  - **Covered by:** R17–R19

---

## Requirements

**Bug fixes**

- R1. Team display: the team badge/icon uses the short name (e.g., "NR"); the match title and team header use the full name (e.g., "Northridge U14").
- R2. Match title format is "FullTeamName vs OpponentName" — the opponent field in the DB already includes "vs", so the UI must not prepend an additional "vs".
- R3. Overlay toggle on the match detail page provides independent controls for Score overlay and Events overlay — toggling one does not affect the other.

**Mock data**

- R4. Both NR (Northridge U14) and EFC (Eastfield FC) have match records in the DB with complete event logs; each team's library is populated with 2–4 past matches.
- R5. Mock data explicitly covers both storage states: at least one match per team is seeded as "on device" (mock video file present at the recording path), and at least one is "on camera only" (no local file, triggers the WiFi stream path).

**Video library — flat match list**

- R6. The video landing page shows a flat, time-ordered list of all past match records across all tracked teams; the team-grouped card navigation is removed.
- R7. Filter chips: Sport (resets to All) and Team (resets to All); the Team chip set is drawn from tracked team records only — opponent strings do not create filter entries.
- R8. The search bar matches against both the primary team's name/short name and the opponent string — searching "NR" surfaces any match where NR appears on either side.
- R9. Each match record is shown once as its own entry; NR's "NR vs EFC" and EFC's "EFC vs NR" are distinct rows that both appear in the unfiltered list.

**Video playback**

- R10. On-device detection: the app checks whether the recording file exists at the path derived from the match's UUID; this check drives the on-device indicator and the playback source selection.
- R11. When not on device, the app auto-initiates the WiFi Direct connection (via MockWifiService) and streams raw video from the camera; the user takes no explicit connection step.
- R12. The mock video asset (`assets/ble/mock-video.mp4`) is used as the video source for all playback instances — local file stand-in and WiFi stream stand-in alike.
- R13. The app always renders a simplified overlay (score + events) on the video surface, derived from the match's event log; this applies to both local and streamed playback.

**Download**

- R14. From the match detail page, the user can trigger a full-game download; the download uses MockWifiService with the match UUID, shows live progress (bytes received, speed, ETA), and can be cancelled.
- R15. On completion, the recording file is saved to the UUID-derived device storage path; the on-device check (R10) then passes and subsequent opens use the local file.

**Highlight clips**

- R16. Creating a highlight clip requires the full match to be downloaded locally; if not downloaded, the app prompts the user to download first.
- R17. Clip creation: FFmpeg trims the local recording file ±15 seconds around the selected event's `timeSeconds`; the clip is saved to device storage and a DB record is created with the event reference and duration.
- R18. From the match detail page the user can select any event from the event list and trigger clip creation for it; multiple clips from the same match are supported.

**Camera-app video contract (mocked; defined for firmware)**

- R19. Camera recordings are identified by the match record's UUID; the app refers to and requests recordings only by this UUID — no filename convention beyond the ID.
- R20. `WifiService` interface is extended with: `checkCameraHasRecording(uuid)` → `bool`; `downloadRecording(deviceId, uuid)` → progress stream + completion with file path.
- R21. `OverlayState` is a named contract type: `{ timeSeconds, homeScore, awayScore, period, recentEventLabel? }`. It is the unit used everywhere overlay data is communicated between app and camera.
- R22. Live stream: `WifiService` provides a stream of the current `OverlayState` at ~1 Hz alongside the raw video stream; the app renders this as the live overlay.
- R23. Recorded playback: the app derives an ordered `List<OverlayState>` from the match's DB event log and uses it to drive the scrubber-synchronized overlay display (no camera round-trip needed).
- R24. Download-with-overlays contract: `WifiService` exposes `downloadRecordingWithOverlays(deviceId, uuid, overlays: List<OverlayState>, config: OverlayConfig)` → progress stream + file; MockWifiService returns the raw mock video for this call; the interface is defined for firmware to implement later.

---

## Acceptance Examples

- AE1. **Covers R1.** Given a match card for Northridge U14, the badge shows "NR" and the title row reads "Northridge U14 vs Eastfield FC".

- AE2. **Covers R2.** Given the `opponent` field in DB is `"vs Eastfield FC"`, the rendered title is "Northridge U14 vs Eastfield FC" — not "Northridge U14 vs vs Eastfield FC".

- AE3. **Covers R3.** Given Score is ON and Events is ON, turning off Events hides the event ticker but leaves the scoreboard visible. Turning Score back off hides the scoreboard while Events remains hidden.

- AE4. **Covers R8, R9.** Given NR has a recorded match "NR vs EFC" and EFC has a recorded match "EFC vs NR", searching "NR" returns both rows. Filtering by Team → NR also returns both rows.

- AE5. **Covers R10, R11.** Given match-001 has no local file, tapping its card initiates WiFi connection (mock), begins streaming the mock video, and shows the app-side overlay. No dialog or manual connection step appears.

- AE6. **Covers R10, R15.** Given a download of match-001 completes, tapping the card now plays the local file (mock video at the recording path) rather than initiating a WiFi stream.

- AE7. **Covers R16.** Given match-002 is not downloaded, tapping "Clip" on an event prompts "Download the full match first to create clips" rather than starting clip creation.

- AE8. **Covers R17.** Given match-001 is downloaded and has a Goal event at 37:22, clipping that event produces a file trimmed from 37:07 to 37:52 saved to clip storage.

---

## Success Criteria

- A user can find any match involving a given team by typing that team's name in the search bar, regardless of which team was holding the camera.
- Both tracked teams have populated libraries; switching the Team filter between NR and EFC returns distinct, non-empty result sets.
- A user can download a full match and play it back entirely from device storage.
- A user can crop a highlight clip from any event in a downloaded match and find it in clip storage.
- The MockWifiService satisfies all `WifiService` interface additions; a firmware engineer reading the interface and mock can implement the camera-side counterpart without needing to read app internals.

---

## Scope Boundaries

- No physical camera is connected during this sprint, so all `WifiService` calls go through `MockWifiService` which returns fake data. The `WifiService` interface itself is production-grade — when a real camera is available, swapping in `WifiServiceImpl` is the only change needed. The same principle applies to every service in the app: interfaces are real and complete; mock implementations supply fake data in dev mode (`kAppEnv.isDevBackend`).
- Camera-side overlay rendering (burning OverlayState onto the video file on the camera) is not implemented; the contract is defined and mocked only.
- Camera-side clip/seek endpoint (camera trims a time range on request) is explicitly excluded; phone-side cropping after full download is the only clip creation path.
- Half-game download (1st half / 2nd half) is not in scope; only full-game download is implemented.
- Social sharing, cloud sync, and export to external apps are not included.
- iOS build support is not in scope (Linux devcontainer only).
- Player-level filtering, tagging, or playlist features are deferred.

---

## Key Decisions

- **Service interfaces are always production-grade; mocks supply fake data**: Every service in the app (`BleService`, `WifiService`, and any future service) follows the same pattern — the abstract interface defines the real contract, a `Mock*` implementation satisfies it with fake data when no device is connected (`kAppEnv.isDevBackend`), and the real `*Impl` is swapped in for hardware. "Mocked" means the data source is fake, never that the interface is incomplete or placeholder. This ensures firmware integration requires zero app-side interface changes.

- **Flat list over team-grouped navigation**: Removing team cards eliminates phantom team entries and makes cross-team search coherent. The filter chips provide the same team-scoping capability without creating a separate navigation level.
- **Search matches any involvement**: Searching by team name surfaces matches from both perspectives (recording team and opponent) because a user's interest in a team's footage is not limited to the team that held the camera.
- **Phone-side clip cropping**: The app downloads the full raw match and uses FFmpeg locally rather than asking the camera to serve a clip range. This keeps the camera contract simple (single file per UUID) and lets clips work offline after download.
- **OverlayState as the shared contract unit**: Using one named type for live-stream overlay push and for recorded-playback overlay derivation ensures the firmware team targets a single, stable interface regardless of whether the footage is live or stored.
- **Mock video asset as universal stand-in**: All video surfaces (local playback, WiFi stream, clip preview) use the same `assets/ble/mock-video.mp4`; this ensures the full UI path is exercisable without per-match video files.

---

## Dependencies / Assumptions

- `ffmpeg_kit_flutter` (or equivalent) is available or can be added as a dependency for phone-side clip trimming.
- The `VideoPathService.recordingPath(uuid)` convention is the canonical storage location; download and on-device detection both use this path.
- `MockWifiService` is extended to implement new `WifiService` interface methods; it remains the only `WifiService` implementation for this sprint.
- The mock video asset (`assets/ble/mock-video.mp4`) is large enough to support a 30-second FFmpeg trim without errors; if not, a minimal test video should be added.

---

## Outstanding Questions

### Resolve Before Planning

*(None — all scope-shaping questions resolved in brainstorm.)*

### Deferred to Planning

- [Affects R14, R20][Technical] Determine whether `MockWifiService.downloadRecording` simulates file I/O by copying the mock video to the recording path, or by writing a placeholder; affects how R10's file-existence check behaves in dev mode.
- [Affects R17][Needs research] Confirm `ffmpeg_kit_flutter` package availability and API shape for the trim command; verify it runs on Android in the devcontainer emulator.
- [Affects R21–R24][Technical] Decide the Dart file location and import path for the `OverlayState` and `OverlayConfig` types — likely `lib/core/models/overlay.dart` but confirm no naming collision.
