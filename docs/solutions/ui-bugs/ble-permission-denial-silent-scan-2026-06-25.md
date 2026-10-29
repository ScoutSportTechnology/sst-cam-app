---
title: "BLE permission denial threw StateError into a fire-and-forget startScan(), leaving a silent dead scan screen"
date: 2026-06-25
category: ui-bugs
module: ble
problem_type: logic_error
component: discovery
severity: high
applies_when:
  - "Adding a runtime-permission request inside a service method the UI calls fire-and-forget"
  - "A BleService/port method throws to signal a user-actionable failure"
  - "Touching lib/features/discovery/discovery_page.dart or BleServiceImpl.startScan"
tags: [ble, permissions, android, riverpod, error-handling, unawaited-future, flutter]
related_components: [discovery, ble]
---

# BLE permission denial threw into an unawaited Future → silent dead scan screen

## Context

PR #19 added Android 12+ runtime permission handling to `BleServiceImpl.startScan()`:
it requests `BLUETOOTH_SCAN` / `BLUETOOTH_CONNECT` and **throws `StateError`** when
either is denied. The intent was to give the user an actionable message instead of a
scan that silently returns nothing.

## Problem

Both call sites in `lib/features/discovery/discovery_page.dart` invoked `startScan()`
**fire-and-forget** — `initState`'s post-frame callback and the Scan button's
`onPressed` both called it without `await` or `try/catch`, and `main_prod.dart`
installs no zone / `FlutterError.onError` handler. So on permission denial:

- The `StateError` lands in an **unawaited `Future`** that nobody reads — no crash,
  no message.
- The throw happens **before** `_isScanning = true`, so the UI stays on
  "Idle / No cameras found yet" with zero guidance.

The carefully-worded error string was never shown. This is the likely **first-launch
failure mode** for the very fix meant to make BLE work, and it was caught by a
multi-agent code review (5 independent reviewers flagged it), not by tests —
`BleServiceImpl` has no direct unit coverage.

## Solution

Route both call sites through a `Future<void> _startScan()` helper on the State that
awaits, catches, and surfaces the message:

```dart
Future<void> _startScan() async {
  try {
    await ref.read(bleServiceProvider).startScan();
  } on StateError catch (e) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
  if (mounted) setState(() {});
}
```

Fixed in PR #21.

## Lesson

A service method that **throws to communicate a user-actionable failure** is only as
good as its callers. If any call site is fire-and-forget (`initState` callbacks,
button handlers that don't `await`), the throw is swallowed and the feature looks
silently broken. When adding a throwing failure path to a port method, audit **every**
call site for `await` + `catch`, or surface failures through observable state
(an `AsyncValue`/error provider) rather than a bare `throw`. There is still no test
exercising the grant/deny branch — a regression guard is outstanding.
