---
date: 2026-05-28
topic: dev-data-camera-toggles
supersedes: docs/brainstorms/2026-05-26-developer-settings-requirements.md (data-mode portion)
---

# Developer Settings: Two-Toggle Data/Camera Model + Mock Restructure

## Summary

Replace the three-mode data selector (Full / Seed only / Empty) in Developer
Settings with **two independent toggles** that map cleanly onto the two distinct
sources of mock state in the app:

1. **Emulate camera** (default ON) — the camera as a whole: BLE advertisement,
   the live WiFi data plane, and all camera-reported state (telemetry, storage,
   temperature, the recordings list). The WiFi server address lives in this section.
2. **Seed app data** (default ON) — data that lives only on the phone:
   teams, matches, players, streaming destinations, and the on-device videos for
   past matches.

The two toggles are orthogonal — all four combinations are valid dev states.

Alongside the UI change, restructure `lib/mock/` so the directory layout mirrors
this same split: `emulator/` (camera) and `internal/` (app data), with the data-mode
logic folded into a single `mock_data_service.dart`, hand-editable JSON fixtures on
both sides, and the one canonical `mock-video.mp4` shared by app and container. The
dev mock's network addressing also becomes config-driven (two base URLs, no
hardcoded ports) so it can run locally or on a remote domain.

The goal is the highest-fidelity representation of the app's real workflows: the
dev toggles should correspond to real, separable concerns, not an opaque enum.

---

## Problem Frame

The current Developer Settings page exposes a three-state Data Mode selector
(Full / Seed only / Empty) plus a separate camera-emulation toggle. This conflates
two unrelated concerns and produces confusing behavior:

- **The modes don't mean what they appear to.** In the running code,
  `DataMode.full` and `DataMode.seed` are **identical** — both call
  `MockDataSeeder.seed()` (`lib/mock/seed/data_mode.dart:18-20`). Only `empty`
  differs (it wipes). So the "three modes" are really "seed: yes/no" with a
  redundant third option.
- **Data mode and camera presence are entangled in the user's mental model but
  not in the code.** Selecting "Empty" (no data) and then tapping "Connect camera"
  still shows a discoverable camera — because camera emulation is a *separate*
  `cameraEmulation` bool, unrelated to data mode. The three-mode label hides this,
  making the behavior feel like a bug.
- **Two genuinely independent concerns are presented as one.** Whether a mock
  camera exists (and reports telemetry/storage/temp) is independent of whether the
  phone already has app data. The UI should make this separation explicit.

This refactor makes the dev surface honest: two toggles for two real concerns, and
a `lib/mock` layout that reflects the same boundary.

---

## The Two Data Sources (conceptual model)

| Concern | Source | Governed by | Examples |
|---|---|---|---|
| **Camera-emulated state** | The mock camera (BLE + WiFi) | **Emulate camera** toggle | Device discoverable in scan; telemetry (battery, temp); storage stats; the recordings list (`recordings.json`); live preview; live downloads |
| **App-internal data** | The phone's local DB + storage | **Seed app data** toggle | Teams, matches, players, streaming destinations; on-device videos for past matches |

The camera has **no database**. When the app requests a video by UUID, the camera
looks up a file in its local storage by that UUID. The single mock video is returned
for *any* requested UUID — the UUID is just the distinguishing key written on the
device, so multiple phones/users stay distinct without the mock needing distinct
sources.

**Crossover (the one link between the two sources):** seeded app data includes
on-device videos for past matches. When **Seed app data = ON**, those videos are
fetched from the mock WiFi container (the same HTTP path the live download uses) and
written to device storage. When **Seed app data = OFF**, those videos are deleted
from device storage. This happens regardless of the camera toggle — it is part of
mocking *app* state, not camera state.

---

## The Four Combinations

| Emulate camera | Seed app data | Resulting dev state |
|:---:|:---:|---|
| ON | ON | **Full fidelity.** Discoverable mock camera with live telemetry/preview/download, plus seeded teams/matches/players/streaming and on-device past-match videos. |
| ON | OFF | **First-run with hardware.** No app data, but a mock camera is discoverable — simulates a brand-new user setting up with a camera present. No on-device videos. |
| OFF | ON | **Offline review.** All app data + on-device videos present, but no camera to discover or connect — review/manage existing content with no hardware around. |
| OFF | OFF | **Cold start.** Completely empty app, no camera. True first-launch / no-hardware state. |

---

## Requirements

**Developer Settings UI**

