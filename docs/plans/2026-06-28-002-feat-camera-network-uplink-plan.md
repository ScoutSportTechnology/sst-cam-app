---
title: "feat: Camera network uplink (configurable WiFi/Ethernet, separate from WiFi-Direct)"
type: feat
status: active
date: 2026-06-28
origin: docs/brainstorms/2026-06-28-camera-network-uplink-requirements.md
---

# feat: Camera network uplink (configurable WiFi/Ethernet, separate from WiFi-Direct)

> **Cross-repo plan.** Units are tagged **[firmware]** (`sst-cam-firmware`), **[app]** (`sst-cam-app`), or **[proto]** (`sst-cam-proto` submodule). Paths are repo-relative to the tagged repo. Plan lives in `sst-cam-app/docs/plans/`.

## Summary

Split the camera's networking into two independent planes: keep **BLE + WiFi-Direct (camera = GO)** for control/preview untouched, and add a **separate, user-configured internet uplink** (local WiFi STA and/or Ethernet) that carries cloud streaming. First recover the Jetson to a deliberately-provisioned wifi baseline (the NetworkManager-vs-wpa contention broke things), fix the live-preview regression on that clean baseline, then build the uplink config surface end-to-end (app Settings → BLE → firmware → persisted → RTMP over the uplink).

---

## Problem Frame

The camera must work in a field with no external network (preview/control over WiFi-Direct) **and** stream to the cloud, which needs internet. Pushing the phone's cellular over the WiFi-Direct link is infeasible on non-root Android, so the uplink is a **separate** camera connection (WiFi STA / Ethernet) the user configures. Today the app can't configure it, live preview regressed to blank/"waiting for frames", and the Jetson's wifi is in a churned, hand-hacked state (NetworkManager fighting wpa_supplicant for the radio). See origin for the full model (Sources & References).

---

## Requirements

- R1. Camera stays the WiFi-Direct GO; BLE control + WiFi-Direct preview unchanged (prior U1–U5 valid).
- R2. **Fix the live-preview regression** — connects but blank/"waiting for frames"; diagnose on a clean baseline.
- R3. App **"Network" settings section** to configure the camera's internet uplink, separate from WiFi-Direct.
- R4. Configure a **local WiFi** uplink (SSID + password) — camera joins as a normal client.
- R5. Configure the **Ethernet** port as an uplink.
- R6. **Activate/deactivate** each uplink (WiFi, Ethernet) independently.
- R7. **Static or dynamic (DHCP)** IP per uplink.
- R8. Uplink config sent **over BLE**, **persisted** on the camera (survives restarts).
- R9. **Cloud streaming (RTMP) runs over the configured uplink**, separate from the WiFi-Direct preview link.
- R10. Uplink **source is the user's choice** (phone hotspot / venue wifi / ethernet); app does not auto-manage any hotspot.

**Origin actors:** A1 (user), A2 (companion app), A3 (camera firmware)
**Origin flows:** F1 (configure uplink), F2 (field live preview), F3 (cloud streaming over uplink)
**Origin acceptance examples:** AE1 (R3–R8), AE2 (R9,R1), AE3 (R2), AE4 (R7), AE5 (R6)

---

## Scope Boundaries

- App auto-enabling/controlling the phone hotspot — out (R10). User manages it.
- Reverse-tether (phone internet over the P2P link) — out / rejected (origin).
- Camera connecting wifi to a local network *instead of* being the GO — out; uplink is a separate connection.

### Deferred to Follow-Up Work

- **Simultaneous WiFi-Direct-GO + WiFi-STA-uplink on the camera's single radio** — gated on the concurrency validation (Open Questions). Ethernet uplink is the guaranteed path for v1; a *wifi* uplink while previewing ships only if concurrency validates. Captured as U3's validation gate, not an active build assumption.
- iOS preview-plane behavior — separate from this work.

---

## Context & Research

### Relevant Code and Patterns

