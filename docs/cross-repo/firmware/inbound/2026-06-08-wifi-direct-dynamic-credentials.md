---
date: 2026-06-08
target_repo: app
source_repo: firmware
status: responded
kind: interaction-change
related: docs/plans/2026-06-08-001-refactor-app-source-of-truth-firmware-plan.md
---

# WiFi Direct: app must consume camera-generated credentials (autonomous P2P GO)

## Context (firmware side)

During planning of the app-as-source-of-truth firmware refactor, we decided the camera will form a **real autonomous WiFi Direct P2P group-owner** (wpa_supplicant `p2p_group_add`, non-persistent) rather than a fixed-credential soft-AP stand-in.

A hard constraint of the Wi-Fi P2P spec: an autonomous (non-persistent) group-owner **generates its own random SSID and passphrase** — they cannot be pinned/pre-shared. You can only get fixed creds with a manually configured *persistent* group, which we are intentionally not doing.

The firmware sidesteps this by **reading back the generated credentials and reporting them to the app over BLE** in `WifiDirectGroupResponse{ssid, psk, group_owner_ip, preview_port, download_port, role}`. So the credentials are dynamic per session, delivered over the BLE control channel.

## What firmware assumes / decided

- **Trigger:** the camera forms the group in response to `StartWifiDirectCommand`. The app is expected to send `StartWifiDirect` immediately after `GetDeviceInfo` so the link comes up automatically from the user's perspective.
- The camera replies with `WifiDirectGroupResponse` carrying the **actual generated** `ssid` + `psk` (not any pre-agreed constant), `group_owner_ip` (`192.168.49.1`), `preview_port`, `download_port`, and `role` (`"GO"`).
- The phone then joins the WiFi group using *those* credentials, opens `rtsp://<group_owner_ip>:<preview_port>/preview`, and uses `<group_owner_ip>:<download_port>` for HTTP downloads.
- RTMP egress stays on cellular while the WiFi Direct group serves preview/downloads (the camera handles its own routing).

## Ask for the app repo

1. Confirm the app **does not assume a fixed/known SSID or passphrase** for the camera's WiFi Direct group, and instead joins using the dynamic `ssid`/`psk` returned in `WifiDirectGroupResponse`. If the current app hard-codes or expects stable creds, plan + implement the change to read them per session.
2. Confirm the app's connect flow sends `StartWifiDirect` right after `GetDeviceInfo` (vs. waiting for a user action), so the experience is "BLE connects → WiFi Direct comes up automatically."
3. Confirm the platform (iOS/Android) can **programmatically join an arbitrary WiFi network from credentials received at runtime** — some OSes restrict this. If it needs user-prompted join, tell us; it may affect how "automatic" the bring-up can be and whether we need to surface the creds differently.

## Acceptance / what "aligned" looks like

- App joins the camera's group using runtime-delivered `ssid`/`psk`, with no compile-time credential assumption.
- App sends `StartWifiDirect` automatically post-`GetDeviceInfo`.
- Preview + download endpoints are derived from `WifiDirectGroupResponse`, not hard-coded.

## Response (app session — 2026-06-08)

### Q1 — No hard-coded credentials: confirmed

The app does not assume any fixed SSID or passphrase. `WifiDirectGroup` holds
`{ssid, psk, groupOwnerIp, previewPort, downloadPort, role}` as runtime fields.
`WifiServiceImpl.connectGroup` will send `StartWifiDirectCommand` over BLE, read
`WifiDirectGroupResponse`, and join the group with those exact credentials. No
compile-time constants.

### Q2 — Automatic `StartWifiDirect` post-`GetDeviceInfo`: confirmed

`WifiHandoffController` fires `connectGroup(deviceId)` the moment
`CameraConnectionState.connected` fires, which is immediately after `GetDeviceInfo`
succeeds. The user experience is: BLE pairs → WiFi Direct group comes up → preview
available. No user-facing "Connect WiFi" step.

### Q3 — Platform capability

| Platform | Verdict |
|---|---|
| **Android** | ✅ `WifiP2pManager.connect()` — programmatic, no user prompt |
| **iOS** | ❌ No public WiFi Direct P2P API. `NEHotspotConfiguration` joins regular APs only, not P2P groups |

**Decision for this release:** WiFi Direct (preview + downloads) is **Android-only**.
iOS will show a graceful placeholder in the session screen. Firmware does **not** need
a soft-AP fallback mode to ship this release.

iOS is tracked as a future track: when prioritised, the likely path is a concurrent
soft-AP from firmware + `NEHotspotConfiguration` on the app side. We will open a new
cross-repo request when that track starts.
