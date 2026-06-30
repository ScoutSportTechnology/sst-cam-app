---
date: 2026-06-29
topic: make-it-real-batch
---

# Make-It-Real Batch — Honest UI, Real Telemetry, and Cross-Repo Wiring

## Summary

Replace the app's placeholder and dead UI with real data, and build the proto + firmware enablers behind it: real camera-state on the hero card, a Settings Diagnostics section fed by live telemetry, real version strings, a working Reboot command, independent record/stream quality controls, a simplified manual streaming-credential model, plus two firmware fixes (pink color cast, telemetry completion).

---

## Problem Frame

The app currently shows several things that are not true. The main hero card's status dot reads green "LIVE" off connection state alone — it stays green when the camera is idle and not streaming to anything. The Settings camera card prints a hardcoded `fw 0.3.2 · proto v0.3`, the About row prints `0.3.2` while `pubspec.yaml` is actually `0.1.0+1`, and the standalone Diagnostics page is entirely mock (fabricated MTU/RSSI/connection-interval and a fake command log, four action buttons wired to nothing). The Reboot and Update-fw buttons are disabled placeholders. The match-setup quality/fps dropdown is a dead control whose value is never sent anywhere. The database browser is functional but visually off-design. Streaming setup is convoluted and, worse, silently drops saved destinations — only a raw custom RTMP URL ever reaches a match.

The cost: an operator cannot trust what the app reports, cannot tell the camera's real state at a glance, cannot reboot it, cannot choose recording or streaming quality, and has a streaming flow that ignores its own saved data. Meanwhile the firmware already exposes real telemetry the app isn't reading, and a known pink color cast in the image has no owner.

This is a deliberate "complete work" pass across all three repos (`sst-cam-app`, `sst-cam-proto`, `sst-cam-firmware`), not an app-only polish round.

---

## Actors

- A1. Operator (user): sets up and runs matches, starts/stops recording and streaming, reads diagnostics, reboots the camera.
- A2. App (`sst-cam-app`, Flutter): renders UI, sends `Command`s over BLE, displays telemetry and versions.
- A3. Firmware (`sst-cam-firmware`, Jetson camera): executes commands, reports `DeviceTelemetry`/`DeviceInfo`, runs the capture/encode/record/stream pipeline and the ISP.
- A4. Proto contract (`sst-cam-proto`): the wire schema, vendored into firmware and app; any new field is a coordinated change here first.

---

## Key Flows

- F1. Configure and start a match with quality + streaming
  - **Trigger:** Operator opens match setup.
  - **Actors:** A1, A2, A3
  - **Steps:** Pick record quality/fps and stream quality/fps from firmware-advertised modes → choose a streaming destination (a saved persistent custom-RTMP destination, or enter a per-match one-off url+key, or none) → start match → app sends session config incl. quality fields → firmware (re)configures pipeline at session start.
  - **Outcome:** Camera records at the chosen record quality and (if a destination is set) streams at the chosen stream quality; the two hidden raw recordings continue at fixed default low-res.
  - **Covered by:** R15, R16, R17, R18, R19, R20

- F2. Start streaming mid-match with no credential set
  - **Trigger:** Operator toggles streaming on during a live match while the match has no streaming credential.
  - **Actors:** A1, A2, A3
  - **Steps:** App detects no credential on the match → prompts operator to enter an RTMP url+key (or pick a saved destination) → stores it on the match only → sends streaming-control with the destination → streaming starts.
  - **Outcome:** Streaming begins; the entered credential lives on that match only, not in the global destinations list.
  - **Covered by:** R19, R20

- F3. View diagnostics
  - **Trigger:** Operator opens Settings → Diagnostics.
  - **Actors:** A1, A2, A3
  - **Steps:** App reads live `DeviceTelemetry` + network config → renders real camera metrics → renders app build/version, app logs, database-browser entry.
  - **Outcome:** Operator sees only real data; unavailable metrics are labeled unavailable, not faked.
  - **Covered by:** R4, R5, R6, R7, R8

- F4. Reboot the camera
  - **Trigger:** Operator taps Reboot on the connected-camera card.
  - **Actors:** A1, A2, A3
  - **Steps:** App shows a confirm dialog → on confirm sends the new Reboot command → firmware reboots.
  - **Outcome:** Camera restarts; button is disabled while disconnected.
  - **Covered by:** R13

---

## Requirements

**Main hero card**
- R1. The hero card preview button and preview-mode toggle render inline using the match/session screen pattern (two `Expanded` columns, `full: true`), so widths and right edges line up.
- R2. The hero card disconnect button uses the danger (red) variant, and all hero-card action buttons share equal height and width (same fix already applied on the match screen).
- R3. Replace the connection-only green "LIVE" indicator with a real camera-state indicator derived from `DeviceTelemetry` flags. States: Disconnected, Standby (connected, idle), Preview, Recording, Streaming, with precedence Streaming > Recording > Preview > Standby > Disconnected. Label and color reflect the real state.

