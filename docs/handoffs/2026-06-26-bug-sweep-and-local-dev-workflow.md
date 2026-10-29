# Handoff — bug sweep + local dev workflow (2026-06-26)

Paste this into the next session. Goal of next session: **brainstorm → plan → work**, fixing
app + firmware **side by side**.

## Guiding principle (confirmed)
**The app I build locally must be byte-for-behaviour identical to the CI app.** No build-type
divergence. This is why the R8/minify fix below turns R8 OFF on release instead of papering over
it with keep-rules — release dex now matches what `flutter run` (debug, never minified) produces.

---

## Current state
- **Firmware:** `v0.1.0-beta.15` installed on Jetson `sst@10.10.1.30` (idempotent WiFi-Direct data
  plane — group-remove-before-add, `ip addr replace`, dnsmasq restart, CAP_NET_RAW). Prior local
  build backed up at `/opt/sst-cam/bin/sst_cam_firmware.bak`.
- **App:** `release/0.1.0` has the scan + P2P-permission fixes (merged PR #32 → beta.9). Preview
  was crashing on beta.9 — see Bug 0.
- **Phone:** currently has an **interim local build** (`com.sst.sstcam.dev`, R8+keep-rule variant)
  that fixed the crash. Working tree now switched to **R8-off** (Bug 0 fix) but **not yet rebuilt/
  installed** — see "Step 0".
- **Uncommitted (app working tree):** `android/app/build.gradle.kts` release block
  `isMinifyEnabled = false`; `android/app/proguard-rules.pro` deleted. Needs rebuild + on-device
  verify, then commit + PR to `release/0.1.0`.

## Step 0 (do first, verifies Bug 0)
Rebuild the R8-off dev APK, install, confirm Live Preview no longer crashes:
```
# in the app persistent devcontainer
flutter build apk --release --flavor dev -t lib/main_prod.dart --dart-define=APP_ENV=stage
# host adb (port rotates — get current from phone Wireless debugging)
adb connect 10.10.1.121:<port>
adb uninstall com.sst.sstcam.dev   # CI/local debug keys differ -> wipes data, expected
adb install build/app/outputs/flutter-apk/app-dev-release.apk
```
If no crash → commit the R8-off change + PR to release/0.1.0.

---

## Bug 0 — preview crash (root-caused, fix in tree, verify pending)
Release R8 tree-shook libVLC's JNI-only class `org.videolan.libvlc.interfaces.IMedia$Track`
(referenced only via native `FindClass` in `libvlcjni.so` `JNI_OnLoad`, invisible to R8). libVLC
then `System.exit(1)` → app closes on Live Preview. Debug (`flutter run`) never runs R8, so it
worked there. **Fix: R8 off on release** (`isMinifyEnabled = false`).

## New bugs (reported this session)
1. **Preview "WIFI · WAITING FOR FRAMES"** after the crash fix — P2P joins but frames never render
   (VLC connects but no decoded frames, or RTSP not delivering). Investigate app VLC pipeline +
   firmware RTSP appsrc.
2. **Intermittent "wifi failed"** — must background app, stop/start preview repeatedly until it
   works. Related to deferred app fixes (request NEARBY_WIFI_DEVICES *before* StartWifiDirect;
   subscribe stateStream right before `_channel.connect`) AND firmware P2P join timing.
3. **"Record Raw (Training)"** label — unclear why it says this; clarify the recording-mode naming/
   intent.
4. **"Open match" button** doesn't open matches. If none exist it should at least route to the match
   page to create one.
5. **Record button placement** — should live in Match. Add an option to record a **Training**
   session when there's no match.
6. **Multi-camera + recording/overlay architecture (BIG — needs joint app+firmware design):**
   - Today: default camera 0, raw footage only.
   - Want firmware to record ≥3 streams: **raw**, **cam0**, **cam1**; plus optional **overlaid**
     output (when overlay active) for streaming/saving. Keep raw so a clip can be viewed with or
     without overlays (overlay rendered camera-side to simplify the app).
   - Want a **dual-camera side-by-side live preview** (default aspect 9:16 / 1080×1920, scaled to
     fit both in the hero card) selectable via a dropdown — to see what both cameras see, not just
     raw. Same for the **match** live preview (they're connected).
7. **Settings > Developer toggles:** render as plain yellow pills (wrong toggle-switch UI), and they
   read as "active" though nothing is emulated (shouldn't be in the real backend).
8. **Settings > Developer:** add an in-app **log viewer / exporter** so adb isn't strictly required
   (adb stays the primary path).
9. **Video page** shows "connect camera" even though a camera IS connected (stale connection state
   on the video page).

## Bugs I found earlier (deferred from code review — carry into the plan)
- **App:** request `NEARBY_WIFI_DEVICES` *before* sending `StartWifiDirect` (denial currently leaves
  the firmware group up); subscribe the platform stateStream *right before* `_channel.connect` (a
  stale `failed` event can flash the hero card). → relates to Bug #2.
- **App:** preview **image distortion** (aspect/scaling — you flagged it).
- **Firmware:** dnsmasq orphan after a firmware **crash** (SIGKILL/OOM resets `pid_` → a leftover
  dnsmasq is invisible to the next start; add a pkill/pidfile sweep before fork). `SendCommand`
  treats a zero-length datagram as a reply (`bytes==0` inconsistency with `ReadUntil`).
- **Test seams:** factor pure `DrainUntilReply` (wpa), `ScanLifecycleTracker` (ble scan), and inject
  a permission-checker into `WifiServiceImpl` so the denial branch is unit-testable.

---

## Local dev workflow (NOT in a single runbook yet — TODO: write docs/runbooks/local-dev-loop.md)
Currently scattered across: app `justfile` comments, firmware `deploy/README.md`, and memory
entries (`local-validation-loop`, `app-analyze-via-docker`, `format-flutter-via-dart-docker`).

**Repos:** `~/Documents/sst/{sst-cam-app, sst-cam-firmware, proto}`. Branch model:
`feat/* → development → release/0.1.0 → main`. Both currently iterating on `release/0.1.0` (betas).

**Firmware (Jetson `sst@10.10.1.30`, JetPack 7.2):**
- Build/test **only** in the devcontainer: `devcontainer up --workspace-folder .` then
  `devcontainer exec ... cmake --build --preset test && ctest --preset test`.
- **clang-tidy + shellcheck are HARD CI gates.** Run `scripts/fix.sh --all` and
  `shellcheck deploy/*.sh scripts/ci/*.sh` BEFORE pushing — the branch's first CI run failed on
  accumulated tidy/shellcheck debt (identifier-length, magic-numbers, member-to-static, SC2317).
- Deploy a **local** build: `just deploy-jetson sst@10.10.1.30` (cross-build + scp + `install.sh
  --binary`). Install a **release**: `scp deploy/install.sh sst@…:/tmp/ && ssh … "sudo bash
  /tmp/install.sh --version vX.Y.Z-beta.N"` — use `--version` explicitly; `latest` resolves only
  *stable* releases and all ours are prereleases. Repo is public (no token needed).
- Verify on device: `ip -br addr | grep wlP`, `iw dev`, `journalctl -u sst-cam-firmware`, CapEff.

**App (phone — Samsung S24, Android 14):**
- Persistent devcontainer: `devcontainer up` once, then `devcontainer exec ... flutter …`. App
  devcontainer `up` is slow (~minutes, two compose services + flutter doctor) — not hung.
- **adb runs on the HOST**, listening on all interfaces so the container reaches it via
  `host.docker.internal:5037`: `adb -a -P 5037 server &`. The devcontainer initialize-command also
  restarts adb. The phone's **wireless-debug port ROTATES** (reboot/toggle) → `adb connect
  10.10.1.121:<port>` each session (pair once via `adb pair`).
- Iterate with **`flutter run`** (hot reload + live logs) via the devcontainer. For the shipped
  artifact use `flutter build apk --release --flavor dev … && adb install`. **Uninstall first** if
  you hit `signatures do not match` (CI debug key ≠ local debug key → wipes app data).
- Verify: `flutter analyze` + `flutter test` (575 tests). `dart format` before push (CI format gate).
- **CI is the authoritative gate** (pipeline-is-primary-verification); local is the fast pre-check.

## Suggested next-session flow
1. **Step 0** above — verify the R8-off preview fix on device, then commit + PR to `release/0.1.0`.
2. `/ce-brainstorm` the bug set. Bug #6 (multi-cam + recording + overlay + dual preview) is a
   joint app+firmware architecture change — brainstorm it first and separately.
3. `/ce-plan` per repo (app plan + firmware plan, cross-referenced).
4. `/ce-work` the units side by side; keep firmware idempotency + app local==CI principles.
5. Write `docs/runbooks/local-dev-loop.md` so this workflow stops living in scattered places.
