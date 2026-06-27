# Plan — App bug sweep + multi-cam/overlay (Bug #6 app side)

**Date:** 2026-06-26
**Branch:** all work → PRs into `release/0.1.0` (still prerelease — no stable cut yet; bugs and #6 both iterate as betas here)
**Source:** handoff `docs/handoffs/2026-06-26-bug-sweep-and-local-dev-workflow.md`
**Architecture:** `docs/brainstorms/2026-06-26-multicam-overlay-architecture-requirements.md`
**Principle:** local build == CI build (no build-type divergence). Verify on device (S24); `flutter analyze` + `flutter test` (575) + `dart format` before push. CI is authoritative.

> Bug 0 (R8-off preview-crash fix) is already in-tree — finish Step 0 (rebuild dev APK, install,
> confirm no crash) and commit + PR to `release/0.1.0` before starting below.

---

## Phase A — Preview pipeline (pairs with firmware F4)

### A1 — #1 "WAITING FOR FRAMES" forever (app side)
- **Cause:** label gated on `previewFrameProvider`, but `WifiServiceImpl.previewFrames()` returns
  `const Stream.empty()` (`lib/core/wifi/wifi_service_impl.dart:307`) — never emits. `frame==null` always →
  label hard-pinned (`lib/core/widgets/live_preview_view.dart:207,216`). VLC surface renders independently.
- **Fix:** drive "playing vs waiting" off the VLC controller's real state (`PlayingState.playing` via
  `_onVlcChange`, `live_preview_view.dart:94`) instead of `frame != null` at `:207,216`. Optionally emit a
  real heartbeat from `wifi_service_impl.dart:307` so stats have a source.
- **Verify:** with firmware F4 landed, preview shows LIVE within ~2s on device.

### A2 — #1b preview image distortion
- **Cause:** `VlcPlayer(aspectRatio: 16/9)` hardcoded (`live_preview_view.dart:225`) + outer `AspectRatio`
  hardcoded (`:259`), ignoring `descriptor.width/height` already in scope (`:194`). Stretches to fill.
- **Fix:** use `descriptor.width / descriptor.height` for both the `VlcPlayer.aspectRatio` (`:225`) and the
  outer box (`:259`, via `widget.aspect`). Prefer aspect-preserving (letterbox) over fill if stream aspect
  is untrusted. **Guard `descriptor.height == 0`** (the descriptor is updated mid-session and may arrive nil)
  → fall back to `16/9` to avoid a divide-by-zero / NaN aspect.
- **Verify:** preview undistorted at the firmware-advertised resolution; nil/zero descriptor falls back cleanly.

---

## Phase B — WiFi-Direct reliability (#2, pairs with firmware F3)

### A3 — #2(a) permission ordering + group teardown on failure
- **Cause:** `StartWifiDirectCommand` sent (`wifi_service_impl.dart:164`) **before**
  `nearbyWifiDevices.request()` (`:211`); denial throws (`:213-220`) but **never** sends
  `StopWifiDirectCommand` → firmware group orphaned. Other post-start failure exits (`:174,184,197,226,236`)
  also leave the group up.
- **Fix:** request `nearbyWifiDevices` **before** the BLE StartWifiDirect (`:164`). Additionally, every
  post-start failure exit must send `StopWifiDirectCommand` (compare `disconnectGroup:265`).
- **Verify:** deny the permission → firmware group is torn down (no orphan); on-device `iw dev`.

### A4 — #2(b) stale `failed` flashes the hero card
- **Cause:** `SeededBroadcast` replays last value (`lib/core/async/seeded_broadcast.dart:45-53`); a `failed`
  left by a previously-thrown connect is replayed to the next lazy subscriber. Native
  `android/app/src/main/kotlin/com/sst/sstcam/WifiDirectChannel.kt` EventChannel delivers
  connection-changed events uncorrelated to the current connect generation.
- **Fix:** reset the controller to `idle` at the top of `_connectGroupInternal` (after `:145`, before the
  `starting` emit at `:147`); gate inbound native codes on the captured `gen` (ignore superseded generations).
