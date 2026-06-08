---
date: 2026-06-08
status: ready-for-planning
tags: [wifi-direct, p2p, android, ios, credentials, firmware-response]
related_cross_repo: docs/cross-repo/firmware/external/2026-06-08-wifi-direct-dynamic-credentials.md
---

# WiFi Direct dynamic credentials — app-side requirements

Response to the firmware team's co-development request
(`docs/cross-repo/firmware/external/2026-06-08-wifi-direct-dynamic-credentials.md`).

## Background

The firmware will form a real autonomous WiFi Direct P2P group (not a fixed-credential
soft-AP). Credentials are randomly generated per session and delivered to the app over
BLE in `WifiDirectGroupResponse`. This document confirms the app team's alignment on
the firmware's three questions and records the iOS decision.

## Decisions (response to firmware)

### Q1 — No hard-coded SSID / passphrase

**Confirmed. The app does not hard-code WiFi credentials.**

The `WifiDirectGroup` model (`lib/core/models/wifi.dart`) already holds
`{ssid, psk, groupOwnerIp, previewPort, downloadPort, role}` as runtime fields. The
model was designed from the start to accept firmware-delivered credentials.

`WifiServiceImpl.connectGroup` currently returns a hardcoded mock (`DIRECT-MOCK-SST`)
as a placeholder stub. The real implementation will send `StartWifiDirectCommand` over
BLE, receive `WifiDirectGroupResponse`, and join the group using those credentials —
no compile-time constants involved.

### Q2 — Timing: `StartWifiDirect` is sent automatically after BLE connects

**Confirmed. No user action is needed.**

`WifiHandoffController` (`lib/core/wifi/wifi_handoff.dart`) watches
`connectionStateProvider` and fires `wifi.connectGroup(deviceId)` the moment BLE
transitions to `CameraConnectionState.connected`. That event fires after
`GetDeviceInfo` succeeds and the link is fully established. The user experience is:
> BLE pairs → WiFi Direct group comes up → preview available

No explicit "Connect WiFi" button or user step is required.

### Q3 — Platform capability to join the group programmatically

**Android: confirmed. iOS: Android-only for this release — iOS deferred.**

| Platform | API | Status |
|---|---|---|
| Android | `WifiP2pManager.connect()` | Programmatic, no user prompt for a trusted device. Full P2P support. ✓ |
| iOS | No public API for WiFi Direct P2P | iOS cannot join a P2P group programmatically. `NEHotspotConfiguration` joins regular WiFi APs only (not P2P), requires an Apple entitlement, and always shows a system confirmation prompt. |

**Decision:** Ship WiFi Direct (preview + download) as **Android-only** in this
release. iOS will show a graceful "local preview not available on iOS" placeholder in
the session screen. A dual-mode approach (firmware soft-AP + `NEHotspotConfiguration`
on iOS) is a candidate for a future release — tracked as a separate cross-repo item.

Firmware does **not** need to implement a soft-AP mode to unblock this release.

## App-side work created

| # | Change | File(s) |
|---|---|---|
| 1 | Implement real `WifiServiceImpl.connectGroup` — BLE round-trip to get credentials + Android `WifiP2pManager` join | `lib/core/wifi/wifi_service_impl.dart`, new `android/` platform channel |
| 2 | Platform-guard `connectGroup` to Android; return early / emit `WifiDirectState.failed` on iOS with a descriptive reason | `lib/core/wifi/wifi_service_impl.dart` |
| 3 | Session screen: show "WiFi preview not supported on iOS" placeholder when `WifiDirectState.failed` with platform reason | `lib/features/match/session/session_screen.dart` |
| 4 | Mock: ensure `MockWifiService.connectGroup` returns dynamic-credential fixture (not a fixed string) to keep tests realistic | `lib/mock/emulator/mock_wifi_service.dart` |

## Platform channel scope (Android)

The Android native channel needs to:
1. Call `WifiP2pManager.initialize(context, looper, null)` once.
2. Issue `WifiP2pManager.connect(channel, WifiP2pConfig(SSID, passphrase), actionListener)`.
3. Listen on `BroadcastReceiver(WIFI_P2P_CONNECTION_CHANGED_ACTION)` and report
   `WifiP2pInfo.groupOwnerAddress` back to Dart.
4. On disconnect, call `WifiP2pManager.removeGroup`.

This is implemented as a single Dart `MethodChannel` call with a response and an event
stream for state changes. No iOS counterpart for this release.

## Deferred — iOS track

When iOS WiFi preview is revisited, the likely path is:
1. Firmware adds a **concurrent soft-AP** mode (hostapd alongside the P2P GO).
2. App detects `Platform.isIOS`, sends a new BLE command requesting soft-AP mode.
3. Firmware returns soft-AP `{ssid, psk}` in a separate response.
4. App calls `NEHotspotConfigurationManager.apply` — user sees a one-time system prompt.
5. RTSP preview and downloads work identically via `groupOwnerIp`.

This is a cross-repo feature; a new firmware request file will be created when the
track is prioritised.

## Acceptance criteria

- On Android: after BLE connects, the WiFi Direct group comes up automatically,
  `WifiDirectGroup.ssid` and `.psk` match what `WifiDirectGroupResponse` returned,
  and the RTSP preview stream is reachable at `previewUrl()`.
- On iOS: no crash; session screen shows a clear "local preview not available on iOS"
  message rather than a spinner or silent failure.
- No compile-time SSID or passphrase constants exist anywhere in the app.
