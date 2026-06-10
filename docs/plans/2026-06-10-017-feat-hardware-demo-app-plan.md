---
title: "feat: Hardware-demo app — real-device wiring + raw dual-camera capture"
type: feat
status: completed
date: 2026-06-10
origin: docs/brainstorms/2026-06-10-hardware-demo-app-requirements.md
---

# feat: Hardware-demo app — real-device wiring + raw dual-camera capture

## Summary

Take the app's capture & transfer / preview / overlay / streaming flows — all built and tested against the in-app mock — and make `main_prod.dart` work against real firmware over real BLE + WiFi Direct, by filling the two real-impl stubs (`WifiServiceImpl.previewDescriptor` → real RTSP, `_runDownload` → real HTTP range+token), hardening the prod Android build, and adding a new raw dual-camera record feature (app-owned Drift metadata + control surface) that captures YOLO training footage.

---

## Problem Frame

The app's full feature surface has only ever run against the in-app mock (`lib/mock/emulator/`); the contract-first design means most wiring should hold, but the prod paths were never exercised on hardware (see origin: `docs/brainstorms/2026-06-10-hardware-demo-app-requirements.md`). Research found the real wiring is closer to done than the brainstorm assumed in some places and stubbed in others:

- `LivePreviewView` already plays RTSP via VLC in every environment; the only gap is `WifiServiceImpl.previewDescriptor` returning `null` (`lib/core/wifi/wifi_service_impl.dart:224`).
- The real HTTP download is a **fake 1-byte tick loop** (`_runDownload`); the real dio range+Bearer client only exists in `lib/mock/mock_video_fetcher.dart`.
- BLE pairing, MTU(512), chunk/ack, and the `protocol_version` handshake are coded but merged **without integration tests** — hardware bring-up is their first real exercise.
- A latent Android-16 ffmpeg-kit `UnsatisfiedLinkError` can silently abort plugin registration (killing FlutterBluePlus + sqlite3) — looks like "BLE broken," isn't.

Raw dual-camera capture is net-new and is the bridge to the intelligence phase (training data).

---

## Requirements

- R1. `main_prod.dart` pairs + controls real firmware over BLE (real MTU/chunk/ack, version handshake) and polls telemetry. (origin R1, R2)
- R2. WiFi Direct brings up against real firmware and `LivePreviewView` renders the real RTSP stream. (origin R3)
- R3. Recording control + real HTTP range download + playback work against real firmware. (origin R4, R5)
- R4. A raw dual-camera record control records both feeds; both files download with identity metadata, stored as app-owned data. (origin R6, R7)
- R5. Overlay state is sent to real firmware (no new authoring); composited output matches the app preview (pixel parity). (origin R8)
- R6. A platform stream target (YouTube RTMP) is configured and the live broadcast starts/stops against real firmware. (origin R9)
- R7. Prod backend is exercised end-to-end on hardware; mock-backed tests stay green; real-device steps documented. (origin R10)

**Origin actors:** A1 Operator, A2 App (this), A3 Firmware, A5 Streaming platform
**Origin flows:** F1 (proof-of-life), F2 (preview), F3 (record+transfer), F4 (raw capture), F5 (overlay+broadcast)
**Origin acceptance examples:** AE1 (pair/telemetry), AE2 (preview), AE3 (record+download), AE4 (raw), AE5 (overlay+RTMP)

---

## Scope Boundaries

- No AI/auto-framing display (intelligence deferred).
- No new overlay authoring UX — reuse existing authoring.
- No iOS device validation — Android phone only (WiFi Direct is Android-only this release).
- No new emulator/in-app device-connection UI — real hardware only this session. (Mock test doubles in `lib/mock/emulator/` are still updated to keep sealed-command parity — that is not "emulator wiring.")
- No `SetStreamingConfigCommand` adoption — keep the existing `PushSessionConfig.rtmpUrl`/`streamKey` + `StreamingControlCommand` path unless a gap forces it.

### Deferred to Follow-Up Work

- Raw file *format* decision (encoded MP4 vs raw NV12) is owned by the firmware plan; the app stores whatever path/metadata firmware reports.
- Stream-key secret storage hardening (beyond the existing local Drift field) — note in U9, full treatment deferred.

---

## Context & Research

### Relevant Code and Patterns

