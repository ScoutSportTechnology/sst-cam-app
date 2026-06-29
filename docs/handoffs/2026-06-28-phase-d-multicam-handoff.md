# Handoff — Phase D #6 (multicam / overlay) + device-fix sweep

**Date:** 2026-06-28
**Branch (all work):** `feat/phase-d-overlay-multicam` — exists in **both** `sst-cam-app` and `sst-cam-firmware`, cut from `release/0.1.0`.
**Proto:** unchanged this phase — pinned to `v0.1.0-beta.2` (`proto` submodule @ `8837968`). No proto edits needed.
**Workflow rule (the user's, non-negotiable):** finish + validate LOCALLY (incl. on real hardware) → THEN open a PR and wait for CI → then test the CI build. Branch pushes are backup only. **Do NOT open a PR until the user says so.**

---

## 1. State in one line

Phase D #6 is **functionally complete and device-validated**. Everything below works on the real Jetson + phone. The only remaining step is the **PR → CI** gate (nothing has been PR'd yet), plus one known-slow rough edge (overlay burn).

---

## 2. What this work is

The camera (NVIDIA Jetson Orin Nano firmware, C++20 hexagonal) records a **clean L1** MP4 and persists the scoreboard overlay as a **timeline (data)** beside it — the overlay is **never** burned into the recording. Overlay is **firmware-unilateral**: it's composited only onto the live stream, and the app no longer draws its own overlay anywhere. To get an overlaid clip the app asks the firmware to **render it on demand** (decode L1 → composite timeline → encode L2), download once. Plus a **single | side-by-side dual-camera** live preview toggle.

Architecture brainstorm: `sst-cam-app/docs/brainstorms/2026-06-26-multicam-overlay-architecture-requirements.md`
Plans: `sst-cam-app/docs/plans/2026-06-26-app-bug-sweep-and-multicam.md`, `sst-cam-firmware/docs/plans/2026-06-26-firmware-bug-sweep-and-multicam.md`

---

## 3. Commits on the branch (since `release/0.1.0`)

**App** (`sst-cam-app`, newest first):
- `ed1012a` fix(wifi): auto-recover preview when the WiFi group drops on its own
- `5316b4f` fix(preview): don't create an orphan VLC controller; recover after a stall
- `6044218` fix(clips): one failing clip no longer aborts the rest; honest gallery reporting
- `58ce76e` fix(preview): one VLC client per visible tab (match preview stuck on "waiting")
- `fd6227c` fix(video): stop app-drawing overlay on playback; overlay option for highlights (A6a/A6c)
- `27b3346` feat(video): on-demand overlayed export + download flow (A6c)
- `0c9ea2a` feat(preview): single | side-by-side dual-camera preview toggle (A6b)

**Firmware** (`sst-cam-firmware`, newest first):
- `59e6415` fix(wifi): harden P2P group-owner formation against "<no reply>" / no GROUP-STARTED
- `1295a2b` fix(session): reset scoreboard state on a new match (stale overlay carry-over)
- `095e0e5` feat(preview): side-by-side dual-camera preview composite (F6d)
- `0a00826` chore(deploy): add `libopencv-videoio406t64` runtime dep (F6c burn)
- `a03895a` feat(overlay): on-demand overlayed burn job (F6c)
- `04b476a` feat(overlay): persist overlay timeline during recording (F6b)

(F6a — clean L1 vs overlaid stream split — was already merged to `release/0.1.0` earlier.)

---

## 4. What's DONE + device-validated

| Item | Status |
| --- | --- |
| #1 Record → clean L1 MP4 | ✓ device |
| #2 Overlay only on camera stream (app draws none, live or playback) | ✓ device |
| #3 Dual preview Single \| Both (cam0 \| cam1 composite) | ✓ "flawless" |
| #5 No past-video retrieval while a match is live (client gate + firmware `LIVE_SESSION_ACTIVE`) | ✓ device |
| #6 `<matchId>.timeline.json` persisted beside L1 (anchor + scenes) | ✓ verified on device |
| A6c on-demand overlay burn → L2 in `videos/exports/` → download | ✓ (exports exist on device) |
| Overlay option on highlights (clips slice from overlaid L2) | ✓ device |
| Stale scoreboard reset between matches (firmware) | fixed; re-confirm on a fresh match |
| Clips: multi-goal (one failure no longer aborts the rest) + honest gallery reporting | ✓ device |
| Preview: one VLC client per visible tab (no dual-client stall) | ✓ device |
| Preview: no orphan VLC controller / recover after a stall | ✓ device |
| WiFi: harden P2P group-owner formation (drain events, bigger budget, 5×/1s retries) | ✓ device |
| WiFi: auto-recover the group when it drops while BLE stays up | ✓ device |

---

## 5. What's LEFT

1. **PR → CI (the actual "done" per the workflow).** Nothing is PR'd. Open app + firmware PRs into `release/0.1.0`, let the gates run:
   - App gate: `Analyze & Test (Linux)` (dart format → gen-proto → analyze → `flutter test`) + `CI Scripts`.
   - Firmware gate: `ci-scripts` / `format` (clang-format-18) / `tidy` (sharded clang-tidy, hard gate) / `test` (cross-build + ctest under qemu; HW-bound tests excluded by name).
   - Pushing to `release/**` mints betas (`-beta.N`). Don't merge release→main casually.
2. **Overlay-burn perf — slow.** Software x264 on the no-NVENC Orin Nano; even a <1-min clip takes a while. It's an offline, on-demand render so it's tolerable — **recommend accept + file a follow-up**, or profile (suspect `cv::VideoWriter` 'avc1' backend / per-frame cost). Not yet investigated.
3. **Optional re-confirm:** start a fresh match right after a previous one → scoreboard reads **0-0** (the stale-score fix `1295a2b`).

---

## 6. How to build / deploy / test locally

### Environment
- **Jetson:** `sst@10.10.1.30` (ssh key-based). Currently running the local build (`sha 59e6415` firmware). systemd service `sst-cam-firmware` (`/opt/sst-cam/bin/`). Logs: `ssh sst@10.10.1.30 journalctl -u sst-cam-firmware -f`. NOTE: the Jetson RTC is unsynced at boot → early logs show **1969** dates; ignore.
- **Phone (Galaxy S-series):** adb over WiFi. **The adb port changes on every phone wake** — ask the user for the current `10.10.1.121:<port>` each time, then `adb connect`. Host adb: `~/Android/Sdk/platform-tools/adb` (host-only, NOT in the devcontainer).
- **App devcontainer:** long-lived container `sst-cam-app_devcontainer-app-1`, workspace `/workspaces/sst-cam-app`. **BUILD the app here, never via one-shot docker** (one-shot churns the debug keystore → forces a phone data-wipe + breaks `package_config`).
- **Firmware:** cross-build only via the devcontainer CLI: `devcontainer exec --workspace-folder . bash -lc '...'`. Host clangd diagnostics are meaningless (no sysroot) — trust the in-container `cmake --build`.

### App — build, test, install
```bash
# inside the long-lived app devcontainer:
docker exec sst-cam-app_devcontainer-app-1 bash -lc 'cd /workspaces/sst-cam-app && \
  dart format lib test && flutter analyze && flutter test'           # gate

docker exec sst-cam-app_devcontainer-app-1 bash -lc 'cd /workspaces/sst-cam-app && \
  flutter build apk --release --flavor dev --target lib/main_prod.dart --dart-define=APP_ENV=stage'
# → build/app/outputs/flutter-apk/app-dev-release.apk  (dev flavor = REAL backend + dev tooling)

ADB=~/Android/Sdk/platform-tools/adb
$ADB connect 10.10.1.121:<PORT>
$ADB -s 10.10.1.121:<PORT> install -r build/app/outputs/flutter-apk/app-dev-release.apk
```
App logs (flutter only, fast): `$ADB -s 10.10.1.121:<PORT> logcat -d -s flutter:V | tail -60`.
Useful tags for preview/wifi bugs: `flutter:V VLC:V WifiP2pService:V`. `logcat -d` (full) is slow over WiFi — prefer `-t N` or tag filters.

### Firmware — build, deploy
```bash
cd /home/rs/Documents/sst/sst-cam-firmware
# gate (do this before any push):
devcontainer exec --workspace-folder . bash -lc 'cmake --preset test && cmake --build --preset test && ctest --preset test'
# 4 HW-bound tests are EXPECTED to fail in-container: GstreamerAdapter.CaptureSingleFrameAndLog,
# BleAdvertisementTest.AdvertisesOnRealBluez, WpaWifiManagerE2E.FormsAutonomousGroupOwner,
# DownloadServerTest.HttpServesByteRangeWithBearerToken.

# tidy hard gate (verify locally — bare clang-tidy gives false positives, must use tidy-args):
devcontainer exec --workspace-folder . bash -lc 'source scripts/tidy-args.sh && \
  clang-tidy -p build/test "${TIDY_EXTRA_ARGS[@]}" <changed.cpp>'
devcontainer exec --workspace-folder . bash -lc 'clang-format-18 --dry-run --Werror <files>'
devcontainer exec --workspace-folder . bash -lc 'scripts/check-floor-nolints.sh origin/release/0.1.0'

# release build + deploy to the Jetson (build in container, scp/ssh from host):
devcontainer exec --workspace-folder . bash -lc 'cmake --preset release && cmake --build --preset release'
scp build/release/bin/sst_cam_firmware deploy/install.sh sst@10.10.1.30:/tmp/
ssh -t sst@10.10.1.30 'sudo bash /tmp/install.sh --binary /tmp/sst_cam_firmware'
# verify: ssh sst@10.10.1.30 "systemctl is-active sst-cam-firmware"  + grep journal for
# "PipelineOrchestrator: started with 2 camera(s)" and no error/fail.
```

### End-to-end device test checklist
1. **Record:** start a match, record, end → a clean `<matchId>.mp4` lands under `videos/<user>/<matchId>/`, plus `<matchId>.timeline.json` beside it.
2. **Live overlay:** scoreboard shows in the live preview, **not** doubled.
3. **Dual preview:** Single | Both toggle (camera card while previewing + match live-thumb) → side-by-side cam0 | cam1.
4. **Stale score:** start a NEW match right after → scoreboard reads 0-0.
5. **Playback:** download a past match clean → plays with **no** overlay; download with "Burn in scoreboard overlay" → plays the **camera's** overlay (app draws none).
6. **Highlights:** 2+ goals → All highlights → all clips land in the gallery (Movies/SSTCam), not just the first; tick the overlay box → clips slice from the overlaid game.
7. **Live-block:** during a live match, retrieval/export controls are disabled; firmware `LIVE_SESSION_ACTIVE` handled gracefully.
8. **Preview resilience:** background the app / lock screen / switch tabs → preview re-forms the group and resumes on its own (no stuck placeholder, no manual restart).

---

## 7. Gotchas / lessons (don't relearn these)

- **One-shot docker for app builds = data wipe.** Always the long-lived devcontainer.
- **Adb port changes every phone wake.** Ask the user; `adb connect` fresh.
- **`MockBleService` has 3 exhaustive `BleCommand` switches** (encode / buildResponse / mapResponse). A new `BleCommand` needs a case in ALL THREE or `flutter analyze` fails.
- **After any proto bump:** regenerate app bindings (`protoc --dart_out=lib/models/proto -I proto proto/*.proto`, `protoc_plugin 21.1.2`) AND check for non-exhaustive switches on `Command`/`CommandResponse` payloads before pushing — stale local bindings hide it. (Not needed this phase; proto unchanged.)
- **Firmware tidy floor-NOLINT:** the `// floor-ok:` marker must be on the SAME line as the NOLINT; verify with `tidy-args.sh` (bare clang-tidy → false positives) + `check-floor-nolints.sh`.
- **`GalleryService.saveVideo` swallows errors + returns null** (never throws) — check the return value, don't rely on a catch.
- **Clips slice LOCALLY** from the full game on device — the firmware has one continuous file, no server-side trim. Overlaid clips need the overlaid L2 downloaded first.
- **OpenCV videoio** runtime dep `libopencv-videoio406t64` is required for the burn (already in `install.sh` + sysroot deb list).
- **Preview = one VLC client per visible tab.** Both home + match preview cards stay mounted in the shell IndexedStack; two clients on the single-stream RTSP server stall the second.

---

## 8. Memory pointers (auto-loaded)

`bug-sweep-2026-06-26-status.md` is the running project memory with full per-bug detail. Other relevant: `app-build-via-devcontainer-not-oneshot`, `format-flutter-via-dart-docker`, `local-validation-loop`, `pipeline-is-primary-verification`, `branch-ruleset-policy`, `main-promotion-caution`.
