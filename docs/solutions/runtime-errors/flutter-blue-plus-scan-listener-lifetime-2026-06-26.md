---
title: "FlutterBluePlus.startScan() returns when the scan STARTS, not when it ends"
date: 2026-06-26
category: runtime-errors
module: lib/core/ble/ble_service_impl.dart
problem_type: runtime_error
component: tooling
severity: high
symptoms:
  - "Open 'Connect a camera' → nothing shows; back out and back in → device appears"
  - "Tapping Scan does nothing; spamming Scan flashes a result for a frame then it vanishes"
  - "Scan indicator sits on 'Idle' even though a platform scan is running"
root_cause: async_timing
resolution_type: code_fix
tags: flutter_blue_plus, ble, scan, stream-subscription, async, lifecycle, riverpod, discovery
---

# FlutterBluePlus.startScan() returns when the scan STARTS, not when it ends

## Problem

BLE discovery never showed the camera on first entry to the page, but showed it
after backing out and re-entering. The scan results listener was being torn down
within milliseconds of starting, before any advertisement was delivered.

## Symptoms

- First entry to discovery: empty list, indicator stuck on "Idle".
- Leave and re-enter: the camera appears immediately.
- Spamming the Scan button: a device row flashes for one frame, then disappears.

## What Didn't Work

- **A `SeededBroadcast` replay of the last device list.** It fixed a real but
  *secondary* blanking issue (the empty list FlutterBluePlus pushes at scan
  start). It could not fix this: the listener was dead before any result arrived,
  so there was nothing to replay.

## Solution

The root cause: `startScan` treated `await FlutterBluePlus.startScan(timeout:)`
as if it blocked for the whole scan, then cancelled the results listener in a
`finally`. But in flutter_blue_plus (1.36.x) that future **completes the instant
the platform scan starts** — the `timeout` only schedules a later auto-stop. So
the `finally` cancelled the `onScanResults` listener immediately; the platform
kept scanning and buffering, but nothing relayed results into the UI. Re-entering
re-subscribed and picked up the *buffered* results — hence "works the second
time."

Fix: stop tying the listener lifetime to the `startScan()` future. Keep the
results subscription in a field, and drive teardown off the authoritative
`FlutterBluePlus.isScanning` stream (which emits `false` when the scan actually
stops):

```dart
_scanResultsSub = FlutterBluePlus.onScanResults.listen(_relayResults);

var sawScanning = false;
_isScanningSub = FlutterBluePlus.isScanning.listen((scanning) {
  if (scanning) {
    sawScanning = true;
  } else if (sawScanning) {           // real scan-end, not a stale replayed false
    _isScanning = false;
    unawaited(_teardownScanSubscriptions());
  }
});

await FlutterBluePlus.startScan(withServices: [_serviceUuid], timeout: timeout);
```

Two guards make it robust (added after code review):

- **Claim `_isScanning = true` BEFORE the first `await`** (the permission
  request), and wrap setup in try/catch that releases it on failure. Otherwise a
  second `startScan` during the permission dialog slips past the
  `if (_isScanning) return` guard and orphans the first call's live listener.
- **`sawScanning` guard** so a stale `false` replayed by `isScanning` at
  subscribe time cannot tear the listener down before the scan begins.
- **One `_teardownScanSubscriptions()` helper** shared by `stopScan`, the
  scan-end listener, the failed-setup catch, and `dispose` so the two
  subscriptions never diverge across those competing call sites.

## Why This Works

`isScanning` reflects the real platform scan state; the `startScan()` future does
not. Binding the listener and the `_isScanning` flag to `isScanning` means they
live exactly as long as the scan does — through the full timeout window — instead
of dying when the start call returns.

## Prevention

- **Never assume a plugin's `start*()` future spans the operation.** Check
  whether it resolves on *initiation* or *completion*; for streaming/scanning
  APIs it is almost always initiation. Drive lifecycle off an explicit state
  stream (`isScanning`, connection-state) instead.
- **A subscription that must outlive the call that creates it belongs in a
  field, not a local cancelled in `finally`.**
- **Mock-built features inherit mock timing.** This code worked against the
  emulator (where `startScan` was effectively synchronous); the divergence only
  appeared against the real plugin. Audit every BLE/WiFi lifecycle assumption
  against real hardware, not just the test double.
- **Test seam:** the `sawScanning` ordering is the exact bug — extracting a pure
  `ScanLifecycleTracker.update(bool) -> bool` (true on the first false after a
  true) would make it unit-testable without the FlutterBluePlus statics.