**Settings — Diagnostics restructure**
- R4. Add a dedicated Diagnostics section in Settings covering both Camera and App, replacing the all-mock standalone diagnostics page.
- R5. Camera diagnostics display real `DeviceTelemetry`/network data: storage free/total, temperature, RAM %, CPU %, uptime, wifi state + SSID, recording/streaming/raw-capture flags, and network uplink status. Remove the fabricated MTU, RSSI, connection-interval, and command-log content.
- R6. Telemetry fields the firmware does not yet provide real values for (battery, internet-reachable, and wifi-RSSI until firmware wiring lands) are shown as "unavailable" — never as fabricated numbers.
- R7. The App diagnostics subsection shows app build/version info and provides access to the app logs and the database browser, mirroring the camera-diagnostics layout.
- R8. Move the app log viewer out of Developer settings and into the Diagnostics section so it sits alongside camera diagnostics.

**Database browser**
- R9. Redesign the database-browser UI to match the app's modern design language (consistent with the rest of the app).

**Versions**
- R10. Replace all hardcoded version placeholders with real values: app version from package metadata (`pubspec`), firmware version from the device-reported `firmware_version`, and proto version.
- R11. Proto version display shows both axes distinctly: the proto repo SemVer release (tag) the app was built against, and the wire `protocol_version` integer the connected device reports.
- R12. Local/dev builds derive their displayed version and channel from git (nearest tag + commits-ahead + short SHA, channel from branch per the alpha/beta/stable ladder), so the shown version reflects what is actually being worked on rather than a manually chosen guess.

**Reboot & Upgrade**
- R13. Implement a real camera Reboot: a new proto command + a firmware handler that reboots the device. The app button is wired with a confirm dialog and is disabled while disconnected.
- R14. Rename the "Update fw" button to "Upgrade" and repurpose it to surface firmware version + "managed via `install.sh`" information rather than a fake action, until over-the-wire upgrade exists.

**Recording & streaming quality / fps**
- R15. Add independent, app-controlled record quality/fps and stream quality/fps, settable in any combination (e.g. record 1080p, stream 720p). This requires new proto fields for each, and firmware applying them by (re)configuring the capture/encode pipeline at session start.
- R16. The app presents only firmware-supported modes: firmware advertises its supported resolutions/fps and the app picks from that advertised list (not a blind static dropdown).
- R17. The two hidden raw recordings remain at their fixed default low resolution (720p, 30/60 fps) for review/training; they are not user-controllable and are unaffected by R15.

**Streaming credentials**
- R18. Settings → Streaming destinations becomes custom-RTMP-only, holding persistent/reusable credentials; the per-platform (YouTube/Instagram/etc.) workflows are dropped.
- R19. A match can carry a per-match RTMP url + key, set at match setup or mid-match (when streaming starts with no credential set). This per-match credential is stored only on that match, never added to the global destinations list.
- R20. Match setup can attach either a saved persistent destination or a per-match one-off, and actually uses the chosen value — fixing the current gap where saved destinations are ignored and only a raw custom URL propagates.

**Firmware-side fixes**
- R21. Fix the pink color cast in the camera image in the firmware capture/ISP pipeline (white-balance / color-correction configuration). The app is a pass-through VLC player and requires no change for this.
- R22. Firmware populates internet-reachable (using its existing uplink probe) and wifi-RSSI (from the wifi manager) so the diagnostics screen can show them as real data (satisfying R6 for those two fields).

---

## Acceptance Examples

- AE1. **Covers R3.** Given the camera is connected but idle (not previewing, recording, or streaming), when the hero card renders, then the indicator reads "Standby" (not green "LIVE").
- AE2. **Covers R3.** Given the camera is recording and also streaming, when the hero card renders, then the indicator reads "Streaming" (precedence: streaming over recording).
- AE3. **Covers R6.** Given the firmware reports battery = 0 / internet-reachable = false / no RSSI, when camera diagnostics render, then those fields show "unavailable" rather than a number.
- AE4. **Covers R12.** Given a local build on a feature branch two commits past tag `v0.1.0-alpha.4`, when the version is displayed, then it shows a git-derived string on the alpha channel (e.g. `0.1.0-alpha.4+2-gabc123`), not a hardcoded literal.
- AE5. **Covers R13.** Given the camera is disconnected, when the operator views the camera card, then the Reboot button is disabled; given it is connected, when the operator taps Reboot, then a confirm dialog appears before any command is sent.
- AE6. **Covers R16.** Given firmware advertises only {1080p30, 1080p60, 720p30, 720p60}, when the operator opens the quality picker, then only those modes are offered (no 4K option appears).
- AE7. **Covers R19.** Given a match with no streaming credential, when the operator starts streaming mid-match, then the app prompts for an RTMP url+key, stores it on that match only, and begins streaming; the credential does not appear later in Settings → Streaming destinations.
- AE8. **Covers R15, R17.** Given record set to 1080p and stream set to 720p, when the match starts, then recording runs at 1080p and the stream at 720p, while the two raw recordings stay at their fixed 720p default.