- **Verify:** repeated stop/start never flashes a stale FAILED.

### A5 — #2 handoff debounce
- **Cause:** `WifiHandoffController` drives connect/disconnect purely off BLE-state transitions with no
  debounce (`lib/core/wifi/wifi_handoff.dart:47-52`), widening the race.
- **Fix:** debounce connect/disconnect transitions.

---

## Phase C — UI / UX bugs

### A6 — #9 video page "connect camera"
- **Cause (reframed):** not a stale-connection bug. Button (`lib/features/video/video_page.dart:345-354`)
  is gated on `allMatches.isEmpty` (library-empty), reads **no** connection provider — unlike
  `lib/features/camera/main_page.dart:29` which watches `activeCameraIdProvider`+`connectionStateProvider`.
- **Fix (confirm intent):** either relabel the empty-state as library-empty, **or** make it
  connection-aware via `activeCameraIdProvider` (`lib/features/camera/camera_state.dart:9`) and swap
  label/action when a camera is connected. → confirm with user which.

### A7 — #4 "Open match" no-op
- **Cause:** `onPressed` calls `DefaultTabController.maybeOf(context)?.animateTo(2)`
  (`main_page.dart:170-171`) but the shell uses `NavigationBar`+`IndexedStack` on `activeTabProvider`
  (`lib/core/shell/app_shell.dart:70-82`) — no `DefaultTabController` in tree → null → silent no-op.
- **Fix:** `ref.read(activeTabProvider.notifier).state = AppTab.match` (`camera_state.dart:20`). Landing's
  empty-state FAB already offers "Schedule a match" (`lib/features/match/landing/landing_screen.dart:82,460`),
  satisfying "create one if none exist".

### A8 — #3 "Record RAW (training)" label
- **Cause:** reflects `RawCapturePhase` (`lib/features/camera/raw_capture_state.dart`), not a mode enum
  (none exists). It is the dual-camera RAW/training (L0) path keyed by `RecordingMetadata.isRaw`
  (`lib/core/models/recording.dart:9,24-26`).
- **Fix:** copy clarification only — no model change. Align wording with the L0/L1/L2 terminology from the
  architecture doc.

### A9 — #5 record button placement
- **Cause:** standalone `_RawCaptureButton` (`main_page.dart:382-449`) is orphaned on the Main tab; match
  record lives in the session (`lib/features/match/session/session_state.dart:283-299`).
- **Fix:** add a "Record Training session" entry on the Match landing
  (`landing_screen.dart`, near `_NoUpcomingState:414`) that enters `SessionScreen` **without** an
  `UpcomingMatch` (today `lib/features/match/match_page.dart:101` requires `_selected != null`). Fold the RAW
  affordance there; remove `_RawCaptureButton` from `main_page.dart`.

### A10 — #7 developer toggles
- **Cause:** they are `Switch`es, not pills (the yellow pill is the `WfChip` "Restart to apply" banner,
  `lib/features/settings/developer/developer_settings_page.dart:131-135`). Real issues: `cameraEmulation`
  defaults `true` (`lib/core/config/dev_config.dart:14`) so reads "on"; it is consumed **only** in
  `lib/main.dart:57`, so it does nothing on a real-backend build (`main_prod.dart`). The dev page is injected
  via `devNavigationProvider` (`lib/core/config/dev_navigation.dart:13,17`), wired only by `main.dart`.
- **Fix:** verify the prod/stage entry never injects `developerSettings` against the real backend; stop
  binding `cameraEmulation` to a switch that has no effect outside the dev entry. Gate any retained
  diagnostics on `isDevBackend`.

### A11 — #8 in-app log viewer/exporter
- **Cause:** no central logger — only scattered `debugPrint` (`live_preview_view.dart:77`,
  `lib/core/services/gallery_service.dart:31`, mocks, `main.dart`).