- **[firmware]** `src/adapters/control/wifi/wpa_supplicant/wpa-wifi-manager.cpp` — the WiFi-Direct GO (U1 persistent named group). `ip-network-configurator.hpp`, `dnsmasq-dhcp-server.hpp` — GO-side IP/DHCP. `src/app/control/ports/network-configurator.hpp` — the existing network port to extend.
- **[firmware]** `src/app/streaming/services/streaming_service/` + `src/adapters/streaming/` (`GstRtmpStreamer`) — RTMP egress; must bind/route over the uplink, not the GO.
- **[firmware]** `src/{domain,app,adapters}/config/` — JSON config load/persist (`device.hpp`, `serde/device.hpp`); the uplink config persists here.
- **[firmware]** `src/app/control/services/handlers/` — BLE command handlers (mirror for a new network-config handler); `src/main.cpp` wiring.
- **[proto]** the command/response contract (`proto/*.proto`) — add a NetworkConfig set/get message pair (mirrors `StartWifiDirect`, `SetStreamingConfig`).
- **[app]** `lib/features/settings/` (`settings_page.dart`, `streaming/`) — pattern for a new `network/` settings subsection. `lib/core/ble/` (`ble_service`, `ble_protocol`, `ble_service_impl`) — command send/encode. `lib/core/models/command.dart` — command model.
- **[deploy]** `sst-cam-firmware/deploy/install.sh` — where the deliberate wifi provisioning (NM unmanaged + dedicated wpa service + socket group) belongs.

### Institutional Learnings (today's on-device findings)

- **NetworkManager owns `wlP1p1s0` by default and fights the firmware's wpa_cli GO** (auto-connects saved wifi, scans, re-asserts STA via DBus → tears the GO down). The firmware drives wpa via the `/run/wpa_supplicant/<iface>` ctrl socket; that socket only exists while wpa runs on the iface, and it must be group `netdev` (mode 750) for user `sst-cam` to use it.
- The phone's single radio band-splits (5 GHz home wifi vs 2.4 GHz GO) and starves the P2P data path — a **test artifact** (real use = phone on cellular), but it masked the preview root cause today. Diagnose preview with the phone on cellular only.
- Firmware GO serves frames locally fine (gst rtspsrc pulled ~583 H.264 buffers/10 s), so the preview pipeline works; the break was the air/data path, entangled with the above.

### External References

- wpa_supplicant dedicated-instance + P2P GO provisioning; NetworkManager `unmanaged-devices` keyfile drop-in; Jetson/`nl80211` single-radio STA+GO concurrency — all on-device validation items (Open Questions).

---

## Key Technical Decisions

- **Two independent planes, never sharing a link.** WiFi-Direct GO (preview) and the uplink (WiFi STA / Ethernet) are separate interfaces/connections. Rationale: origin's core decision; removes the infeasible reverse-tether.
- **Dedicate the camera wifi radio to the firmware, NM out of it.** A NetworkManager `unmanaged-devices` drop-in for `wlP1p1s0` + a dedicated `wpa_supplicant` instance (its own ctrl socket, `netdev` group) provisioned in `install.sh`. Rationale: the NM-vs-wpa fight was the single biggest source of instability; the radio must have one owner.
- **Ethernet-first uplink for v1; wifi-STA uplink gated on concurrency validation.** Rationale: ethernet coexists with the GO trivially; STA+GO on one radio is unproven on this driver.
- **Uplink config is camera-persisted JSON, set/queried over BLE.** Rationale: matches the existing JSON config + BLE command pattern; survives restarts (R8).
- **RTMP binds to the uplink interface/route, not the GO subnet.** Rationale: streaming must egress via the uplink (R9).

---

## Open Questions

### Resolved During Planning

- Where does uplink config live? → camera JSON config (`src/{domain,app,adapters}/config/`), set over BLE.
- One plan or split? → one cross-repo plan, repo-tagged units; sequencing is interdependent (recover → fix preview → uplink).
- Does this replace U1–U5? → No. Camera-as-GO preview plane is kept; this is additive.

### Deferred to Implementation

