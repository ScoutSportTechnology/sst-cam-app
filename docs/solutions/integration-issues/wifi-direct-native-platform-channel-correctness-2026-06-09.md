---
title: "WiFi Direct native platform channel: iOS nil stream handler, Android pre-Q guard, BroadcastReceiver leak, group-owner fallthrough"
date: 2026-06-09
category: integration-issues
module: wifi_direct
problem_type: integration_issue
component: tooling
severity: high
symptoms:
  - "MissingPluginException thrown on iOS when Dart subscribes to the WiFi Direct EventChannel"
  - "On Android API < 29, connect() produces no state change; Dart side hangs in starting"
  - "After a failed Android P2P connect, spurious WifiDirectState changes emitted by leaked BroadcastReceiver"
  - "Device becomes P2P group owner after negotiation; no state emitted; Dart side stuck in starting indefinitely"
root_cause: wrong_api
resolution_type: code_fix
related_components: [wifi_service_impl, wifi_p2p_channel]
tags: [ios, android, wifi-direct, platform-channel, eventchannel, stream-handler, missing-plugin-exception, broadcast-receiver, wifi-p2p, group-owner, api-level]
---

# WiFi Direct native platform channel: iOS nil stream handler, Android pre-Q guard, BroadcastReceiver leak, group-owner fallthrough

## Problem

The native WiFi Direct platform channel layer (`AppDelegate.swift` on iOS, `WifiDirectChannel.kt` on Android) contained four correctness bugs that caused `MissingPluginException` on iOS and silent hangs, BroadcastReceiver leaks, and stuck connection states on Android.

## Symptoms

- `MissingPluginException` thrown on iOS when Dart code subscribed to `com.sst.sstcam/wifi/state`
- On Android API 28 and below, `connect()` produced no state change; Dart side stuck indefinitely in `starting`
- After a failed Android P2P connect, future system-wide `WIFI_P2P_CONNECTION_CHANGED_ACTION` broadcasts triggered spurious `WifiDirectState` changes
- When P2P negotiation resulted in the app device becoming group owner, no state was emitted and the Dart side hung indefinitely in `starting`

## What Didn't Work

Root causes were identified directly through code inspection; no failed intermediate attempts.

## Solution

### Bug A — iOS: nil stream handler causes MissingPluginException

**Files:** `ios/Runner/AppDelegate.swift`

`FlutterEventChannel.setStreamHandler(nil)` does not register a no-op — it fully *unregisters* the handler. When Dart subscribes, no handler is registered, producing `MissingPluginException`. Additionally, `FlutterEventChannel` does not retain its handler; a local variable is released at end of scope, silently unregistering it.

```swift
// Before — nil unregisters the handler; local vars released at end of scope
let eventChannel = FlutterEventChannel(name: "com.sst.sstcam/wifi/state",
                                        binaryMessenger: controller.binaryMessenger)
eventChannel.setStreamHandler(nil)

// After — top-level no-op handler class (before AppDelegate declaration):
private class _NoOpStreamHandler: NSObject, FlutterStreamHandler {
  func onListen(withArguments arguments: Any?,
                eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    events(FlutterEndOfEventStream)  // immediately closes the stream on iOS
    return nil
  }
  func onCancel(withArguments arguments: Any?) -> FlutterError? { nil }
}

// AppDelegate — store both channels and handler as instance properties:
@objc class AppDelegate: FlutterAppDelegate {
  private var wifiMethodChannel: FlutterMethodChannel?
  private var wifiEventChannel: FlutterEventChannel?
  private let wifiStreamHandler = _NoOpStreamHandler()

  override func application(_ application: UIApplication,
      didFinishLaunchingWithOptions launchOptions: ...) -> Bool {
    if let controller = window?.rootViewController as? FlutterViewController {
      wifiMethodChannel = FlutterMethodChannel(name: "com.sst.sstcam/wifi",
                                               binaryMessenger: controller.binaryMessenger)
      wifiMethodChannel?.setMethodCallHandler { (_, result) in result(nil) }

      wifiEventChannel = FlutterEventChannel(name: "com.sst.sstcam/wifi/state",
                                              binaryMessenger: controller.binaryMessenger)
      wifiEventChannel?.setStreamHandler(wifiStreamHandler)
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
```

### Bug B — Android: no pre-Q API guard