- **Fix:** add a ring-buffer `lib/core/services/log_service.dart` + provider in `lib/core/state/`; route
  existing `debugPrint`s through it; add a "Logs" row in `developer_settings_page.dart` opening a viewer with
  share/export. adb stays primary.

### A12 — test seams (from code review, enables unit tests)
- Factor pure **`DrainUntilReply`** out of the BLE response listener
  (`lib/core/ble/ble_service_impl.dart:624-672`).
- Factor **`ScanLifecycleTracker`** out of `startScan` (`ble_service_impl.dart:152-161`).
- Inject a **`PermissionChecker`** into `WifiServiceImpl` (constructor `wifi_service_impl.dart:27-29`;
  replaces the static `Permission.nearbyWifiDevices.request()` at `:212`) so the deny branch is testable —
  do this alongside A3.

---

## Phase D — Bug #6 app (new minor; pairs with firmware F6 + proto)

### A6a — Remove app overlay rendering entirely — **core change**
- App stops rendering overlay on live preview **and** playback. Remove the `OverlayLayoutRenderer` Stack over
  VLC (`lib/features/match/session/session_screen.dart` ~`:959-964`,
  `lib/features/match/session/overlay_renderer.dart`) and the playback helper
  `lib/features/video/overlay_helper.dart`. App displays the firmware-baked stream as-is. Retire the
  app-side half of `proto/overlay-rendering.md` equivalence handling. App keeps only `PushOverlayLayout`.

### A6b — Dual preview dropdown + portrait
- Add a single|side-by-side dropdown (`_HeroCameraCard`, `main_page.dart:101`; and the match `_LiveThumb`,
  `session_screen.dart:954`) that issues the firmware `set-preview-layout` command. Replace hardcoded 16:9
  (`live_preview_view.dart:225,259`) with descriptor-driven aspect (ties into A2), supporting 9:16/1080×1920.

### A6c — Download-overlayed background flow
- Replace any "render overlay in app" retrieval with: request firmware on-demand burn → poll job → download
  L2 → store/play. Extend `RecordingMetadata`/DAO to represent clean-L1 + overlay-timeline grouping (the
  `captureGroupId` infra already exists). Coordinate proto with firmware F6c.
- **HARD INVARIANT — no retrieval during a live session.** While a match is live (recording and/or
  streaming), the app **hides/disables** all past-video retrieval + overlayed-export affordances, and treats
  a `LIVE_SESSION_ACTIVE` rejection from firmware as the authoritative fallback (firmware is the source of
  truth — the app gate is UX, not enforcement). Gate the UI on the live-session state the app already tracks
  (`is_recording`/`is_streaming` telemetry). Re-enable retrieval only once the session ends. Never request a
  burn mid-session.
- **Verify:** start a match → retrieval/export controls disabled; attempt via any path → blocked client-side;
  if forced, firmware `LIVE_SESSION_ACTIVE` is handled gracefully (no crash, clear message). End session →
  controls re-enable.

> **No migration needed.** Reviewer flagged a pre-#6→#6 recording-format migration, but we're still
> prerelease (no stable cut). Existing beta recordings are disposable — no `recordingModel` versioning /
> backfill. Just land the clean-L1 + timeline model directly.

### A6 housekeeping
- Update `docs/firmware-spec.md` to the locked model (this repo owns it).
- Archive/delete `proto/overlay-rendering.md` — the app↔firmware perceptual-equivalence contract is retired
  (overlay is now firmware-unilateral). Firmware plan should reference this retirement too.

---

## Sequencing
1. **Step 0** (Bug 0 verify) → commit + PR.
2. Phase A (A1+A2 with firmware F4) → Phase B (A3+A4+A5 with firmware F3, +A12 permission seam) →
   Phase C (A6–A11). Ship as betas on `release/0.1.0`.
3. Phase D (#6) — also betas on `release/0.1.0`, after the proto messages land (firmware Sequencing step 2).
   Cross-ref firmware F6.
4. Write `docs/runbooks/local-dev-loop.md` (handoff TODO) once the loop stabilizes.