- **Backend switch:** real impls are the provider defaults (`bleServiceProvider` `lib/core/ble/ble_providers.dart:16`, `wifiServiceProvider` `lib/core/wifi/wifi_providers.dart:14`); `main.dart` overrides them with mocks, `main_prod.dart` uses a bare container → real impls. Not a runtime `isDevBackend` branch.
- **BLE:** `BleService` (`lib/core/ble/ble_service.dart`), `BleServiceImpl` (`lib/core/ble/ble_service_impl.dart` — `connect()` already does `requestMtu(512)`, UUID/name filter, `GetDeviceInfo` handshake, `BleProtocolVersionException` on skew), `BleProtocol._toProtoCommand` (`lib/core/ble/ble_protocol.dart:222`, sealed-command switch — the new-command edit site), `ChunkReassembler`, `ChunkAck` (`total_chunks==0` sentinel). `kAppProtocolVersion=1` (`lib/core/models/command.dart`).
- **WiFi:** `WifiServiceImpl` (`lib/core/wifi/wifi_service_impl.dart`) — `connectGroup` real; `previewDescriptor` returns null (224); `previewFrames/Stats` empty (227-230); `_runDownload` fake (288). `WifiP2pChannel` (`lib/core/wifi/wifi_p2p_channel.dart`) + Kotlin `WifiDirectChannel.kt`. `WifiHandoffController` auto-connects on BLE connect.
- **Live preview:** `LivePreviewView` (`lib/core/widgets/live_preview_view.dart`) builds `VlcPlayerController.network(descriptor.url, rtpOverRtsp)` — env-agnostic; needs only a non-null real descriptor.
- **Recording/streaming control:** `lib/features/match/session/session_screen.dart` `_sendIfConnected` → `RecordingControlCommand` / `StreamingControlCommand`; `session_state.dart` `RecState`. `main_page.dart` (`lib/features/camera/main_page.dart`) has no record button — home for the raw-record control.
- **Download/playback:** `lib/features/video/playback/download_sheet.dart` → `wifiServiceProvider.downloadRecording`; real range+Bearer pattern to lift from `lib/mock/mock_video_fetcher.dart:32`; `DownloadToken` (`lib/core/models/recording.dart:19`); `GalleryService`, `VideoPathService`.
- **Streaming target:** `lib/features/settings/streaming/` + `lib/core/models/streaming.dart` (`RtmpConfig{url,streamKey}`); reaches firmware via `PushSessionConfig` (`setup_screen.dart:323`) + `StreamingControlCommand`.
- **Overlay:** push at `lib/features/match/setup_screen.dart:372` (`pushOverlayLayout`); live `ScoreUpdate`/`BannerEvent` in `session_screen.dart`.
- **DB:** Drift tables `lib/core/db/tables/`; no `recordings` table (a recording = `team_matches` row + on-disk file). New `raw_recordings` table + DAO + `app_database.dart` registration + `just gen-db`.
- **View models vs generated:** `lib/core/models/` (plain Dart) vs `lib/models/proto/` (gitignored, `just gen-proto`); only `*_impl` + `BleProtocol` + mocks touch generated.

### Institutional Learnings

