---
title: "kAppEnv.isDevBackend must not bypass camera connection state guards"
date: 2026-05-19
category: docs/solutions/conventions/
module: ble
problem_type: convention
component: development_workflow
severity: medium
applies_when:
  - Writing UI guards that gate actions behind an active camera connection
  - Adding dev shortcuts to pages that require a connected camera
  - Reviewing any code path that uses kAppEnv.isDevBackend as a condition
tags:
  - ble
  - mock-service
  - dev-mode
  - connection-state
  - flutter
---

# kAppEnv.isDevBackend must not bypass camera connection state guards

## Context

During early development, screens often bypass real connection checks with `kAppEnv.isDevBackend` so developers can navigate the full UI without a physical device or even a connected mock. The shortcut is tempting: add `kAppEnv.isDevBackend ||` to a connection check and the button is always enabled in dev.

The problem: `MockBleService` already provides a complete scan+connect simulation that mirrors the real `BleServiceImpl` lifecycle. By the time this bypass is reached, the developer could simply tap "Connect" in the mock discovery screen — one extra tap that provides real exercise of connection-dependent code paths.

Two bypasses accumulated in `match_page.dart`:
1. `_SetupScreen` computed `connected = kAppEnv.isDevBackend || (activeId != null && ...connected)` — "Start match" was always enabled in dev regardless of mock camera state.
2. `_SessionScreen` had no connection check at all for recording and streaming controls — `toggleRecPause`, `stopRecording`, and `setStreaming` could be called with no camera connected.
3. `_startMatch()` fell back to a hardcoded `'SST-CAM-001'` device ID when `activeId` was null.

The user could start a match and start recording without ever connecting to a camera — in a UI that communicates camera state through connection indicators.

## Guidance

Remove `kAppEnv.isDevBackend ||` from connection-state guards. Compute `connected` from the real provider and pass `null` callbacks when disconnected.

**Before (`_SetupScreen` — bypass in connected computation):**
```dart
final connected = kAppEnv.isDevBackend ||
    (activeId != null &&
        ref.watch(connectionStateProvider(activeId)).valueOrNull ==
            CameraConnectionState.connected);
```

**After (no bypass):**
```dart
final connected =
    activeId != null &&
    ref.watch(connectionStateProvider(activeId)).valueOrNull ==
        CameraConnectionState.connected;
```

**Before (`_SessionScreen` — no connection check on recording controls):**
```dart
_BottomControls(
  onRecToggle: ctl.toggleRecPause,
  onRecStop: ctl.stopRecording,
  onStreamToggle: () => ctl.setStreaming(!state.streaming),
),
```

**After (null callbacks disable buttons when disconnected):**
```dart
_BottomControls(
  onRecToggle: connected ? ctl.toggleRecPause : null,
  onRecStop: connected ? ctl.stopRecording : null,
  onStreamToggle: connected ? () => ctl.setStreaming(!state.streaming) : null,
),
```

**Before (`_startMatch` — hardcoded device ID fallback):**
```dart
final deviceId = ref.read(activeCameraIdProvider) ??
    (kAppEnv.isDevBackend ? 'SST-CAM-001' : null);
```

**After (no fallback; the UI guard already prevents this path):**
```dart
final deviceId = ref.read(activeCameraIdProvider);
if (deviceId == null) return;
```

Also remove the hint text bypass — the "Connect a camera to start the match." message should appear whenever disconnected, not only in non-dev mode:

**Before:**
```dart
if (!kAppEnv.isDevBackend && !connected) Text('Connect a camera...')
```

**After:**
```dart
if (!connected) Text('Connect a camera...')
```

## Why This Matters

`kAppEnv.isDevBackend` bypasses simulate "the happy path always" in dev. This hides two categories of bugs:

1. **Null-safety bugs.** Code that assumes `activeId != null` or a valid device ID will crash in production when the camera is absent. With the bypass, these paths are never exercised locally.

2. **UI state bugs.** Buttons that should be disabled when disconnected remain enabled in dev. UX regressions (wrong styling on disabled state, mismatched indicator colors, accessibility labels that describe the wrong state) are invisible.

`MockBleService` supports the full device lifecycle:
- `startScan()` emits mock `SstDevice` objects after configurable delays
- `connect(deviceId)` transitions through `CameraConnectionState.connecting` → `connected`
- All BLE commands return realistic responses via `pushSessionConfig`, `getTelemetry`, etc.

A developer in dev mode can tap "Connect" in the discovery screen in under two seconds. That one tap exercises the full connection-dependent code path and catches state bugs before they reach production.

## When to Apply

**Remove `kAppEnv.isDevBackend` from a guard when:**
- The mock service already handles the scenario the guard bypasses.
- The guard prevents testing a real code path (null handling, disabled UI state, etc.).

**Keep `kAppEnv.isDevBackend` checks when:**
- Selecting which service implementation to instantiate (this is its intended purpose).
- Enabling dev-only diagnostic overlays or panels with no production equivalent.
- Skipping platform-specific initialization that cannot run in the dev container (e.g., actual BLE adapter startup, platform channel registration).

## Examples

**Legitimate uses of `kAppEnv.isDevBackend` (keep these):**
```dart
// lib/state/ble_providers.dart — selecting implementation
final bleServiceProvider = Provider<BleService>((ref) {
  if (kAppEnv.isDevBackend) return MockBleService();
  return BleServiceImpl();
});

// lib/pages/debug_page.dart — dev-only diagnostic screen
// (accessible via long-press on version label in Settings)
```

**Illegitimate uses (remove these):**
```dart
// Bypasses connection check — MockBleService handles this state
final connected = kAppEnv.isDevBackend || (activeId != null && ...);

// Suppresses null-safety guard — crashes in production
final deviceId = activeId ?? 'SST-CAM-001';

// Hides UX bugs in disabled state
onTap: kAppEnv.isDevBackend
    ? () => doThing()
    : connected ? () => doThing() : null,
```

## Related

- `lib/ble/mock_ble_service.dart` — full scan+connect simulation; no bypass needed
- `lib/state/ble_providers.dart` — legitimate use of `kAppEnv.isDevBackend` for service selection
- `lib/pages/match_page.dart` — the page where these bypasses were found and removed
