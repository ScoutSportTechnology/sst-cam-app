---
title: "feat: WiFi-Direct stable connection (persistent group + lean recovery)"
type: feat
status: active
date: 2026-06-28
origin: docs/brainstorms/2026-06-28-wifi-direct-stable-connection-requirements.md
---

# feat: WiFi-Direct stable connection (persistent group + lean recovery)

> **Cross-repo plan.** Units are tagged **[firmware]** (`sst-cam-firmware`) or **[app]** (`sst-cam-app`). File paths are repo-relative to the tagged repo. This plan doc lives in `sst-cam-app/docs/plans/`.

## Summary

Make the camera's WiFi-Direct group **persistent** so its SSID/PSK stay identical across every re-form (firmware), and replace the app's timer-based reconnect with a **verify-before-action** model that polls reachability and waits when the link isn't ready (app). The persistent identity lets the phone OS auto-rejoin one saved network instead of rediscovering a new SSID each time, which is what broke downloads.

---

## Problem Frame

Every WiFi-Direct re-form currently mints a new random SSID (`sst-cam-firmware/src/adapters/control/wifi/wpa_supplicant/wpa-wifi-manager.cpp` calls bare `P2P_GROUP_ADD`), so the phone must rediscover + rejoin and any HTTP download right after fails "no route to host." The app's reactive timer recovery made it worse by re-forming on transient blips (self-sustaining flap). See origin for the full pain narrative and on-device evidence (Sources & References).

---

## Requirements

- R1. Camera forms/reuses a persistent WiFi-Direct group: identical SSID + passphrase across every formation, within a session and across firmware restarts.
- R2. A repeated bring-up request reuses the existing/persistent group rather than tearing down + minting a new identity.
- R3. Credentials reported over BLE are the stable persistent-group credentials.
- R4. App runs no periodic/timer-based WiFi reconnect loop and does not re-form the group on transient wifi-state transitions.
- R5. Rejoining the saved network is owned by the phone OS; the app does not drive WiFi reconnection.
- R6. Before any WiFi-dependent action (preview start, download), the app verifies the camera data plane is reachable.
- R7. On reachability failure, the app waits (polling) in a visible "reconnecting…" state up to a bounded timeout, then surfaces a clear, actionable error — never failing hard on the first raw connection error.

**Origin actors:** A1 (companion app), A2 (camera firmware), A3 (phone OS WiFi stack)
**Origin flows:** F1 (bring-up), F2 (verify-before-action), F3 (re-form survival)
**Origin acceptance examples:** AE1 (R6,R7), AE2 (R7), AE3 (R1,R3), AE4 (R4)

---

## Scope Boundaries