- R1. Replace the three-mode Data Mode selector with two independent toggle controls:
  **Emulate camera** and **Seed app data**. Both default to ON.
- R2. The **Emulate camera** section contains the toggle *and* the WiFi server
  address field — they belong together as "camera infrastructure." The toggle
  governs the camera as a whole (BLE advertisement + live WiFi data plane), not
  just BLE.
- R3. The **Seed app data** section contains its toggle and a short description
  clarifying it controls phone-local data (teams, matches, players, streaming) and
  on-device past-match videos.
- R4. Each toggle persists independently to device storage on change. The running
  app is unaffected until restart (consistent with existing "restart to apply"
  behavior). The active-vs-staged indicator continues to work per toggle.

**Behavior on startup (`main()`)**

- R5. `main()` reads the two flags from `DevConfig` and applies them independently:
  - **Seed app data = ON** → seed teams/matches/players/streaming into the DB and
    ensure on-device videos exist for past matches with `sizeMb > 0`.
  - **Seed app data = OFF** → wipe app data back to base scaffolding (default user +
    sport presets) **and** delete on-device past-match videos from storage.
  - **Emulate camera = ON** → MockBleService advertises a discoverable device and
    the live mock WiFi data plane is active; camera-reported state (telemetry,
    storage, temp, recordings list) is available.
  - **Emulate camera = OFF** → no mock device advertises; the app behaves as if no
    camera is nearby. No camera-reported state.
- R6. The camera-reported state (telemetry, storage, temperature, recordings list)
  depends **only** on the Emulate camera toggle — never on the seed toggle.

**Video fidelity (the crossover)**

- R7. When seeding app data, on-device past-match videos must be obtained by
  requesting the mock WiFi container over the same HTTP download path the live app
  uses (`http://<serverAddress>:8080/recordings/<uuid>`), rather than copying the
  bundled asset directly into place. This routes seeded videos through the real
  download mechanics for higher fidelity.
- R8. The existing graceful fallback must be preserved: if the container is
  unreachable (e.g. unit-test environment or container down), fall back to the
  bundled `mock-video.mp4`, then to a sentinel — so seeding never hard-fails.
  (Mirror the existing `_downloadOrFallback` behavior in `mock_wifi_service.dart`.)
- R9. The WiFi server address must be readable by the seed path regardless of the
  camera toggle, since seeding videos can occur with the camera toggle OFF.

**Reseed action compliance**

- R10. The in-app reseed action (`devReseedProvider`, `lib/core/config/dev_reseeder.dart`)
  must be consistent with the two-toggle model. Re-running it must reflect the
  current Seed app data state in both directions — adding app data + videos when
  on, and removing app data + videos when off — not only the additive (seed) path
  it currently supports.

**`lib/mock` restructure — data colocated with code (both sides)**

The "one service file + per-feature JSON fixtures" pattern applies to **both**
`internal/` and `emulator/`. Each side keeps one consolidated service file plus a
`fixtures/` folder of hand-editable JSON. The target layout:

```
lib/mock/
  emulator/
    mock_ble_service.dart        # logic; loads its fixtures
    mock_wifi_service.dart       # logic (generative; no static dataset)
    mock-video.mp4               # the one canonical mock video
    fixtures/
      devices.json               # discoverable cameras (was _fakeDevices)
      recordings.json            # camera's recording list
      telemetry.json             # baseline telemetry values (drift applied in code)
  internal/
    mock_data_service.dart       # load + apply(seed) + wipe (was data_mode + seeder)
    fixtures/
      teams.json
      matches.json
      players.json
      streaming_destinations.json
```

- R11. Rename `lib/mock/seed/` → `lib/mock/internal/` so the top-level layout reads
  as two parallel concerns: `emulator/` (camera) and `internal/` (app data).
- R12. Consolidate `data_mode.dart` and `mock_data_seeder.dart` into a single
  `lib/mock/internal/mock_data_service.dart` that owns loading, applying (seed),
  and wiping — mirroring how `emulator/` keeps one consolidated file per service.
- R13. Keep app data as per-feature JSON fixtures (teams/matches/players/streaming)
  under `lib/mock/internal/fixtures/`. Editing data stays a JSON edit; the
  loader/apply/wipe logic stays in the one service file.
- R14. `recordings.json` stays on the **emulator** side (`lib/mock/emulator/fixtures/`)
  — it is the camera's view of what recordings exist, loaded by
  `MockBleService.listRecordings()`. It must not move into `internal/`.
