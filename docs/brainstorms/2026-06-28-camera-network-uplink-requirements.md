---
date: 2026-06-28
topic: camera-network-uplink
---

# Camera Network Uplink (separate from the WiFi-Direct preview link)

## Summary

Give the camera a **configurable internet uplink** — a "Network" section in the app to set up the camera's **local WiFi and/or Ethernet** (enable/disable, static or dynamic IP) — that is **separate** from the BLE + WiFi-Direct control/preview link. Cloud streaming runs over that uplink; live preview and control stay on WiFi-Direct (camera = group owner, unchanged). Also restore the **live preview, which is currently not rendering in the app**.

---

## Problem Frame

The camera must be usable in a field with **no external network**: the phone controls it over BLE and watches live preview over **WiFi-Direct** (camera is the group owner) — no internet required. But **cloud live-streaming (RTMP) is fundamental**, and that needs the camera to reach the internet.

The natural-but-wrong idea is to push the phone's cellular internet *up* to the camera over the WiFi-Direct link. That is technically infeasible on a normal (non-rooted) phone — Android does not route a phone's cellular onto a WiFi-Direct group, and an app can't NAT it without root or a fragile VPN-forward. A long on-device session confirmed how brittle conflating the two planes is (NetworkManager fighting the radio, single-radio band splits, a broken preview data path).

The resolution: keep the two **completely separate**. The WiFi-Direct link is for control + preview only. The camera's **internet uplink is its own connection** — local WiFi (the camera joins a network as a normal client) or Ethernet — configured by the user in the app. When the source is a phone hotspot, the camera simply joins it like any wifi network (the easy, standard path; no reverse-tether). Today the app has no way to configure this, and live preview regressed and no longer shows.

This complements (does not replace) the prior `2026-06-28-wifi-direct-stable-connection` work: the camera stays the WiFi-Direct GO, and U1–U5 remain valid.

---

## Actors

- A1. User: configures the camera's network uplink; manages their own phone hotspot if used as the uplink source.
- A2. Companion app (Flutter): control over BLE, live preview over WiFi-Direct, and a new Network settings UI that pushes uplink config to the camera.
- A3. Camera firmware (Jetson): WiFi-Direct GO for the phone; manages its own internet uplink (WiFi STA and/or Ethernet) per the pushed config; streams RTMP over that uplink.

---

## Key Flows

- F1. Configure the camera uplink
  - **Trigger:** user opens app → Settings → Network.
  - **Actors:** A1, A2, A3
  - **Steps:** user sets a local WiFi (SSID + password) and/or the Ethernet port → toggles each on/off → chooses static or dynamic IP → app sends the config to the camera over BLE → camera persists + applies it.
  - **Outcome:** the camera has a configured, activatable internet uplink, independent of the WiFi-Direct link.
  - **Covered by:** R3–R8

- F2. Field live preview (no internet)
  - **Trigger:** user connects to the camera in a field.
  - **Actors:** A1, A3
  - **Steps:** phone connects over BLE (control) + WiFi-Direct (camera GO) → live preview streams over WiFi-Direct.
  - **Outcome:** preview + control work with zero external network.
  - **Covered by:** R1, R2