- `docs/solutions/integration-issues/app-firmware-contract-alignment-ble-wiring-2026-06-09.md` — chunking is ack-gated + index-ordered; `connect()` refuses on `protocol_version` skew (`BleProtocolVersionException`); proto3 `optional` — never encode `null` as `""` for `rtmpUrl`/`streamKey`; `PushSessionConfig` deliberately stays out of the `BleCommand` sealed hierarchy (don't "tidy" it in). Merged **without integration tests** → verify `kAppProtocolVersion` vs device first; expect real-MTU-below-dev to break chunk sizing.
- `docs/solutions/logic-errors/wifi-direct-dart-service-lifecycle-correctness-2026-06-09.md` — `disconnectGroup` MUST send `StopWifiDirectCommand` or the *second* `connectGroup` fails until firmware's P2P timeout; every `invokeMethod` needs `.timeout(15s)`; `Map.remove(key)` must chain `.cancel()`; in-flight dedup (Completer guard).
- `docs/solutions/integration-issues/wifi-direct-native-platform-channel-correctness-2026-06-09.md` — app is always P2P **client**, camera is GO (emit `STATE_FAILED` if app becomes GO); credential join needs Android API 29+; balanced `registerReceiver`/`unregister`.
- `docs/solutions/integration-issues/ffmpegkit-android16-plugin-registration-abort-2026-05-27.md` — **critical:** `ffmpeg_kit_flutter_new_full 2.0.0` throws `UnsatisfiedLinkError` (a `java.lang.Error`) on Android 16/API 36, aborting registration of FlutterBluePlus, sqlite3, etc. Fix: Gradle task rewriting `GeneratedPluginRegistrant.java` to `catch (Throwable)` + pin `path_provider_android: 2.2.22`. Confirm intact before the prod build.
- `docs/solutions/runtime-errors/vlc-controller-dispose-lateerror-2026-05-27.md` — `VlcPlayerController.dispose()` is async and throws `LateError` if the native view never attached; route disposal through one `.catchError` helper (bites on rapid enable→disable of real preview).
- `docs/solutions/architecture-patterns/app-source-of-truth-drift-sqlite-2026-05-06.md` — app owns all persistent data; camera owns only in-memory session + on-disk files. Raw metadata is **app** data → Drift, referencing on-device paths (mirror clips/thumbnails). `PRAGMA foreign_keys = ON` in `beforeOpen`; watch joined tables; `onError` on listeners.
- `docs/solutions/conventions/isdevbackend-must-not-bypass-connection-state-guards-2026-05-19.md` — `isDevBackend` may only select impls/dev diagnostics; audit prod paths for lingering `isDevBackend ||` bypasses + hardcoded device IDs.
- Overlay parity: `docs/solutions/ui-bugs/overlay-renderer-opacity-missing-banner-timer-orphan-2026-06-09.md` + `docs/brainstorms/2026-06-08-overlay-pixel-parity-app-requirements.md` — opacity on every shape; uniform `min(sx,sy)` scale; Inter Regular+Bold bundled both sides; `{{param}}` substitution.

---

## Key Technical Decisions

- **Fill the two `WifiServiceImpl` stubs, don't redesign:** `previewDescriptor` returns a real `PreviewStreamDescriptor` from the `WifiDirectGroup` (`groupOwnerIp`+`previewPort`); `_runDownload` becomes a real dio range+Bearer client lifting `mock_video_fetcher`'s pattern. `LivePreviewView` and `download_sheet` need no changes.
- **Raw record control lives on `main_page.dart`, framed as training capture:** the camera surface has no record button today; raw capture is first-class (user's stated driver), reconciled against `DeviceTelemetry.is_raw_capturing` for honest state.
- **Raw metadata = new app-owned `raw_recordings` Drift table** keyed by `captureGroupId`+`cameraIndex`, not an overload of `team_matches` (which assumes one file per id). Honors the source-of-truth boundary.
- **New `RawCaptureControlCommand` rides the sealed `BleCommand` switch:** the compiler forces the encode/decode edits across `ble_protocol` + `mock_ble_service`, keeping mock and real in lockstep.
- **Keep streaming target on the `PushSessionConfig` path:** proven wiring; honor proto3 `optional` (never `null`→`""`).

---

## Open Questions

### Resolved During Planning

- Real RTSP rendering: `LivePreviewView` is already capable; only `previewDescriptor` needs implementing.
- Raw metadata storage: dedicated `raw_recordings` Drift table.
- New command propagation: sealed switch enforces mock+real edits.

### Deferred to Implementation

- Negotiated MTU below dev assumptions breaking chunk sizing — only observable on real BLE; deferred to bring-up.
- Whether `previewFrames`/`previewStats` need a real heartbeat for the LIVE badge or a synthetic local tick suffices — decide when validating the badge on-device.
- Stream-key secret storage hardening — current local Drift field used as-is for the demo.

---

## Implementation Units

### Phase 0 — Prod-build sanity + pairing (M0)

- U1. **Harden the prod Android build and audit prod-only paths**

**Goal:** The prod build runs on the demo phone and real BLE pairing/telemetry works.

**Requirements:** R1, R7

**Dependencies:** None

**Files:**
- Verify: `android/app/build.gradle.kts` — confirm the ffmpeg-kit Gradle task **re-applies** the `catch(Throwable)` patch on every build (`GeneratedPluginRegistrant.java` is generated and a `flutter clean` reverts it — checking the current file is not enough); `pubspec.yaml` (`path_provider_android: 2.2.22` pin)
- Audit: prod paths for `isDevBackend ||` **and `kDebugMode ||`** bypasses + hardcoded device IDs (`lib/core/`, `lib/features/`); ensure the demo APK is a **release build** (a debug-profile build leaks sensitive BLE payloads to logcat)
- Fix: `CLAUDE.md` — its "mocks selected at runtime via `isDevBackend`, no Riverpod override" line is **stale**; selection is provider-default + dev-entry override. Correct it so the audit targets the real mechanism.
- Verify: `lib/core/models/command.dart` `kAppProtocolVersion` vs the device's `protocol_version`
- **Add (day-0, no hardware needed): a host-side `ChunkReassembler`/`ChunkAck` integration test** parameterized over realistic negotiated MTUs (e.g. 23, 185, 247) — converts the highest-risk on-device debug (chunk sizing at real MTU) into a closed-box CI failure. Also run the prod dio/RTSP clients against the devcontainer `mock-camera-wifi` service to exercise real client code before hardware day.

**Approach:**
- Confirm the Android-16 ffmpeg-kit fix is intact (else FlutterBluePlus/sqlite3 silently fail to register). Check `adb logcat | grep GeneratedPluginRegistrant` if plugins look dead.
- Remove/guard any dev-only shortcut that would mask a prod null-safety/disabled-UI bug.

**Execution note:** The chunk/MTU host test is writable now and is a **blocking pre-req** for trusting U1 on hardware — not a "budget debug time" afterthought. The rest is confirm-on-hardware.

**Test scenarios:**
- Happy path (on-device): release prod build pairs `sst-cam-NNNN`, shows device info + 1 Hz telemetry. Covers AE1.
- Edge case (host): `ChunkReassembler` round-trips a multi-chunk command at MTU 23/185/247 with correct ack-gating and ordering.
- Error path: `protocol_version` skew surfaces `BleProtocolVersionException` with a clear message, not a generic failure.

**Verification:** Release prod build on the phone pairs and polls telemetry; chunk/MTU host test green in CI; no silent plugin-registration failure.

---

### Phase 1 — Real RTSP preview (M1)

- U2. **Implement `WifiServiceImpl.previewDescriptor` + safe VLC disposal**

**Goal:** `LivePreviewView` renders the real cam-0 RTSP stream.

**Requirements:** R2

**Dependencies:** U1

**Files:**
- Modify: `lib/core/wifi/wifi_service_impl.dart` (`previewDescriptor`; optionally a heartbeat on `previewFrames`/`previewStats`)
- Verify/Modify: `lib/core/widgets/live_preview_view.dart` (route disposal through one `.catchError` helper)
- Test: `test/wifi/wifi_service_impl_test.dart`, `test/core/widgets/live_preview_view_test.dart`

**Approach:**
- Return `PreviewStreamDescriptor(url: 'rtsp://${group.groupOwnerIp}:${group.previewPort}/preview', codec: rtspH264)` from the stored `WifiDirectGroup`. **Confirm the real firmware's actual RTSP URL/port/mount/transport on-device first** — the `/preview` path and `rtpOverRtsp` transport are assumed from the mock; if they differ this becomes descriptor-discovery, not a one-liner.
- **LIVE-badge decision (resolved, not deferred):** emit a local-tick heartbeat into `previewFrames` while the descriptor URL is non-null, matching the mock pattern, so the badge reflects "stream configured" — or explicitly suppress the badge in prod. Pick the heartbeat; add a test.
- **Preview states to define:** (a) no group → "Not connected" placeholder; (b) group up, awaiting first frame → spinner + "Connecting to preview…"; (c) RTSP error mid-stream → "Preview unavailable" + manual retry tap. Guard `VlcPlayerController.dispose()` against `LateError` on rapid enable→disable (route through one `.catchError` helper).

**Patterns to follow:** `MockWifiService.previewDescriptor` (`lib/mock/emulator/mock_wifi_service.dart:152`); VLC dispose learning.

**Test scenarios:**
- Happy path: given a connected group, `previewDescriptor` yields the correct rtsp URL from group IP+port. Covers AE2.
- Edge case: disconnected/no-group → `null`; view shows "Not connected" placeholder, no crash.
- Edge case: awaiting-first-frame shows the connecting state; mid-stream RTSP error shows the retry affordance.
- Edge case: rapid enable→disable disposes the controller without `LateError`.

**Verification:** On-device, live cam-0 video renders in the preview view after pairing + WiFi Direct.

---

- U3. **WiFi Direct disconnect + lifecycle correctness**

**Goal:** Reconnect works repeatedly against real firmware.

**Requirements:** R2

**Dependencies:** U1

**Files:**
- Verify/Modify: `lib/core/wifi/wifi_service_impl.dart` (`disconnectGroup` sends `StopWifiDirectCommand`; `.timeout(15s)` on `invokeMethod`; `.cancel()` on subscription removal; in-flight dedup), `lib/core/wifi/wifi_p2p_channel.dart`
- Test: `test/wifi/wifi_service_impl_test.dart`

**Approach:**
- Ensure every firmware resource is released over BLE on disconnect (lifecycle learning); guard platform-channel hangs; dedup rapid retries.

**Test scenarios:**
- Happy path: connect → disconnect sends `StopWifiDirectCommand`; a second connect succeeds (no stale-group failure).
- Error path: a hung `invokeMethod` times out at 15s with a clear error, not an isolate hang.

**Verification:** On-device, connect/disconnect/reconnect cycles succeed repeatedly.

---

### Phase 2 — Record + download (M2)

- U4. **Real HTTP range + token download**

**Goal:** A finished recording downloads over real WiFi Direct and plays back.

**Requirements:** R3

**Dependencies:** U1, U3

> **Net-new streaming client, not a "lift."** `mock_video_fetcher` does a single buffered `dio.get(ResponseType.bytes)` with **no Range header** — fine for a tiny mock asset, fatal for a multi-GB recording. Only the `Authorization: Bearer` header transfers; the streaming/progress/cancel logic is new.

**Files:**
- Modify: `lib/core/wifi/wifi_service_impl.dart` — replace `_runDownload` (a fake 1-byte tick loop) with a **streamed-to-disk** dio client (`ResponseType.stream`, byte-count progress, cancellation wired to the existing `VideoDownloadHandle.cancel`) using `DownloadToken.httpUrl`/`authToken`. Firmware supports `Range`/`206` (`http-download-server.cpp`), so state explicitly whether resume is in scope or deferred.
- Verify: `lib/features/match/session/session_screen.dart` (recording control already wired), `lib/features/video/playback/download_sheet.dart`, `GalleryService`, `VideoPathService`
- Test: `test/wifi/wifi_service_impl_test.dart`, `test/features/video/playback/download_sheet_test.dart`

**Approach:**
- Stream to disk (do not buffer the whole body in memory); derive `VideoDownloadProgress` from `Content-Length`/received bytes; preserve the existing cancel contract. Take only the Bearer-header pattern from `mock_video_fetcher`. **Never log `authToken`** at any level.

**Patterns to follow:** existing `VideoDownloadProgress`/`VideoDownloadHandle`; dio streamed download.

**Test scenarios:**
- Happy path: requesting a recording streams the real file to disk with progress; playback works. Covers AE3.
- Error path: expired/invalid token → clear error; partial/interrupted download resumes or restarts cleanly; cancel mid-download stops and cleans up.

**Verification:** On-device, record→stop→download→play round-trips a real clip.

---

### Phase 3 — Raw dual-camera capture (M3)

- U5. **Wire `RawCaptureControlCommand` + new metadata/telemetry fields through the contract**

**Goal:** The app can send raw start/stop and decode raw/identity + raw-capturing state.

**Requirements:** R4

**Dependencies:** U1, proto raw-capture amendment landed (`just gen-proto`)

**Files:**
- Modify: `lib/core/models/command.dart` (`RawCaptureControlCommand` + action enum), `lib/core/ble/ble_protocol.dart` (`_toProtoCommand` case; decode new `RecordingMetadata`/telemetry fields), `lib/mock/emulator/mock_ble_service.dart` (`_encodeCommand`/`_buildResponse`/`_mapResponse` + a raw-capturing side-effect flag), `lib/core/models/telemetry.dart` (`isRawCapturing`), `lib/core/models/recording.dart` (`isRaw`/`cameraIndex`/`captureGroupId`)
- Test: `test/ble/ble_service_impl_proto_test.dart`, `test/mock/mock_ble_service_test.dart`

**Approach:**
- `RawCaptureControlCommand` carries the **app-minted `captureGroupId`** (the app generates it on start and sends it — the proto stop response is status-only, so this is the only way the app reliably pairs the two files). Add it to the sealed hierarchy.
- Adding the sealed case is **compiler-forced at four exhaustive `switch` sites**: `ble_protocol.dart` `_toProtoCommand`, and `mock_ble_service.dart` `_encodeCommand` / `_buildResponse` / `_mapResponse` (not "two sites").
- The **new field decoders are NOT compiler-enforced** — `_dartTelemetry` (`ble_protocol.dart:424`) and the `RecordingMetadata` decode (`ble_protocol.dart:367` **and** its duplicate in `mock_ble_service.dart:888`) are hand-written field copies; a forgotten field compiles clean and silently drops data (the cross-stack drift class). Make the new `RecordingMetadata` fields **nullable/defaulted** (`isRaw=false`, others nullable) — three construction sites including `_fallbackRecordings` and the fixtures loader.

**Patterns to follow:** existing `RecordingControlCommand` mapping (`command.dart:173`, `ble_protocol.dart:255`, `mock_ble_service.dart:664`).

**Test scenarios:**
- Happy path: `RawCaptureControlCommand(start, captureGroupId)` round-trips real + mock; response status mapped; `captureGroupId` preserved.
- Edge case: telemetry with `is_raw_capturing` absent decodes to false; raw `RecordingMetadata` decodes `isRaw`/`cameraIndex`/`captureGroupId` in **both** decoders; final-recording metadata leaves them null/false. Add an explicit round-trip assertion for each new field in both decoders (not compiler-guarded).

**Verification:** Mock + real proto round-trip tests green.

---

- U6. **`raw_recordings` Drift table + DAO**

**Goal:** App-owned metadata for paired raw recordings.

**Requirements:** R4

**Dependencies:** None (parallel to U5)

**Files:**
- Create: `lib/core/db/tables/raw_recordings_table.dart`, `lib/core/db/daos/raw_recordings_dao.dart`
- Modify: `lib/core/db/app_database.dart` (register table/DAO), then `just gen-db`
- Test: `test/core/db/raw_recordings_dao_test.dart`

**Approach:**
- Columns: `id`, `captureGroupId`, `cameraIndex`, `matchId` (nullable FK→`team_matches`), `localPath`, `sizeBytes`, `isRaw`, timing. Group cam0/cam1 by `captureGroupId`. Ensure `PRAGMA foreign_keys = ON` in `beforeOpen`.

**Patterns to follow:** `clips_table.dart`/`thumbnails_table.dart` + their DAOs; source-of-truth learning's Gotchas checklist.

**Test scenarios:**
- Happy path: insert two rows sharing `captureGroupId`, distinct `cameraIndex`; query returns the pair.
- Edge case: FK cascade on match delete works (pragma on); watch stream emits on related-table writes.

**Verification:** DAO tests green; `just gen-db` clean.

---

- U7. **Raw-record control UI + download both files**

**Goal:** Operator records both raw feeds and pulls both files.

**Requirements:** R4

**Dependencies:** U5, U6, U4 (download client)

**Files:**
- Modify: `lib/features/camera/main_page.dart` (raw-record control in `_HeroCameraCard` action row), `lib/features/camera/camera_state.dart` (optimistic `rawCaptureProvider`)
- Modify: `lib/features/video/*` — surface raw pairs via a **"RAW" filter chip** in the existing `wf_filter_bar` (decided, not "or a dedicated list"); show each pair as one grouped card under its `captureGroupId`; reuse `download_sheet` with a dual-file progress indicator
- Test: `test/features/camera/*`, `test/features/video/*`

**Approach:**
- The app **mints `captureGroupId`** and sends it on start; gate the button on `connected`. Use **optimistic local state** (like the existing `RecordingControlCommand`/`RecState` pattern) for the demo; decode `is_raw_capturing` but treat it as a soft confirmation, not a per-tick gate (full telemetry reconciliation deferred — `is_raw_capturing` is a session bool, not a per-camera health signal). After stop, enumerate the two files by the minted `captureGroupId`, download both via U4, persist via U6. **Download is auto-triggered on stop**; progress shows in the download sheet; a second raw capture is blocked until the pair finishes.
- **UI states to define (don't leave to the implementer):** raw-record button needs a **distinct icon + "RAW" label + color token** so it never reads as normal recording; states idle / starting / capturing (pulsing "RAW REC") / stopping / error. On disconnect mid-capture: reset button to idle + non-blocking banner "Raw capture interrupted — files may be incomplete"; mark any single recovered file in the library as incomplete.

**Patterns to follow:** `RecState` optimistic pattern (`session_state.dart`); `main_page` action row (`~163-211`); `download_sheet` progress; `wf_filter_bar`.

**Test scenarios:**
- Happy path: tap raw-record (distinct RAW affordance) → start sent with minted `captureGroupId`; stop → two files auto-download as a grouped pair. Covers AE4.
- Edge case: disconnect mid-capture → button resets to idle, interrupted banner shown, no orphaned optimistic state.
- Error path: a missing second file surfaces a clear error and marks the entry incomplete, not a silent single-file save.

**Verification:** On-device, a raw session yields two downloaded, paired files in the library.

---

### Phase 4 — Overlay parity (M4)

- U8. **Send overlay state to real firmware + verify parity**

**Goal:** Composited firmware output matches the app preview.

**Requirements:** R5

**Dependencies:** U1, U2

**Files:**
- Verify: `lib/features/match/setup_screen.dart` (`pushOverlayLayout`/`pushSessionConfig`), `lib/features/match/session/session_screen.dart` (`ScoreUpdate`/`BannerEvent`), `lib/features/match/session/overlay_renderer.dart`
- Test: existing overlay/session tests stay green

**Approach:**
- Validate authoring → push → live updates against real firmware; run the pixel-parity checklist (uniform `min(sx,sy)` scale, Inter Regular+Bold bundled both sides, opacity on every shape, `{{param}}` substitution). Mostly validation — no new authoring.

**Patterns to follow:** overlay pixel-parity requirements + renderer opacity learning.

**Test scenarios:**
- Happy path: overlay enabled → real recorded/streamed output shows banner+scoreboard matching the preview. Covers AE5 (overlay half).
- Edge case: absent `visible`/`opacity` default true/1.0 (overlay doesn't vanish).

**Verification:** On-device, preview and composited output match within tolerance.

---

### Phase 5 — Platform broadcast (M5)

- U9. **Configure + start platform RTMP broadcast**

**Goal:** Operator broadcasts cam-0 (overlaid) to YouTube.

**Requirements:** R6

**Dependencies:** U1, U8

**Files:**
- Verify/Modify: `lib/features/settings/streaming/*`, `lib/features/match/setup_screen.dart` (`PushSessionConfig.rtmpUrl`/`streamKey`), `lib/features/match/session/session_screen.dart` (`StreamingControlCommand` live toggle), `lib/core/models/streaming.dart`
- Test: `test/features/settings/streaming/*`, `test/features/match/session/session_ble_wiring_test.dart`

**Approach:**
- Send the configured YouTube `RtmpConfig` via the proven `PushSessionConfig` path (honor proto3 `optional` — never encode `null` as `""`); live start/stop via `StreamingControlCommand`. Use the existing local stream-key field; **hardening deferred but bounded for the demo**: the stream key transits BLE as cleartext and sits unencrypted in Drift — treat it as **single-use** and revoke/regenerate it after the demo (U10 runbook). The key must **never** appear in any `toString()`/log/crash payload (add a review-checklist item).

**Patterns to follow:** existing session-config streaming wiring; proto3 optional semantics learning.

**Test scenarios:**
- Happy path: configure YouTube target → start broadcast → `StreamingControlCommand(start, rtmpUrl)` sent; stop sent on end. Covers AE5 (RTMP half).
- Edge case: no streaming configured → `rtmpUrl`/`streamKey` unset (not `""`), firmware distinguishes "no streaming."

**Verification:** On-device, the platform shows the live overlaid cam-0 broadcast.

---

### Cross-cutting

- U10. **Real-device integration runbook**

**Goal:** Repeatable on-device bring-up steps (M0→M5).

**Requirements:** R7

**Dependencies:** None

**Files:**
- Create: `docs/runbooks/hardware-demo-bringup.md` (or extend `docs/`)

**Dependencies:** None for drafting — write incrementally during M0→M5. The "second person can run it" verification only applies once M0→M5 are complete.

**Approach:** Document the prod build (release, not debug), protocol-version check, pairing, WiFi Direct, preview, record/download, raw capture, overlay, and RTMP steps, plus the known footguns (ffmpeg-kit Android-16 check + `adb logcat | grep GeneratedPluginRegistrant` as the first "BLE dead" triage, real-MTU, stale-group reconnect). Include **post-demo security steps**: revoke/regenerate the YouTube stream key, remove the persistent Android WiFi Direct P2P group (prevents credential reuse), confirm no token/key logging.

**Test scenarios:** Test expectation: none — documentation only.

**Verification:** Runbook reviewed against the actual M0→M5 steps post-demo (drop the "second person" gate if team size doesn't allow it).

---

## System-Wide Impact

- **Interaction graph:** New `RawCaptureControlCommand` flows through the sealed `BleCommand` switch (forces mock+real edits); new `raw_recordings` table + DAO join into the video/library watch streams; `previewDescriptor`/`_runDownload` move from stub to real in `WifiServiceImpl` (consumed unchanged by `LivePreviewView`/`download_sheet`).
- **Error propagation:** `protocol_version` skew → `BleProtocolVersionException`; platform-channel hangs → 15s timeout; download token expiry → clear error; raw single-file → explicit error.
- **State lifecycle risks:** WiFi Direct resource release on disconnect (else reconnect fails); optimistic raw-capture UI reconciled vs telemetry; FK pragma for raw table cascade; VLC async dispose.
- **API surface parity:** `camera_index`/`capture_group_id` semantics must match firmware (identity-key drift); overlay parity per `overlay-rendering.md`.
- **Unchanged invariants:** pull model, ProviderScope override mechanism, `PushSessionConfig`-out-of-sealed-hierarchy, mock-backed test suite behavior.

---

## Risks & Dependencies

| Risk | Mitigation |
|------|------------|
| ffmpeg-kit Android-16 abort silently kills BLE/sqlite | U1 confirms the `catch(Throwable)` Gradle patch + `path_provider` pin before the prod build. |
| **Real MTU below dev assumptions breaks chunk sizing — the #1 timeline risk** (universal U1 dependency, ack-gated, untested on hardware) | **Host-side `ChunkReassembler`/MTU test (U1, no hardware needed)** converts open-ended on-device debug into CI; not "budget debug time." |
| Stale P2P group blocks second connect | U3 sends `StopWifiDirectCommand` on disconnect + dedup. |
| Mock/real divergence (paths never exercised) — green mock tests CANNOT catch this | Mock suite is a **no-regression floor on already-working flows only**. Real divergence is mitigated by running the prod dio/RTSP clients against the devcontainer `mock-camera-wifi` server (real client vs non-mock server) + the chunk/MTU test, before hardware day. |
| `_runDownload` is net-new streaming code, not a lift (multi-GB, range, progress, cancel) | U4 rewritten as streamed-to-disk; do not under-budget Phase 2 by pairing it with the trivial `previewDescriptor`. |
| **U7 raw-pair path needs the minted `captureGroupId`** (stop response is status-only) | Resolved: **app mints `captureGroupId`** and sends it on START (U5); proto adds the optional field. |
| Raw capture depends on firmware file format (undecided) | App stores whatever path/metadata firmware reports; metadata fields additive. |
| **Firmware M3 (raw handler + download-server metadata) must land before app U5-U7 integration** | Cross-repo: if firmware M3 slips past week 2, defer app U5-U7 to follow-up. Proto amendment lands first (proto → firmware → app); `just gen-proto` after the submodule bump (owned: bump `sst-cam-app/proto` to the amended commit before regen). |

---

## Documentation / Operational Notes

- U10 runbook. Post-demo, capture the four zero-coverage areas as `/ce-compound` learnings: real RTSP preview, real HTTP range download, platform RTMP wiring, and the raw dual-camera feature.

---

## Sources & References

- **Origin document:** `docs/brainstorms/2026-06-10-hardware-demo-app-requirements.md`
- System spec: `docs/brainstorms/2026-06-10-hardware-demo-system-requirements.md`
- Proto plan: `sst-cam-proto/docs/plans/2026-06-10-001-feat-raw-capture-contract-plan.md`
- Firmware plan: `sst-cam-firmware/docs/plans/2026-06-10-001-feat-hardware-demo-pipeline-firmware-plan.md`
- Learnings: `docs/solutions/integration-issues/app-firmware-contract-alignment-ble-wiring-2026-06-09.md`, `docs/solutions/logic-errors/wifi-direct-dart-service-lifecycle-correctness-2026-06-09.md`, `docs/solutions/integration-issues/ffmpegkit-android16-plugin-registration-abort-2026-05-27.md`, `docs/solutions/architecture-patterns/app-source-of-truth-drift-sqlite-2026-05-06.md`
- Stubs to fill: `lib/core/wifi/wifi_service_impl.dart` (`previewDescriptor`, `_runDownload`)