- R15. Externalize `MockBleService`'s inline `_fakeDevices` list into
  `lib/mock/emulator/fixtures/devices.json`, loaded the same way `recordings.json`
  is. Keep the existing in-code list as the unit-test fallback (matching the
  current `_fallbackRecordings` pattern), so tests without an asset bundle still work.
- R16. Externalize telemetry **baseline values** into
  `lib/mock/emulator/fixtures/telemetry.json` (storage total/used, temp, wifi
  ssid/signal, cpu/ram, internet reachable, recording/streaming flags). The mock reads
  these as the starting point and applies its existing sinusoidal drift on top, so the
  live readout still wobbles but the baseline is editable in one place. Both
  `_makeTelemetry` and `_makeProtoTelemetry` (`mock_ble_service.dart:424,659`) must
  read from this single baseline. The drift math (sine wobble + slow storage growth)
  stays in code — only the seed values move to JSON. Keep an in-code fallback baseline
  for unit tests without an asset bundle.
- R16a. `MockWifiService` gets **no** JSON fixture: its behavior (download progress
  curves, preview heartbeat, pairing) is generative, not a static dataset. Its only
  external data is the shared `mock-video.mp4` (see Asset & container consolidation).

**Asset & container consolidation**

- R17. Eliminate the `assets/ble/` directory entirely. The JSON fixtures move to the
  per-module `fixtures/` folders (R13–R15) and `mock-video.mp4` moves to
  `lib/mock/emulator/`. Update `pubspec.yaml` `assets:` to declare the new
  module-local paths and remove all `assets/ble/` entries.
- R18. `mock-video.mp4` lives at `lib/mock/emulator/mock-video.mp4` and is the single
  canonical mock video: bundled into the app (rootBundle fallback + seeded files) and
  served by the mock WiFi container — so preview, live download, and seeded files are
  all literally the same bytes.
- R19. The mock-camera-wifi container sources its video from the app's
  `lib/mock/emulator/mock-video.mp4` instead of generating its own. Drop the
  Dockerfile `video-gen` ffmpeg stage; provide the file to the container via a
  docker-compose volume mount onto `/srv/sample.mp4` (the container build context is
  `.devcontainer/mock-camera-wifi/`, so the Dockerfile cannot `COPY` a repo-root file
  — a mount is required).
- R20. The container's RTSP preview currently stream-copies (`ffmpeg -c copy`) from
  `/srv/sample.mp4`, which requires an H.264/RTSP-compatible source. Ensure the
  shared `mock-video.mp4` satisfies this — either by guaranteeing it is encoded
  H.264 baseline (like the current generated sample) or by changing the preview
  ffmpeg command to re-encode (`-c:v libx264 …`) so any valid MP4 works. See Open
  Questions.

**Service addressing — no hardcoded ports (mock/dev only)**

- R22. Replace the single `serverAddress` host field with **two base-URL fields** in
  the Emulate camera section of Developer Settings: a **preview base** and a
  **download base**, each a full `scheme://host[:port]`. Defaults preserve current
  local behavior: `rtsp://localhost:8554` and `http://localhost:8080`. On a remote VM
  these become e.g. `rtsp://mws.domain` and `https://mws.domain` (standard ports
  implied, no port in the URL).
- R23. The app must not hardcode ports or schemes for the mock data plane. All mock
  preview/download URLs derive from the two bases: preview = `<previewBase>/preview`,
  download = `<downloadBase>/recordings/<uuid>`. Update the hardcoded sites:
  `mock_wifi_service.dart:137` (preview URL) and `:440` (download URL), and the mock
  download-token `httpUrl` in `mock_ble_service.dart:564,744`. The seed→video fetch
  (R7) uses the **download base** too.
- R24. Migrate the persisted `dev_config_server_address`: if it is a bare host,
  derive `previewBase = rtsp://<host>:8554` and `downloadBase = http://<host>:8080`;
  absent/empty → the localhost defaults. Dev-only storage, one-time read-and-replace.
- R25. This addressing change is **mock/dev only**. Production `WifiServiceImpl` +
  `WifiDirectGroup` (which use the camera's `group_owner_ip` and the contract ports
  8554/8080 per `proto/README.md:19`) are **unchanged** — two protocols on two ports
  is the production-faithful design and is not collapsed. The base-URL config exists
  solely so the dev mock can live locally or on a remote domain.

---

## Acceptance Examples

