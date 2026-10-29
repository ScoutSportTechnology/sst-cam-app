---
title: "Android 13+ WiFi-Direct join needs CHANGE_WIFI_STATE on all APIs + runtime NEARBY_WIFI_DEVICES"
date: 2026-06-26
category: integration-issues
module: android/app/src/main/AndroidManifest.xml + lib/core/wifi/wifi_service_impl.dart
problem_type: integration_issue
component: tooling
severity: high
symptoms:
  - "Hero card shows 'WIFI · FAILED' even though telemetry reports the camera AP is ready"
  - "WifiP2pManager.connect() ActionListener.onFailure fires; no Nearby-devices prompt ever shown"
  - "Preview never reaches LINKING→LIVE on Android 13/14 despite the firmware group being up"
root_cause: missing_permission
resolution_type: code_fix
tags: android, wifi-direct, p2p, WifiP2pManager, permissions, nearby_wifi_devices, change_wifi_state, manifest, flutter
---

# Android 13+ WiFi-Direct join needs CHANGE_WIFI_STATE on all APIs + runtime NEARBY_WIFI_DEVICES

## Problem

On a Samsung S24 (Android 14 / API 34), the phone could never join the camera's
WiFi-Direct group. The firmware formed the group, assigned the GO IP, served
RTSP, and telemetry reported "AP ready" — but the app's `WifiP2pManager.connect()`
silently failed and the hero card showed `WIFI · FAILED`. The telemetry badge and
the hero card diverge because they have different sources: telemetry is a firmware
poll over BLE; the hero card reflects the *phone-side* P2P join.

## Symptoms

- `WifiP2pManager.connect()` → `ActionListener.onFailure(reason)` → Kotlin emits
  `STATE_FAILED` → `wifiConnectionStateProvider` = failed → hero `WIFI · FAILED`.
- No "Nearby devices" runtime permission dialog ever appeared.
- Camera side fully healthy (group + IP + RTSP + DHCP all up).

## What Didn't Work

- **Declaring `NEARBY_WIFI_DEVICES` in the manifest only.** On API 33+ it is a
  *dangerous* (runtime) permission — declaring it is not enough; it must be
  requested at runtime and granted, or `connect()` fails.

## Solution

Two coupled defects, both required:

1. **Manifest: `CHANGE_WIFI_STATE` was capped at `maxSdkVersion="32"`.**
   `WifiP2pManager.connect()` / `removeGroup()` require it on **all** API levels.
   Capping it left Android 13+ without it.

   ```xml
   <!-- before: android:maxSdkVersion="32" — left API 33+ without it -->
   <uses-permission android:name="android.permission.CHANGE_WIFI_STATE" />
   ```

2. **Runtime: request `NEARBY_WIFI_DEVICES` before the join.** It is dangerous on
   API 33+ and was never requested (only the BLE-scan permissions were).

   ```dart
   if (Platform.isAndroid) {
     final status = await Permission.nearbyWifiDevices.request();
     if (!status.isGranted && !status.isLimited) {
       _emitState(deviceId, WifiDirectState.failed);
       throw const WifiDirectException(
         'Nearby Wi-Fi devices permission denied — grant it to join the '
         'camera preview network.');
     }
   }
   ```

   `NEARBY_WIFI_DEVICES` is declared with `usesPermissionFlags="neverForLocation"`
   so it is not treated as a location proxy (least-privilege; we don't derive
   location). `ACCESS_FINE_LOCATION` stays capped at `maxSdkVersion="32"` (its
   pre-13 role), replaced by `NEARBY_WIFI_DEVICES` on 33+.

## Why This Works

`WifiP2pManager.connect()` has two permission requirements on API 33+:
`CHANGE_WIFI_STATE` (normal, install-time, all API levels) **and**
`NEARBY_WIFI_DEVICES` (dangerous, runtime, 33+). The manifest cap removed the
first; the missing runtime request denied the second. Either alone makes
`connect()` fail. Restoring the install-time permission and requesting the runtime
one at the point of join satisfies both.

## Prevention

- **For Android 13+ WiFi-Direct: hold `CHANGE_WIFI_STATE` (uncapped) + request
  `NEARBY_WIFI_DEVICES` at runtime.** `ACCESS_WIFI_STATE` is also needed (read).
- **Audit `maxSdkVersion` caps when targeting a newer SDK** — a cap added for a
  permission-model migration can silently drop a permission that newer APIs still
  require. The compile-time/install-time nature means it fails only at runtime on
  the affected API level.
- **When two UI surfaces report the same concept (here: camera-AP-ready vs
  preview-join), confirm they share a source before assuming agreement.** Their
  divergence here was the clue that the firmware was fine and the failure was
  phone-side.
- **Improvement (deferred):** request the permission *before* sending
  `StartWifiDirect` so a denial doesn't leave the firmware group up; and subscribe
  the platform state stream right before `connect()` to avoid a stale `failed`
  event flashing the hero card. See [[flutter-blue-plus-scan-listener-lifetime-2026-06-26]]
  for the related "emulation-era async assumptions break on real hardware" theme.
- **Test seam:** inject a permission-checker closure into `WifiServiceImpl` so the
  granted/denied branches are unit-testable without the `permission_handler`
  plugin statics.