**Files:** `android/app/src/main/kotlin/com/sst/sstcam/WifiDirectChannel.kt`

`WifiP2pConfig.Builder.setNetworkName/setPassphrase` (SSID/PSK join) requires API 29+. The pre-Q `WifiP2pConfig()` path requires a peer MAC address from a prior P2P discovery scan — a flow this app never performs. Using an empty address always produces `WifiP2pManager.ERROR`.

```kotlin
// Added at top of connect():
if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
    eventSink?.success(STATE_FAILED)
    result.error("UNSUPPORTED", "WiFi Direct credential-based join requires Android 10+", null)
    return
}
```

### Bug C — Android: BroadcastReceiver not unregistered on connect failure

**Files:** `android/app/src/main/kotlin/com/sst/sstcam/WifiDirectChannel.kt`

`unregisterReceiver()` was called in `onCancel` and `onSuccess` but not in `ActionListener.onFailure`. The receiver registered before the connect attempt persisted after failure and responded to system-wide P2P broadcasts indefinitely.

```kotlin
override fun onFailure(reason: Int) {
    unregisterReceiver()  // ← was missing
    eventSink?.success(STATE_FAILED)
    result.error("CONNECT_FAILED", "WifiP2p connect failed: $reason", null)
}
```

### Bug D — Android: group-owner role unhandled in BroadcastReceiver

**Files:** `android/app/src/main/kotlin/com/sst/sstcam/WifiDirectChannel.kt`

The app is always a P2P client (the camera is always group owner). If negotiation makes the app device the GO, the old code fell through with no state change, leaving Dart in a terminal `starting` state.

```kotlin
if (info?.isGroupOwner == false && info.groupFormed) {
    eventSink?.success(STATE_CONNECTED)
} else if (info?.isGroupOwner == true && info.groupFormed) {
    // Device became GO unexpectedly; we only join as client.
    Log.w(TAG, "Device became GO unexpectedly; emitting STATE_FAILED")
    eventSink?.success(STATE_FAILED)
} else if (info?.groupFormed == false) {
    eventSink?.success(STATE_IDLE)
}
```

## Why This Works

**Bug A:** `FlutterEventChannel` docs specify that passing `nil` removes the previously registered handler. Making both channels (`wifiMethodChannel`, `wifiEventChannel`) and the handler (`wifiStreamHandler`) instance properties on `AppDelegate` ensures they remain alive for the app's lifetime. `_NoOpStreamHandler` must be declared as a top-level Swift class (before `AppDelegate`) — Swift does not support nested class declarations the same way other languages do. The handler satisfies the protocol contract by immediately signaling end-of-stream via `FlutterEndOfEventStream`, so iOS-side Dart subscriptions receive a clean close rather than hanging.

**Bug B:** `WifiP2pConfig.Builder` for SSID/PSK join was introduced in API 29. The pre-Q path requires a MAC address from prior discovery — a flow this app never initiates — so any pre-Q attempt always fails with `ERROR`. The guard makes the failure explicit and immediate, with a clear error message.

**Bug C:** `registerReceiver()` and `unregisterReceiver()` must always be balanced. The failure path was the only one missing the call, causing the receiver to persist and respond to system broadcasts indefinitely after a failed connect.

**Bug D:** Without handling the unexpected GO case, the state machine had no exit path. Emitting `STATE_FAILED` triggers the Dart-side error path, which cancels the subscription and emits `WifiDirectState.failed`, allowing the UI to show an error and offer a retry.

## Prevention

- Never pass `nil` to `FlutterEventChannel.setStreamHandler()` on iOS; always register a concrete handler. Store both the channel and the handler as strong instance properties on the owner object, never as locals.
- For every Android API with a version gate, add an explicit `Build.VERSION.SDK_INT < Build.VERSION_CODES.X` guard at the call site that returns a clear error rather than attempting the call on unsupported versions.
- Code-review checklist: every `registerReceiver()` must have a corresponding `unregisterReceiver()` in all exit paths (success, failure, and cancel).
- Enumerate all possible state combinations in `BroadcastReceiver` handlers. Any unhandled combination should emit `STATE_FAILED` and log a warning rather than silently falling through.

## Related Issues

- See also: `docs/solutions/logic-errors/wifi-direct-dart-service-lifecycle-correctness-2026-06-09.md` — Dart-layer lifecycle bugs for the same WiFi Direct feature