- AE1. **Covers R1, R6.** With Emulate camera = ON and Seed app data = OFF, after
  restart the app has no teams/matches/videos, but a mock camera is discoverable and
  reports telemetry/storage/temp. (This is the scenario that previously felt like a
  bug under "Empty" mode — now it is explicit and correct.)
- AE2. **Covers R5, R7.** With Seed app data = ON, after restart the Video Library
  shows past-match videos whose files were fetched from the mock WiFi container at
  `/recordings/<uuid>`, playable on device.
- AE3. **Covers R5 (delete branch).** Toggling Seed app data ON→OFF and restarting
  removes seeded teams/matches and deletes the on-device past-match video files.
- AE4. **Covers R6.** With Emulate camera = ON and Seed app data = OFF, camera
  telemetry/storage still render — proving camera state is not gated by the seed flag.
- AE5. **Covers R7, R8.** With the mock WiFi container stopped, seeding still
  completes by falling back to the bundled `mock-video.mp4` — no seed failure.
- AE6. **Covers R11–R16a.** After the restructure, `lib/mock/internal/mock_data_service.dart`
  exists, `lib/mock/seed/` is gone, `recordings.json` + `devices.json` + `telemetry.json`
  are emulator fixtures, editing `telemetry.json` changes the baseline the live readout
  drifts around, `MockWifiService` has no JSON fixture, and `flutter analyze` + the
  existing data-mode/dev-settings tests pass against the new names.
- AE7. **Covers R17.** After the move, `assets/ble/` no longer exists, `pubspec.yaml`
  has no `assets/ble/` entries, and `flutter run` (dev) boots with fixtures loading
  from their new module-local paths.
- AE8. **Covers R18, R19.** With the container running, the live preview shows the
  contents of `lib/mock/emulator/mock-video.mp4` (not a generated test pattern), a
  recording download serves the same bytes, and the Dockerfile no longer contains the
  `video-gen` ffmpeg stage.
- AE9. **Covers R22, R23.** Setting the download base to `https://mws.domain` (no
  port) makes the app request `https://mws.domain/recordings/<uuid>` — no `:8080`
  appended. Leaving the defaults makes it request `http://localhost:8080/recordings/<uuid>`
  as today. No port or scheme is hardcoded anywhere in the mock data-plane code.

---

## Success Criteria

- The Developer Settings page presents two clearly-scoped toggles, and a developer
  can reach any of the four documented combinations without confusion about what
  each control affects.
- Selecting "no app data" while keeping the camera on no longer feels like a bug —
  the camera's presence is plainly governed by its own toggle.
- Seeded on-device videos are produced via the real container download path (with
  the safe fallback intact).
- `lib/mock` reads as two parallel concerns (`emulator/`, `internal/`), with one
  consolidated `mock_data_service.dart`, JSON fixtures preserved, and `recordings.json`
  on the emulator side.
- Default fresh-install behavior is unchanged from today: camera on + app data
  seeded.

---

## Scope Boundaries

- **No per-UUID distinct video content.** Only one mock video exists; the container
  returns it for any UUID by design. Not changing this.
- **No DB on the camera / no server-side ID validation.** The mock WiFi container
  already accepts any `/recordings/<id>` and serves the sample file — no server change.
- **Mock service *behavior* (telemetry drift math, download timing, edge cases) is not
  redesigned** here — only the toggle wiring, the seed→video path, the directory
  layout, and externalizing static/baseline data to JSON. The telemetry drift stays;
  only its baseline values move to `telemetry.json`.
- **Compile-time exclusion of mock code from stage/prod builds** and **dev-only nav
  gating** are already specified in the 2026-05-26 doc (R1/R2/R12 there) and remain
  in force, unchanged.
- **No in-app "restart now" button** — manual kill + reopen remains the apply
  mechanism.
- **Fixture content itself is not being expanded** — same teams/matches/players/
  streaming, just relocated.

---

## Key Decisions

- **Two orthogonal toggles over a three-state enum.** The enum conflated two
  independent concerns and contained a redundant option (`full` ≡ `seed` in code).
  Booleans map 1:1 onto the two real data sources and make all four combinations
  reachable and self-explanatory.
- **WiFi address grouped with the camera toggle.** The address is camera
  infrastructure; grouping it signals that the toggle governs the camera as a whole,
  not just BLE.
