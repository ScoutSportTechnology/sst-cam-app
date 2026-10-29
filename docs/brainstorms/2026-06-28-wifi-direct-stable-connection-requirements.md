---
date: 2026-06-28
topic: wifi-direct-stable-connection
---

# WiFi-Direct Stable Connection

## Summary

Give the camera's WiFi-Direct group **one stable persistent identity** (same SSID/PSK across every re-form) and move the app to a **lean "verify, don't drive"** model — it checks reachability before a WiFi action and waits if not ready, instead of running timer-based reconnects. Result: live preview and downloads survive every group re-form.

---

## Problem Frame

The camera (Jetson firmware) is the WiFi-Direct P2P **group owner**; the phone joins as a client for the data plane — live RTSP preview and HTTP downloads of recordings/overlay exports. BLE is the always-stable control channel; WiFi Direct carries the data.

The firmware forms a **fresh autonomous P2P group on every formation** (`sst-cam-firmware/src/adapters/control/wifi/wpa_supplicant/wpa-wifi-manager.cpp`, bare `P2P_GROUP_ADD`), so wpa_supplicant mints a **new random SSID + passphrase each time** — even though `wifi-direct.json` already defines a fixed identity that the code ignores. Every re-form (starting a new match, a firmware restart, a transient drop) is therefore a network the phone has never seen: it must rediscover and rejoin, and any HTTP download attempted right after fails with "no route to host."

The app compounded this. `sst-cam-app/lib/core/wifi/wifi_handoff.dart` did reactive, timer-based recovery that re-formed the group on transient wifi-state blips. Because each re-form minted a new SSID that kicked the phone, the recovery's own re-form looked like a fresh drop and re-fired — a self-sustaining flap (a new SSID every ~20–30 s, the phone never holding a route). On-device traces confirmed: BLE solid throughout, group re-forming repeatedly, phone unreachable, downloads failing. The cost is intermittent, confusing breakage of the two things the WiFi link exists for — preview and downloads — most visibly right after a new match or an overlay burn.

---

## Actors

- A1. Companion app (Flutter, Android): controls the camera over BLE; consumes preview + downloads over WiFi.
- A2. Camera firmware (Jetson): WiFi-Direct group owner; serves RTSP preview and the HTTP download server.
- A3. Phone OS WiFi stack: joins and auto-rejoins saved WiFi-Direct networks, independent of the app.

---

## Key Flows

- F1. Bring-up
  - **Trigger:** BLE connects to a camera.
  - **Actors:** A1, A2, A3
  - **Steps:** app requests the group over BLE → firmware ensures the persistent group is up and returns its stable credentials → phone joins the saved network.
  - **Outcome:** phone is on a known, stable WiFi-Direct network; data plane reachable.
  - **Covered by:** R1, R3, R6

- F2. Verify-before-action
  - **Trigger:** user starts live preview or a download.
  - **Actors:** A1, A3
  - **Steps:** app checks the camera data plane is reachable → if reachable, proceed → if not, show a "reconnecting…" state and poll until reachable or a bounded timeout elapses.
  - **Outcome:** the action runs only once the link is actually usable; otherwise a clear error.
  - **Covered by:** R6, R7

- F3. Re-form survival
  - **Trigger:** the group drops and re-forms (new match, restart, transient drop).
  - **Actors:** A2, A3
  - **Steps:** firmware re-forms with the **same** SSID/PSK → phone OS auto-rejoins the saved network → the next action's reachability check passes.
  - **Outcome:** a re-form is invisible to the user; no re-pairing, no broken download.
  - **Covered by:** R1, R2, R4, R5

---

## Requirements

**Firmware — stable WiFi identity**
- R1. The camera forms or reuses a **persistent** WiFi-Direct group such that its SSID and passphrase are identical across every formation, within a session and across firmware restarts — never a new random network per re-form.
- R2. A repeated request to bring the group up **reuses the existing/persistent group** rather than tearing it down and minting a new identity.
- R3. The WiFi credentials the firmware reports over BLE are the **stable** persistent-group credentials, so the app and phone always target the same network.