- F3. Cloud streaming over the uplink
  - **Trigger:** user starts a cloud live-stream.
  - **Actors:** A1, A3
  - **Steps:** camera streams RTMP out over its configured uplink (the user's phone hotspot, another hotspot, venue wifi, or ethernet) — while the phone still previews/controls over WiFi-Direct.
  - **Outcome:** the camera live-streams to the cloud; the phone's preview link is unaffected.
  - **Covered by:** R9, R10

---

## Requirements

**Control + preview plane (existing — keep)**
- R1. The camera remains the **WiFi-Direct group owner**; the phone controls it over BLE and watches live preview over WiFi-Direct. No internet required for this plane. (Carries the prior `wifi-direct-stable-connection` model + U1–U5.)
- R2. **Live preview must actually render frames in the app.** It currently regressed (connects but shows blank / "waiting for frames"); this must be diagnosed on a clean baseline and fixed.

**Internet / uplink plane (new)**
- R3. The app has a **"Network" settings section** to configure the camera's internet uplink, separate from the WiFi-Direct link.
- R4. Configure a **local WiFi** uplink: SSID + password (the camera joins it as a normal client).
- R5. Configure the **Ethernet** port as an uplink.
- R6. **Activate / deactivate** each uplink (WiFi, Ethernet) independently.
- R7. Each uplink supports **static or dynamic (DHCP) IP** configuration.
- R8. Uplink config is sent to the camera **over BLE** and **persisted** on the camera (survives restarts).
- R9. **Cloud streaming (RTMP) runs over the configured uplink**, fully separate from the WiFi-Direct preview link.
- R10. The uplink **source is the user's choice** — their phone hotspot, another phone's hotspot, venue wifi, or ethernet. The app does **not** control or auto-enable any hotspot; it only configures which network the camera joins.

---

## Acceptance Examples

- AE1. **Covers R3–R8.** Given the user enters a venue wifi SSID + password in Settings → Network and activates it, when saved, the camera joins that network and (AE-linked) streaming uses it.
- AE2. **Covers R9, R1.** Given a field with the user's phone hotspot on, when the user previews over WiFi-Direct AND starts a cloud stream, preview keeps running over WiFi-Direct while the stream goes out over the hotspot uplink.
- AE3. **Covers R2.** Given the phone is connected to the camera, when the user opens live preview, it renders moving frames (not a blank / stuck "waiting for frames").
- AE4. **Covers R7.** Given the user sets a static IP for the Ethernet uplink, when applied, the camera uses that static address.
- AE5. **Covers R6.** Given both WiFi and Ethernet uplinks are configured, when the user deactivates WiFi, the camera uses only Ethernet for internet.

---

## Success Criteria

- Live preview renders again over WiFi-Direct (R2 fixed).
- The user can configure, IP-set, and activate/deactivate a WiFi and/or Ethernet uplink entirely from the app.
- The camera streams to the cloud over the configured uplink while live preview continues over WiFi-Direct.
- Field case works: with the user's phone hotspot on, the camera joins it as a normal client and streams — no reverse-tether, no app-managed hotspot.
- ce-plan can implement without inventing the two-plane split, the config surface, or the streaming/uplink relationship.

---

## Scope Boundaries

- **App auto-enabling / controlling the phone's hotspot** — out. The user manages their own hotspot; the app only configures which network the camera joins.
- **Reverse-tether** (routing the phone's cellular over the WiFi-Direct link) — out / rejected; the separate-uplink model removes the need.
- **Camera connecting its wifi to a local network *instead of* being the GO** — out; the WiFi-Direct GO link is preserved; the uplink is a separate connection.

### Deferred to Follow-Up Work

- **Simultaneous WiFi-Direct-GO + WiFi-STA on the camera's single radio** — depends on Jetson radio concurrency (see Outstanding Questions). Ethernet uplink is the guaranteed path; a wifi uplink *while previewing* is gated on that validation.
- **iOS** — WiFi-Direct support differs on iOS; out for now.

---

## Key Decisions

- **Two separate planes.** Control + live preview = BLE + WiFi-Direct (camera GO, kept). Internet/streaming = a configurable WiFi/Ethernet uplink. They never share a link.
- **Camera stays the WiFi-Direct GO.** Nothing from the prior model or U1–U5 is replaced; this is additive.
- **User owns the uplink choice.** The app exposes config (creds, ethernet, IPs, on/off) but does not manage the user's hotspot — sidestepping the infeasible phone-internet-over-P2P sharing.
- **Phone-hotspot-as-uplink is just a normal STA join**, not a reverse-tether — which is why this resolves the earlier dead-end.

---

## Dependencies / Assumptions

- BLE (the existing control channel) carries the network-uplink config to the camera.
- Camera-side WiFi/Ethernet management needs a **deliberate provisioning setup** (the WiFi-Direct GO plus a managed STA/ethernet uplink), avoiding the NetworkManager-vs-firmware radio contention that broke things on-device today.
- The live-preview regression (R2) is assumed fixable once tested on a **clean device baseline** (today's diagnosis was confounded by heavy device churn + the phone's single-radio band split while on home wifi).

---

## Outstanding Questions

### Deferred to Planning

- [Affects deferred uplink][Needs research] Can the Jetson's single wifi radio run a **WiFi-Direct GO and a WiFi-STA uplink simultaneously** (STA+GO concurrency on this driver/regdomain)? If not, a wifi uplink and live preview can't coexist on one radio (ethernet uplink avoids it).
- [Affects R2][Needs research] Root cause of the **live-preview regression** — diagnose on a clean baseline (rule out the NetworkManager/wpa churn + the phone band-split that masked it today).
- [Affects R8][Technical] Config transport + schema over BLE for the network settings; how the camera persists + applies WiFi/Ethernet config (and which subsystem owns it vs NetworkManager).
- [Affects R3] iOS behavior for the WiFi-Direct preview plane (separate from this uplink work).