---

## Success Criteria

- An operator can look at the hero card and Settings and trust every value shown — no field displays data that is not real, and unavailable data says so.
- The operator can choose record and stream quality independently, reboot the camera, and stream to a per-match or saved destination without the app discarding their input.
- The image shows correct color (no pink cast) on real hardware.
- A downstream planner can sequence the work from this doc without inventing product behavior: each cross-repo workstream (Reboot, quality/fps, streaming model, firmware telemetry, ISP) has a clear app/proto/firmware split and a stated boundary.

---

## Scope Boundaries

- Over-the-wire firmware OTA / upgrade — deferred; current upgrade path stays `deploy/install.sh`. The "Upgrade" button is informational only this round (R14).
- Per-platform streaming API integration, OAuth, refresh-token storage, and Google/Meta app verification — rejected. All streaming credentials are entered manually (R18–R20).
- Third-party multistream relay (e.g. Castr) — rejected for this round.
- Instagram Live and TikTok Live — not feasible (no programmatic broadcast API); excluded.
- Facebook Live API — excluded (formal Meta App Review gate, ephemeral keys).
- Real battery telemetry — deferred until target hardware is known; no battery/fuel-gauge sensor is confirmed to exist, so the tile stays "unavailable" (R6) rather than wired.
- `FactoryResetCommand` wiring — out of scope; Reboot (R13) is a distinct new command.
- Changing the raw dual-recording resolution/fps or making it user-controllable — out (R17).
- Live mid-record quality switching — out; quality applies at session start via pipeline (re)configuration (R15).

---

## Key Decisions

- Streaming uses a manual, two-tier credential model (persistent custom-RTMP destinations in Settings + per-match one-off credentials), with no OAuth/API/relay: research showed only a paid relay (Castr) offers pure API-key on-demand generation, and direct platforms (YouTube/Twitch/Kick) all require OAuth; the operator's existing "mint a key per match in the platform" workflow is simpler and sufficient for self-use.
- Record and stream quality are independent controls (not one shared setting): real use is recording at higher quality than the stream (e.g. 1080p record, 720p stream).
- Versions for local builds are git-derived (not manually chosen): removes the "alpha or beta?" guesswork by mapping branch → channel and tag/commits → version automatically.
- Reboot is built for real but firmware OTA is deferred: a reboot handler is small; OTA (image transfer, flashing, rollback) is a large firmware project and `install.sh` already covers upgrades.
- Diagnostics show only real telemetry, with explicit "unavailable" for stubs: honesty over the appearance of completeness.
- Pink color is owned by firmware, not the app: the app does no color processing (pass-through VLC), so the fix is ISP/white-balance config in `sst-cam-firmware`.

---

## Dependencies / Assumptions

- `DeviceTelemetry` already provides real storage, temp, RAM, CPU, uptime, wifi state/SSID, and recording/streaming/raw flags (verified in `sst-cam-firmware/src`), and `DeviceInfoResponse` provides a real `firmware_version` and wire `protocol_version`. The app must add a telemetry read/subscribe path to surface them.
- New proto fields (record quality/fps, stream quality/fps, reboot command) require a coordinated change: proto first, then the firmware submodule bump and handler, then the app submodule bump and UI.
- The app does not currently depend on a package-info plugin (no `PackageInfo` usage found); R10/R12 likely add that dependency.
- Available quality presets (R16) depend on what the IMX477 sensor + firmware GStreamer pipeline can actually deliver and switch to at session start — to be confirmed against firmware capabilities.
- Firmware capture res/fps currently come from `calibration.json` at startup and compile-time constants; R15 requires making the encode/stream path runtime-configurable from session config.

---

## Outstanding Questions

### Resolve Before Planning

- (None blocking — all product-scope decisions are resolved above.)

### Deferred to Planning

- [Affects R15, R16][Needs research] Which exact resolution/fps modes the IMX477 + firmware pipeline can deliver, and whether a session-start pipeline reconfigure (vs full restart) is acceptable latency-wise.
- [Affects R15, R13][Technical] Exact proto message/field shapes for record/stream quality and the reboot command.
- [Affects R21][Needs research] Root cause of the pink cast — white-balance vs pixel-format vs ISP tuning — and the correct firmware fix.
- [Affects R12][Technical] The precise git-describe → version-string format and branch → channel mapping for the app repo's CI, consistent with the existing alpha/beta/stable ladder.
- [Affects R3][Design] Camera-state color palette and iconography (e.g. red = recording/live, amber = standby, grey = disconnected).
- [Affects R6][Technical] Whether the target camera hardware has any battery/fuel-gauge sensor at all (gates whether battery is ever wired).