- [Affects U3][Needs research] Can the Jetson radio run **WiFi-Direct GO + WiFi-STA-uplink simultaneously** (nl80211 single-radio concurrency, regdomain)? Validate on device; if no, wifi-uplink-while-previewing is deferred and ethernet is the path.
- [Affects U2][Needs research] **Live-preview regression root cause** — re-diagnose on a clean baseline (phone on cellular, NM provisioning fixed). Could be the air/data path, the dedicated-wpa GO config, or something masked by today's churn.
- [Affects U4] Exact proto schema + chunking for the NetworkConfig command/response over BLE (reuse the `ChunkedPayload` envelope if the payload is large).
- [Affects U3] Which subsystem applies the uplink on the camera (a dedicated wpa STA instance vs `systemd-networkd`/NM for the *uplink* iface vs `nmcli`), given the GO radio is firmware-owned and ethernet is separate.

---

## High-Level Technical Design

> *Illustrates the intended approach; directional guidance for review, not implementation specification.*

```
PLANE 1 (unchanged): phone --BLE--> camera (control)
                     phone <--WiFi-Direct (camera=GO, wlP1p1s0)--> camera (live preview, no internet)

PLANE 2 (new): camera uplink for internet/cloud streaming, SEPARATE interface:
   ethernet (eth0)            ──┐
   or wifi-STA (joins a net) ──┤──> camera default route ──> RTMP egress ──> cloud
                                │
   user configures in app Settings→Network ──BLE(NetworkConfig)──> firmware persists+applies

Radio ownership on the camera:
   wlP1p1s0 = firmware-owned (dedicated wpa, NM unmanaged) = WiFi-Direct GO  [always]
   uplink   = eth0 (always works)  OR  wlP1p1s0-as-STA (ONLY if single-radio GO+STA validates)
```

---

## Implementation Units

### U1. [firmware/deploy] Deliberate wifi-radio provisioning (NM out, dedicated wpa) + recover baseline

**Goal:** Make the camera wifi radio firmware-owned and stable: NetworkManager unmanaged for `wlP1p1s0` + a dedicated `wpa_supplicant` instance (own ctrl socket, `netdev` group) so the WiFi-Direct GO forms reliably with no NM contention. Provisioned in `install.sh` so it survives reboots and replaces today's manual hack.

**Requirements:** R1 (preconditions R2)

**Dependencies:** None (do first — everything else needs a working baseline)