- SoftAP / iOS data-plane support — excluded (persistent P2P, Android-only).
- Firmware-driven active health-checks / reconnect monitoring — excluded (recovery responsibility is OS + app verify).
- BLE health-check — excluded (BLE stable); verify-before-action is WiFi-only.
- Burn CPU contention (#18 x264 thread-cap / nice) — already shipped; not in this plan.

### Deferred to Follow-Up Work

- Human-friendly SSID (if wpa_supplicant constrains P2P SSIDs to `DIRECT-xx-…`) — accept a stable-but-machine SSID for now; cosmetic rename is a separate item.

---

## Context & Research

### Relevant Code and Patterns

- **[firmware]** `src/adapters/control/wifi/wpa_supplicant/wpa-wifi-manager.cpp` — `StartP2pGroupOwner()` (the bare `P2P_GROUP_ADD` to change), `Stop()`, `SendCommand`/`ReadUntil`/`ParseGroupStarted` helpers, `DrainPendingEvents`. The retry/event-drain machinery and `ParsedGroup` parsing are reused.
- **[firmware]** `src/adapters/control/wifi/wpa_supplicant/` config struct loading `wifi-direct.json` (`ssid`, `passphrase`, `channel`, `ip_address`) — currently loaded but unused in group formation.
- **[firmware]** `WifiDirectGroup` model returned over BLE (`src/domain/network/...`) — already carries ssid/psk/ip; no shape change needed.
- **[app]** `lib/core/wifi/wifi_handoff.dart` — `WifiHandoffController`; the recovery block (cooldown + budget + stable-timer) to be removed; BLE-driven bring-up/teardown kept.
- **[app]** `lib/core/wifi/wifi_service.dart` / `wifi_service_impl.dart` / `lib/mock/emulator/mock_wifi_service.dart` — the WiFi port; add a reachability probe method here (mirrors how `connectGroup`/`startDownload` are declared on the port + implemented in real + mock).
- **[app]** `lib/features/video/playback/download_sheet.dart` — overlay-export poll loop + `startDownload` + `_mapDownloadError`; the verify-before + reconnecting-wait wraps the download start.
- **[app]** `lib/core/widgets/live_preview_view.dart` — VLC start gating + placeholder/status states (`statusLabel`, `shouldStream`); reachability gates preview start.
- **[app]** Tests: `test/core/wifi/wifi_handoff_test.dart`, `test/features/video/playback/download_sheet_test.dart` (has `_ControlledWifiService`/`_ControlledBleService` stubs), `test/mock/mock_wifi_service_test.dart`.

### Institutional Learnings

- Firmware build = devcontainer cross-compile only; `clang-tidy` is a hard CI gate (magic-numbers, easily-swappable-params, cognitive-complexity, floor-NOLINT same-line rule). Validate locally via `cmake --build --preset test` + tidy before push.
- App build via the long-lived devcontainer; `dart format` + `flutter analyze` gate CI; the real WiFi/BLE backends are exercised on device (mock+emulator for unit tests).
- On-device truth: firmware journal (`ssh sst@10.10.1.30 journalctl -u sst-cam-firmware`) shows `StartP2pGroupOwner formed group …`; pinging the phone from the Jetson + `iw dev wlP1p1s0 station dump` reveals link state. Jetson RTC can show 1969 early — key off event order.

### External References

- wpa_supplicant P2P persistent groups (`P2P_GROUP_ADD persistent` / `persistent=<network id>`, `LIST_NETWORKS`, `p2p_persistent_group`) — exact command set + creds retrieval is the primary on-device unknown (see Open Questions / U1).

---

## Key Technical Decisions

- **Persistent group via the existing `WpaWifiManager`, not a rewrite:** keep the proven retry/event-drain machinery; change only how the group is created (persistent + reused) and add a "is a usable group already up?" short-circuit. Rationale: the bare-`P2P_GROUP_ADD` retry logic exists precisely because this radio is finicky; reuse it.
- **Reachability probe lives behind the WiFi port (`WifiService`), not in widgets:** one method the UI awaits, mockable in tests. Rationale: matches the existing port/impl/mock split; keeps download & preview flows testable without a real socket.
- **Probe = lightweight TCP connect to the download/preview host:port with a short timeout** (decision; exact target + timing in Open Questions). Rationale: a TCP connect to `192.168.49.1:8080` proves L3 route + server up without an HTTP round-trip; "no route to host" surfaces immediately as a failed connect.
- **Remove the cooldown recovery rather than keep it alongside:** the lean model (R4/R5) makes timer recovery dead weight; leaving it risks re-introducing the flap. Rationale: origin Key Decision.

---

## Open Questions

### Resolved During Planning

- Where does the reachability check live? → behind `WifiService` (Key Decisions).
- Keep or remove the cooldown recovery? → remove (R4/R5).
- One plan or split per repo? → one cross-repo plan, units tagged by repo (origin is cross-repo and the sequencing is interdependent: app verify-before-action only pays off once the firmware SSID is stable).

### Deferred to Implementation

- [Affects U1][Needs research] Exact wpa_supplicant persistent-group command sequence on JetPack 7.2: whether `P2P_GROUP_ADD persistent` (auto-creates + stores) then `persistent=<id>` on reuse works on this driver, and how `P2P-GROUP-STARTED` creds are obtained on a persistent re-form vs first create. Validate on device.
- [Affects U1] Whether the persistent group's SSID can be set to the config value or stays wpa's `DIRECT-xx-…` (stable but machine-generated). Either satisfies R1 (stability); the human-friendly name is deferred follow-up.
- [Affects U3][Needs research] Whether Android auto-rejoins a saved P2P group with no explicit app re-connect call, or needs a one-time join the OS then persists — determines whether R5 is fully OS-owned or needs a single app-side join on first pairing.
- [Affects U4] Final probe target (download server `:8080` vs preview `:8554`) + timeout / poll-interval / overall wait-budget values — tune on device.

---

## High-Level Technical Design

> *Illustrates the intended approach; directional guidance for review, not implementation specification.*

```
BEFORE (per re-form):  P2P_GROUP_REMOVE *  →  P2P_GROUP_ADD  →  NEW random SSID  →  phone must rejoin a new network
AFTER  (per re-form):  ensure persistent group up (reuse stored id)  →  SAME SSID/PSK  →  phone OS auto-rejoins saved network

App download/preview start:
  reachable(host:port, t)?  ──yes──▶ proceed (download / start VLC)
        │ no
        ▼
  show "reconnecting…", poll reachable() every P  ──reachable──▶ proceed
        │ still unreachable after wait-budget
        ▼
  clear error ("Couldn't reach the camera — move closer / reconnect"), no raw "no route to host"
```

---

## Implementation Units

### U1. [firmware] Persistent, stable-identity WiFi-Direct group

**Goal:** Form/reuse a persistent P2P group so SSID + passphrase are identical across every formation and restart; report the stable creds over BLE.

**Requirements:** R1, R2, R3

**Dependencies:** None

**Files:**
- Modify: `src/adapters/control/wifi/wpa_supplicant/wpa-wifi-manager.cpp` (`StartP2pGroupOwner`, possibly a new private helper for "ensure persistent group", and `Stop` so teardown doesn't destroy the persistent network definition)
- Modify (if needed): `src/adapters/control/wifi/wpa_supplicant/wpa-wifi-manager.hpp` (cache the persistent network id / last creds)
- Tests: `tests/.../wpa_wifi_manager*.test.cpp` if a seam exists; otherwise rely on on-device validation (the real wpa ctrl interface is HW-bound, like the existing `WpaWifiManagerE2E` test that only passes on device)

**Approach:**
- Replace the unconditional `P2P_GROUP_REMOVE *` + bare `P2P_GROUP_ADD` with: (a) short-circuit if a usable group with the persistent identity is already up (R2); (b) otherwise (re-)invoke the **persistent** group — create-and-store on first run, reuse the stored network id thereafter — so the SSID/PSK are stable (R1).
- Keep the existing retry + `DrainPendingEvents` + `ParseGroupStarted` machinery; persistent re-forms still emit `P2P-GROUP-STARTED` (verify) — if creds aren't in the event on reuse, read them from the stored network (`LIST_NETWORKS` / `GET_NETWORK`).
- `Stop()` should drop the active group instance but NOT delete the persistent network definition, so the next bring-up reuses the same identity.
- Return the stable creds in `WifiDirectGroup` unchanged in shape (R3).

**Patterns to follow:** existing `SendCommand`/`ReadUntil`/`ParseGroupStarted`/`DrainPendingEvents` flow in the same file; the `kGroupAddAttempts` retry structure.

**Test scenarios:**
- Covers AE3. On-device: form group, note SSID; trigger a re-form (restart firmware / new match); assert the journal shows the **same** SSID and the phone reconnects without re-pairing.
- On-device: call bring-up twice in a row (simulating a redundant `StartWifiDirect`); assert the group is reused (no new SSID, R2).
- On-device: after `Stop()` + bring-up, the persistent identity is reused (not regenerated).
- Edge: first-ever boot (no stored persistent group) creates it cleanly and reports creds.
- Error: if persistent re-form fails to emit `GROUP-STARTED`, the retry path still recovers (existing behavior preserved).

**Verification:** Firmware journal shows one stable SSID across multiple re-forms; `iw dev wlP1p1s0 station dump` shows the phone associated with a stable route; a download after a fresh re-form succeeds.

---

### U2. [app] Remove timer/cooldown recovery from the handoff

**Goal:** Strip the reactive WiFi recovery (timers, cooldown, budget, stable-window) so the app never re-forms the group on transient wifi-state transitions; keep only BLE-driven bring-up + teardown.

**Requirements:** R4, R5

**Dependencies:** U1 (the lean model is only safe once the SSID is stable; sequence after firmware lands, but app code can be written in parallel)

**Files:**
- Modify: `lib/core/wifi/wifi_handoff.dart` (remove `_wifiRecoveryAttempts`, `_recoveryStableTimer`, `_recoveryCoolingDown`, `_recoveryCooldownTimer`, `_wifiWasUp` and the entire wifi-state recovery branch; keep the `id`-change teardown and BLE connected→connectGroup / disconnected→disconnectGroup bring-up)
- Modify: `test/core/wifi/wifi_handoff_test.dart` (drop the recovery/flap tests; keep + adjust the BLE-driven bring-up/teardown tests)

**Approach:**
- `build()` keeps: active-camera tracking, BLE-connected → debounced `connectGroup`, BLE-disconnected → debounced `disconnectGroup`, id-change teardown. It no longer watches `wifiConnectionStateProvider` to drive reconnects.
- Net effect: one bring-up per BLE connect; the OS owns rejoin thereafter (R5).

**Patterns to follow:** the existing debounce + `unawaited(wifi.connectGroup/disconnectGroup)` structure already in the file.

**Test scenarios:**
- Happy path: BLE connects → exactly one `connectGroup`; BLE disconnects → one `disconnectGroup`.
- Covers AE4. A wifi-state blip (connected→failed) while BLE stays connected triggers **zero** additional `connectGroup` (no recovery).
- Edge: active-camera change tears down the previous group and does not recover it.

**Verification:** `flutter analyze` clean; the handoff test asserts no re-form on wifi-state churn; on-device journal shows ≤1 group formation per BLE connect (no storm).

---

### U3. [app] Reachability probe on the WiFi port

**Goal:** Add a single awaitable reachability check to `WifiService` that tells callers whether the camera data plane is reachable right now.

**Requirements:** R6

**Dependencies:** None

**Files:**
- Modify: `lib/core/wifi/wifi_service.dart` (declare the probe on the port)
- Modify: `lib/core/wifi/wifi_service_impl.dart` (real impl — TCP connect to host:port with a short timeout)
- Modify: `lib/mock/emulator/mock_wifi_service.dart` (mock — configurable reachable/unreachable)
- Modify: `test/mock/mock_wifi_service_test.dart` (cover the mock's contract)

**Approach:**
- One method, e.g. "is the data plane reachable" returning a bool (or a small result), taking deviceId; the impl does a bounded TCP connect to the GO host + download/preview port (exact target in Open Questions) and returns false on connect error/timeout rather than throwing.
- Mock returns a settable value so download/preview tests can drive both branches.

**Patterns to follow:** the existing `WifiService` port methods (`connectGroup`, `startDownload`) declared on the abstract class and implemented in real + mock + emulator.

**Test scenarios:**
- Happy path (mock): reachable=true → probe returns true.
- Error path (mock): reachable=false → probe returns false (no throw).
- Edge (real, if a loopback seam exists): connect to a closed port returns false within the timeout, not a hang.

**Verification:** `flutter analyze` clean; mock test exercises both branches; the method is awaited by U4/U5.

---

### U4. [app] Download resilience — verify, wait, clear error

**Goal:** Gate the download (full-game and overlay-L2) on reachability: proceed if reachable; otherwise show "reconnecting…", poll until reachable or a bounded wait elapses, then a clear error — never the raw "no route to host."

**Requirements:** R6, R7

**Dependencies:** U3

**Files:**
- Modify: `lib/features/video/playback/download_sheet.dart` (wrap `startDownload` for both the plain and overlay-L2 paths with a reachability gate + reconnecting state; extend `_mapDownloadError` so any residual host-unreachable error maps to friendly copy)
- Modify: `test/features/video/playback/download_sheet_test.dart` (use the existing `_ControlledWifiService` to drive reachable / not-yet / never)

**Approach:**
- Before calling `startDownload`, await the probe. If reachable → proceed. If not → enter a "reconnecting…" UI state and poll the probe every interval P up to a wait-budget; when it flips reachable, proceed; if the budget elapses, set a clear `_error`.
- Add a host-unreachable → friendly-message mapping in `_mapDownloadError` as a backstop for an error that slips through mid-transfer.

**Patterns to follow:** the existing `_exporting`/`_error`/`_buildExporting` states and the overlay-export poll loop already in `download_sheet.dart`; the `_kExportTimeout`/`_kExportPollInterval` const style.

**Test scenarios:**
- Covers AE1. Given the probe is not-yet-reachable then becomes reachable, when the user starts a download, the sheet shows "reconnecting…" then proceeds to `startDownload`.
- Covers AE2. Given the probe stays unreachable past the wait-budget, the sheet shows a clear human error and never calls `startDownload`.
- Happy path: probe reachable immediately → download starts with no reconnecting state.
- Error path: a mid-transfer host-unreachable error maps to friendly copy (not raw library text).
- Edge: dismissing the sheet during the reconnecting wait cancels the poll (no leaked timer).

**Verification:** `download_sheet_test` green for all three reachability branches; manual on-device: a download right after a new match shows "reconnecting…" briefly then succeeds.

---

### U5. [app] Live-preview reachability gating

**Goal:** Start the VLC preview only when the data plane is reachable; show a "reconnecting…" status while waiting, instead of a stuck/blank surface or a hard failure.

**Requirements:** R6, R7

**Dependencies:** U3

**Files:**
- Modify: `lib/core/widgets/live_preview_view.dart` (gate `shouldStream`/VLC controller creation on reachability; add a "reconnecting…" `statusLabel` branch; resume automatically when reachable)
- Modify (if a preview test exists): preview widget test, or add one under `test/core/widgets/`

**Approach:**
- Fold reachability into the existing `shouldStream` gate: only spin up / keep the VLC controller when preview is on, the surface is visible, WiFi is connected, AND reachable. While unreachable, show a "reconnecting…" placeholder and re-check; auto-resume when reachable (mirrors the existing pause/resume + descriptor-swap logic).

**Patterns to follow:** the existing `shouldStream`, `_swapVlcController`/`_tearDownVlc`, `statusLabel` switch, and `paused` handling in `live_preview_view.dart`.

**Test scenarios:**
- Happy path: reachable → VLC controller created; statusLabel reflects live.
- Edge: unreachable → no controller created, "reconnecting…" shown; becomes reachable → controller created (auto-resume).
- Edge: preview off or surface paused → no controller regardless of reachability (existing invariant preserved).
- Test expectation note: VLC native view doesn't attach in the headless test env (existing tests assert controller lifecycle, not playback) — assert on the gate + statusLabel, not on decoded frames.

**Verification:** `flutter analyze` clean; preview gate test green; on-device: after a re-form, preview shows "reconnecting…" then resumes without a manual restart.

---

## System-Wide Impact

- **Interaction graph:** `wifi_handoff.dart` (bring-up only), `WifiService` probe (new) consumed by `download_sheet.dart` + `live_preview_view.dart`; firmware `StartP2pGroupOwner` reused by the existing `WifiDirectHandler` (no handler change).
- **Error propagation:** host-unreachable becomes a soft, retried, friendly state in the app rather than a fatal VLC/http error surfaced raw.
- **State lifecycle risks:** ensure the reconnecting-wait poll timers are cancelled on sheet dismiss / preview teardown (no leaks); firmware `Stop()` must not delete the persistent network definition (or R1/R2 regress).
- **API surface parity:** the reachability gate should apply to BOTH download and preview (U4 + U5) so behavior is consistent across the two WiFi consumers.
- **Unchanged invariants:** BLE control channel untouched; `WifiDirectGroup` proto/model shape unchanged; the live pipeline / RTSP server unchanged; the #18 burn changes untouched.

---

## Risks & Dependencies

| Risk | Mitigation |
|------|------------|
| wpa_supplicant persistent-group commands behave differently on this driver (creds not in `GROUP-STARTED` on reuse, or persistent flag unsupported) | U1 keeps the existing retry machinery; read creds from the stored network as a fallback; validate on device early before building U4/U5 atop it |
| Android does NOT auto-rejoin the saved P2P group without an app call | If validation shows this, add a single one-time join on first pairing (small addition to U2/U3 scope) — flagged in Open Questions, not assumed |
| Removing recovery (U2) regresses the genuine "OS tore down the group on background/lock" case | With a stable saved SSID the OS rejoins on its own; verify-before-action (U4/U5) covers the gap by waiting; if a real gap remains, the hybrid escalation (origin's rejected option) is the documented fallback |
| Probe target/timeout mis-tuned → false "unreachable" or slow UX | Tune on device (Open Questions); keep timeout short and wait-budget bounded with a clear error |

---

## Sources & References

- **Origin document:** [docs/brainstorms/2026-06-28-wifi-direct-stable-connection-requirements.md](docs/brainstorms/2026-06-28-wifi-direct-stable-connection-requirements.md)
- Firmware group formation: `sst-cam-firmware/src/adapters/control/wifi/wpa_supplicant/wpa-wifi-manager.cpp`
- App handoff + WiFi port: `sst-cam-app/lib/core/wifi/wifi_handoff.dart`, `lib/core/wifi/wifi_service.dart`
- Download / preview flows: `sst-cam-app/lib/features/video/playback/download_sheet.dart`, `lib/core/widgets/live_preview_view.dart`
- Config (defines the intended fixed identity): `sst-cam-firmware` `wifi-direct.json` (`/etc/sst/cam/config/wifi-direct.json` on device)
- On-device target: Jetson `sst@10.10.1.30`; phone at `10.10.1.121:<port>`