- **Config-driven base URLs, two ports kept.** The mock data plane is two protocols
  (RTSP preview + HTTP download), matching the real camera — so two ports is faithful,
  not a smell. "One port" would mean switching preview to HTTP streaming, which lowers
  fidelity. Instead the app stops hardcoding `:8554`/`:8080` and derives every URL from
  two configurable base URLs. A single domain with clean (port-less) URLs is then a
  deployment choice (standard ports / reverse proxy on the VM), and the local
  8555→8554 host-mapping mismatch disappears because the base URL is explicit.
- **Seeded videos go through the container download path.** Higher fidelity — seeded
  "already downloaded" videos exercise the same mechanics as a real download. The
  bundled-asset fallback keeps tests and container-down dev from breaking.
- **`recordings.json` stays emulator-side.** It is camera state (what the camera says
  it holds), consumed by `MockBleService.listRecordings()`, so it follows the camera
  toggle — not the seed toggle.
- **JSON fixtures retained, one service file.** Per-feature JSON keeps data trivially
  editable by hand; folding the loader + apply + wipe into one `mock_data_service.dart`
  mirrors the emulator's consolidated-per-service style.

---

## Dependencies / Assumptions

- `MockWifiService._downloadOrFallback` (`lib/mock/emulator/mock_wifi_service.dart:506`)
  already implements container-fetch-with-fallback; R7/R8 should reuse this path or
  factor a shared helper rather than duplicating it in the seeder.
- The mock WiFi container (`mock-camera-wifi`) runs independently of the in-app camera
  toggle, so it is reachable for seeding even when Emulate camera is OFF — assuming the
  Docker service is up in the devcontainer.
- `DevConfig` already persists `cameraEmulation` and `serverAddress` independently; the
  change is replacing the `dataMode` enum field with a `seedData` bool plus its migration.
- The existing tests `test/mock/data_mode_test.dart` and
  `test/features/settings/developer_settings_page_test.dart` reference the old enum and
  file names — they will need updating as part of the restructure.
- Flutter declares assets via `pubspec.yaml` paths relative to the package root, so
  fixtures and the video can be declared under `lib/mock/…`. Planning should confirm
  the dev build bundles assets placed under `lib/` correctly; if any tooling friction
  appears, fall back to a mock-scoped path under `assets/` (e.g. `assets/mock/`) — the
  firm requirement is eliminating `assets/ble/` and colocating data with its module.
- The container build context is `mock-camera-wifi` (relative to
  `.devcontainer/docker-compose.yml`); the repo root is `..`. The volume mount source
  for the video is therefore `../lib/mock/emulator/mock-video.mp4` mounted read-only at
  `/srv/sample.mp4`.
- Codec: the current bundled `mock-video.mp4`'s codec is unverified (`ffprobe` not
  installed in the devcontainer). The file is ~103 MB — far larger than the container's
  current 10s generated sample — so serving it (R18/R19) means heavier downloads and a
  longer preview loop. R20 depends on it being H.264/RTSP-`-c copy`-compatible, or on
  switching the preview ffmpeg to re-encode. Confirm during planning.
- The mock builds a `WifiDirectGroup` (`mock_wifi_service.dart:127`) and `wifi.dart`
  exposes `previewUrl()`/`downloadBaseUrl()` from `groupOwnerIp` + ports. R22/R23 change
  how the **mock** derives its URLs (from the two base URLs); the shared `WifiDirectGroup`
  model and the production `WifiServiceImpl` (`lib/core/wifi/wifi_service_impl.dart:37`)
  should not be forced to change. Planning should decide whether the mock bypasses the
  group's port-based URL builders or feeds them parsed host/port from the base URLs.

---

## Open Questions

- OQ1. Is `mock-video.mp4` already H.264 baseline (so the RTSP `-c copy` path works
  unchanged), or should the container's preview ffmpeg re-encode to be source-agnostic?
  Re-encoding is more robust (any valid MP4 works) at a small CPU cost; stream-copy is
  cheaper but constrains the file's encoding. Resolve before implementing R19/R20.

---

## Relationship to Prior Doc

This supersedes the **data-mode portion** of
`docs/brainstorms/2026-05-26-developer-settings-requirements.md`:

- That doc's R3 (three mutually exclusive modes) is **replaced** by R1 here (two
  toggles).
- That doc's R6/R7 (camera emulation = BLE advertisement only) is **broadened** by
  R2/R6 here (camera as a whole, including live WiFi + camera-reported state).
- All other requirements from the 2026-05-26 doc (dev-only nav row, restart-to-apply,
  `kUseMockData` retirement, compile-time mock exclusion) remain in force unchanged.