**App — lean, verify-don't-drive recovery**
- R4. The app runs **no periodic or timer-based WiFi reconnect loop** and does not re-form the group in response to transient wifi-state transitions.
- R5. Rejoining the saved network is **owned by the phone OS**; the app does not drive WiFi reconnection.
- R6. Before any WiFi-dependent action (start live preview, start a download), the app **verifies the camera data plane is reachable**.
- R7. When the reachability check fails, the app **waits — polling reachability — in a visible "reconnecting…" state up to a bounded timeout**, then surfaces a clear, actionable error. It must not fail hard on the first raw connection error.

---

## Acceptance Examples

- AE1. **Covers R6, R7.** Given the phone has not yet rejoined the network after a re-form, when the user taps download, the app shows "reconnecting…" and automatically proceeds with the download once the camera becomes reachable.
- AE2. **Covers R7.** Given the camera stays unreachable past the timeout, when the user taps download, the app shows a clear, human error (not the raw "no route to host … cannot be solved by the library" text).
- AE3. **Covers R1, R3.** Given a new match triggers a group re-form, when the phone rejoins, it connects to the **same** SSID without the user re-pairing or re-entering credentials.
- AE4. **Covers R4.** Given a brief wifi-state blip while BLE stays connected, the app issues **no** group re-form (no new SSID).

---

## Success Criteria

- A download or preview attempted after a new match, an overlay burn, or any group re-form completes without "no route to host."
- The WiFi SSID never changes across re-forms — the phone sees one saved network for the camera, like it sees one BLE device.
- No reconnect storm: group formations do not recur on transient blips (verifiable in the firmware journal — at most one formation per genuine bring-up).
- ce-plan can implement without having to invent the recovery model or the stable-identity contract.

---

## Scope Boundaries

- **SoftAP / iOS data-plane support** — excluded. The decision is persistent P2P (Android-only data plane); iOS preview/download stays unavailable for now.
- **Firmware-driven active health-checks or reconnect logic** — excluded. Recovery responsibility moves to the phone OS + app verify-before-action, not new firmware monitoring.
- **BLE health-check** — out. BLE proved stable; verify-before-action is WiFi-only.
- **Burn CPU contention** (the #18 x264 thread-cap / nice) — separate concern, already addressed.
- **The interim cooldown recovery** currently on the branch — to be **removed/superseded** by R4–R5, not kept alongside.

---

## Key Decisions

- **Persistent P2P group over SoftAP:** smallest change, keeps the existing WiFi-Direct architecture and connection code, lowest risk for the current Android demo. SoftAP (which would also unlock iOS) is deferred.
- **Lean "verify, don't drive" over active recovery:** a stable saved SSID lets the phone OS auto-rejoin, so app-driven recovery is unnecessary — and it was the source of the flap. The app's role shrinks to verifying reachability before it needs the link.

---

## Dependencies / Assumptions

- Assumes wpa_supplicant on JetPack 7.2 / this radio supports a persistent P2P group that preserves a stable SSID/PSK across re-invocations. **Needs on-device validation.**
- Assumes the phone OS auto-reconnects to a saved WiFi-Direct network without app intervention (the premise of the lean model).
- The cooldown fix already shipped on `feat/phase-d-overlay-multicam` is an interim stopgap; this design replaces it.

---

## Outstanding Questions

### Deferred to Planning

- [Affects R1, R2][Needs research] Exact wpa_supplicant mechanism for a persistent P2P group with stable credentials on this radio (e.g. `P2P_GROUP_ADD persistent` / a stored persistent-group network id, and how `GROUP-STARTED` creds are obtained on reuse).
- [Affects R3][Needs research] Whether the stable SSID can be a human-friendly value or must remain wpa_supplicant's `DIRECT-xx-…` form (P2P naming) but simply stable across re-forms.
- [Affects R6, R7][Technical] What the reachability probe is (TCP connect vs HTTP HEAD against the download/preview server) and the concrete timeout / poll-interval values.
- [Affects R5][Technical] Whether the Android WiFi-Direct client API auto-rejoins a saved P2P group without an explicit app re-connect call, or needs a one-time "join" that the OS then persists.