**Files:**
- Modify: `deploy/install.sh` (add: NM `unmanaged-devices` keyfile drop-in for `wlP1p1s0`; install a `wpa_supplicant@`-style systemd unit or drop-in for the dedicated P2P instance with `ctrl_interface=DIR=/run/wpa_supplicant GROUP=netdev`; ensure socket group/perms)
- Create: `deploy/` config assets (the NM drop-in `.conf`, the dedicated `wpa_supplicant` conf, the systemd unit)
- Modify (if needed): `src/adapters/control/wifi/wpa_supplicant/wpa-wifi-manager.cpp` — confirm it targets the dedicated socket; keep `DisableStaNetworks`/persistent-group logic
- Test: on-device validation (HW-bound; container can't run it)

**Approach:**
- NM drop-in: `[keyfile] unmanaged-devices=interface-name:wlP1p1s0`.
- Dedicated `wpa_supplicant` systemd service for `wlP1p1s0` with the ctrl socket in `/run/wpa_supplicant` group `netdev`, P2P config (`device_name=sst-cam-NNNN`, regdomain set to a real country — today's `country 00` limits the radio).
- `install.sh` applies both idempotently; document that the camera wifi is dedicated to WiFi-Direct.
- Recover the currently-churned device by running the new provisioning.

**Patterns to follow:** existing `deploy/install.sh` structure (identity/deps/service steps); the manual setup proven on-device today (dedicated wpa + chgrp netdev).

**Test scenarios:**
- On-device: after `install.sh` + reboot, `wlP1p1s0` is NM-unmanaged, the dedicated wpa socket exists (`root:netdev`, `sst-cam` can read), firmware forms the GO with no "Permission denied".
- On-device: GO SSID is the stable `DIRECT-XY-sst-cam-NNNN`; survives a firmware restart (reuse).
- Edge: no saved home wifi present → GO still forms (no NM idling the radio).
- Edge: regdomain set to a real country (not `00`); GO on a valid channel.

**Verification:** Fresh boot → firmware forms the GO unattended; no NM/wpa contention in the journal; socket reachable by `sst-cam`.

---

### U2. [firmware/app] Diagnose + fix the live-preview regression (clean baseline)

**Goal:** Restore live preview rendering in the app (R2), diagnosed on the U1 clean baseline with the phone on cellular only (no band-split confound).

**Requirements:** R2

**Dependencies:** U1

**Files:**
- Investigate/Modify: `src/adapters/streaming/gst_rtsp/gst-rtsp-app-stream-server.cpp` (appsrc feed/size guard), `src/app/pipeline/services/orchestrator/pipeline-orchestrator.cpp` (stream_sink push), `src/app/streaming/services/streaming_service/` (RTSP start/feed)
- Investigate/Modify (app): `lib/core/widgets/live_preview_view.dart` (VLC start/gating), `lib/core/wifi/wifi_service_impl.dart` (preview descriptor)
- Test: on-device end-to-end (phone cellular only); add a firmware-side RTSP self-pull check to the validation runbook

**Execution note:** Characterization-first — capture the actual on-device failure (firmware RTSP self-pull works? phone reaches `:8554`? VLC error?) on the clean baseline before changing code; today's root cause was never isolated (confounded by NM churn + band split).

**Approach:**
- Reproduce on the clean baseline; confirm the firmware serves frames locally (gst rtspsrc self-pull), the phone (cellular only) joins the GO + gets DHCP + reaches `:8554`, and where VLC stalls.
- Fix the actual root cause (candidate areas above). Do NOT assume — the prior session's hypotheses were confounded.

**Test scenarios:**
- Covers AE3. On-device (phone cellular only): connect → preview renders moving frames within a few seconds.
- Integration: firmware RTSP self-pull yields buffers (pipeline healthy) AND the phone's VLC connection stays ESTAB with bytes flowing.
- Edge: re-form the group (new match) → preview recovers (ties to the lean recovery U2–U5).

**Verification:** Live preview shows real frames on device with the phone on cellular; no "waiting for frames" stall.

---

### U3. [firmware] Camera uplink management (WiFi STA + Ethernet), separate from the GO

**Goal:** A firmware capability to bring up an internet **uplink** — Ethernet and/or a WiFi STA — independent of the WiFi-Direct GO, with enable/disable + static/dynamic IP, persisted in config.

**Requirements:** R4, R5, R6, R7, R8, R9

**Dependencies:** U1

**Files:**
- Create: `src/domain/network/models/uplink-config.hpp` (+ formatter) — wifi creds, ethernet, per-iface enabled + ip-mode (dhcp/static) + static addr
- Create: `src/app/network/services/uplink-manager/` (port + service) — apply/teardown an uplink iface
- Create: `src/adapters/control/network/` adapter(s) — bring up eth0 (DHCP/static) and a WiFi-STA join (its own mechanism, NOT the GO's wpa instance/iface)
- Modify: `src/{domain,app,adapters}/config/` — persist `uplink-config` in the device JSON
- Modify: `src/app/streaming/services/streaming_service/` — ensure RTMP egress uses the uplink route (R9)
- Modify: `src/main.cpp` — wire the uplink manager
- Test: `tests/network/uplink_manager.test.cpp` (config apply/persist logic, mockable parts); on-device for real iface bring-up

**Approach:**
- Ethernet uplink: configure `eth0` DHCP or static; default route via it.
- WiFi-STA uplink: **gated** on the single-radio concurrency validation (Open Questions). If validated, a STA join on `wlP1p1s0` concurrent with the GO; if not, ethernet-only for v1 and surface "wifi uplink unavailable on this hardware".
- Persist `uplink-config`; apply on boot + on config change.
- RTMP binds to / routes via the uplink, never the GO subnet.

**Test scenarios:**
- Happy: ethernet uplink, DHCP → camera gets an address + default route; RTMP egress uses it.
- Happy: ethernet uplink, static IP → camera uses the configured static addr (Covers AE4).
- Edge: both uplinks configured, WiFi disabled → only ethernet active (Covers AE5).
- Error: wifi creds wrong → join fails gracefully, reported back (no crash, GO unaffected).
- Integration: enabling an uplink does NOT disturb the WiFi-Direct GO / live preview.

**Verification:** With ethernet plugged + configured, the camera reaches the internet over it while the GO + preview keep working; config persists across restart.

---

### U4. [proto/firmware/app] NetworkConfig command over BLE (set/get uplink config)

**Goal:** A BLE command/response contract to set and read the camera's uplink config, wired into the firmware handler and the app BLE layer.

**Requirements:** R3, R8

**Dependencies:** U3 (firmware applies it), independent of U5

**Files:**
- Create/Modify: **[proto]** `proto/*.proto` — `SetNetworkConfig` / `GetNetworkConfig` request+response (wifi creds, ethernet, per-iface enabled, ip-mode, static addr); regenerate bindings (`just gen-proto`)
- Create: **[firmware]** `src/app/control/services/handlers/network.handler.{hpp,cpp}` — handle set/get, call the uplink manager + persist
- Modify: **[firmware]** `src/main.cpp` / dispatcher wiring
- Create/Modify: **[app]** `lib/core/models/network_config.dart` (view model), `lib/core/ble/ble_protocol.dart` + `ble_service_impl.dart` (encode/decode + send), `lib/core/models/command.dart`
- Test: **[firmware]** `tests/control/network_handler.test.cpp`; **[app]** `test/core/ble/` network-config encode/decode + a `_ControlledBleService` round-trip

**Approach:**
- Mirror the existing `StartWifiDirect` / `SetStreamingConfig` command pattern (proto → handler → dispatcher; app: command model → ble_protocol encode → ble_service send).
- Set persists + applies (via U3); Get returns current config + uplink status (connected/failed, current IP).
- Use the `ChunkedPayload` envelope if the payload exceeds a single BLE write.

**Test scenarios:**
- Happy (firmware): SetNetworkConfig → uplink manager applied + config persisted; GetNetworkConfig returns it.
- Happy (app): encode a config → bytes match proto; decode a GetNetworkConfig response → view model populated.
- Error: malformed/invalid config (bad IP) → handler rejects with a clear status; app surfaces it.
- Integration: app sends SetNetworkConfig over a controlled BLE service → firmware handler invoked with the right fields.

**Verification:** App can set + read the camera's uplink config over BLE; firmware persists + applies it.

---

### U5. [app] Settings → Network UI

**Goal:** A "Network" section in app Settings to configure the camera's uplink — local WiFi (SSID/password), Ethernet, enable/disable each, static/dynamic IP — and push it over BLE; show uplink status.

**Requirements:** R3, R4, R5, R6, R7, R10

**Dependencies:** U4

**Files:**
- Create: `lib/features/settings/network/network_settings_page.dart` + `network_settings_state.dart` (Riverpod)
- Modify: `lib/features/settings/settings_page.dart` — add the Network entry
- Test: `test/features/settings/network/network_settings_test.dart`

**Approach:**
- Form: WiFi (SSID + password, enable toggle, IP mode dhcp/static + static fields), Ethernet (enable toggle, IP mode + static fields). Validate IPs.
- Save → send SetNetworkConfig (U4) over BLE; reflect Get status (connected/failed, current IP).
- Copy makes clear the user manages their own hotspot; the app only configures which network the camera joins (R10).

**Patterns to follow:** `lib/features/settings/streaming/` (existing settings subsection + BLE-backed config form).

**Test scenarios:**
- Covers AE1. Enter venue wifi SSID/password, enable, Save → app sends a SetNetworkConfig with those fields.
- Happy: toggle Ethernet on, set static IP → config reflects it; invalid IP → inline validation error, no send.
- Edge: deactivate WiFi while Ethernet on → config sent with wifi disabled.
- Widget: status area shows "connected / IP" vs "failed" from a GetNetworkConfig response.

**Verification:** From the app, a user configures + activates a WiFi/Ethernet uplink with IP settings; status reflects the camera's actual uplink.

---

### U6. [firmware] Cloud streaming egresses over the uplink

**Goal:** Ensure RTMP cloud streaming uses the configured uplink (ethernet/wifi-STA), never the WiFi-Direct GO subnet, so streaming works while preview runs on WiFi-Direct.

**Requirements:** R9

**Dependencies:** U3

**Files:**
- Modify: `src/app/streaming/services/streaming_service/` + `src/adapters/streaming/` (`GstRtmpStreamer`) — bind/route egress via the uplink iface/route
- Test: `tests/streaming/` (route/bind selection logic where mockable); on-device end-to-end RTMP

**Approach:**
- RTMP connects out over the uplink default route (ethernet or wifi-STA), not 192.168.49.x.
- If no uplink is up, streaming reports "no internet uplink" rather than failing opaquely.

**Test scenarios:**
- Integration (on-device): with an ethernet uplink, start a cloud stream → RTMP reaches the cloud while WiFi-Direct preview keeps running (Covers AE2).
- Error: no uplink configured/up → start-stream returns a clear "no uplink" status.
- Edge: uplink drops mid-stream → graceful failure/report (no GO/preview impact).

**Verification:** Cloud stream egresses over the uplink concurrently with WiFi-Direct preview; clear error when no uplink.

---

## System-Wide Impact

- **Interaction graph:** new NetworkConfig BLE command (dispatcher + handler) alongside existing commands; uplink manager touches OS network state (eth0/wifi-STA) separate from the GO; streaming egress route changes.
- **Error propagation:** uplink/join failures must surface as clear command statuses to the app, never crash the firmware or disturb the GO/preview.
- **State lifecycle risks:** persisted uplink config must apply cleanly on boot; partial/failed apply must not brick the radio or the GO.
- **API surface parity:** the GO/preview plane (U1–U5 prior work) is unchanged; only additive.
- **Unchanged invariants:** WiFi-Direct GO SSID/model, BLE control channel, preview RTSP pipeline — all preserved; the uplink is a strictly separate interface.

---

## Risks & Dependencies

| Risk | Mitigation |
|------|------------|
| Single-radio GO+STA concurrency unsupported on the Jetson | Ethernet-first uplink for v1 (always works); wifi-STA uplink gated on validation (U3), surfaced as "unavailable" if not |
| NetworkManager still contends for the radio | U1 makes `wlP1p1s0` NM-unmanaged + dedicated wpa, provisioned in `install.sh`, validated on a fresh boot |
| Preview root cause still elusive | U2 is characterization-first on a clean baseline (phone cellular), with a firmware RTSP self-pull check to localize fault |
| Uplink iface management mechanism unclear (wpa vs networkd vs nmcli for the *uplink*) | Open Question resolved early in U3; ethernet path is simple and unblocks v1 |
| BLE payload size for network config | Reuse the `ChunkedPayload` envelope (existing pattern) |

---

## Sources & References

- **Origin document:** [docs/brainstorms/2026-06-28-camera-network-uplink-requirements.md](docs/brainstorms/2026-06-28-camera-network-uplink-requirements.md)
- Companion preview/SSID plane: [docs/plans/2026-06-28-001-feat-wifi-direct-stable-connection-plan.md](docs/plans/2026-06-28-001-feat-wifi-direct-stable-connection-plan.md) (U1–U5 kept)
- Firmware: `sst-cam-firmware/src/adapters/control/wifi/wpa_supplicant/`, `src/app/streaming/`, `deploy/install.sh`
- App: `sst-cam-app/lib/features/settings/`, `lib/core/ble/`
- On-device: Jetson `sst@10.10.1.30`
