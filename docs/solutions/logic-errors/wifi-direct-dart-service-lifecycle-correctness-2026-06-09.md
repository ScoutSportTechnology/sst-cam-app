---
title: "WiFi Direct Dart service layer: invokeMethod timeout, subscription leak, concurrent connect race, missing StopWifiDirectCommand"
date: 2026-06-09
category: logic-errors
module: wifi_direct
problem_type: logic_error
component: service_object
severity: high
symptoms:
  - "invokeMethod for connect/disconnect blocks Dart isolate indefinitely if Android native layer hangs"
  - "Ghost WifiDirectState events emitted after a failed connection (subscription not cancelled in onError)"
  - "Concurrent connectGroup() calls for same device race: two BLE round-trips, two P2P connects"
  - "Camera firmware keeps P2P group alive after app-side disconnectGroup(); blocks future connect attempts"
  - "disconnectGroup() runs teardown even when device was never connected"
root_cause: missing_workflow_step
resolution_type: code_fix
related_components: [wifi_direct_channel, ble_service, ble_protocol]
tags: [wifi-direct, dart, service-layer, lifecycle, subscription-leak, in-flight-dedup, ble-command, stop-wifi-direct, timeout, completer, platform-channel]
---

# WiFi Direct Dart service layer: invokeMethod timeout, subscription leak, concurrent connect race, missing StopWifiDirectCommand

## Problem

`WifiP2pChannel` and `WifiServiceImpl` contained five lifecycle correctness bugs: missing timeouts on platform channel calls, a subscription cancellation omission causing ghost state emissions, missing in-flight deduplication allowing concurrent `connectGroup` calls to race, and `disconnectGroup` never sending `StopWifiDirectCommand` over BLE to release the firmware's P2P group.

## Symptoms

- `channel.connect()` or `channel.disconnect()` blocks the Dart side indefinitely when the Android native layer hangs (no timeout)
- After a failed WiFi Direct connection, `WifiDirectState` events continued emitting for the disconnected device
- Rapid UI retries or overlapping `connectGroup` calls for the same device caused inconsistent final state (two BLE credential fetches, two Android P2P connect attempts)
- After `disconnectGroup()` returned, the camera firmware kept its P2P group alive, preventing a subsequent `connectGroup` from succeeding until the camera timed out internally
- `disconnectGroup()` on a device that was never connected triggered teardown work unnecessarily

## What Didn't Work

Root causes were identified directly through code inspection; no failed intermediate attempts.

## Solution

### Bug E — invokeMethod timeout missing

**Files:** `lib/core/wifi/wifi_p2p_channel.dart`

Platform channel `invokeMethod` futures have no built-in timeout. A hung Android service thread leaves the Dart future permanently unresolved.

```dart
Future<void> connect({required String ssid, required String psk}) async {
  await _method
      .invokeMethod<void>('connect', {'ssid': ssid, 'psk': psk})
      .timeout(const Duration(seconds: 15));
}

Future<void> disconnect() async {
  await _method
      .invokeMethod<void>('disconnect')
      .timeout(const Duration(seconds: 15));
}
```

### Bug F — Stream subscription leak in onError

**Files:** `lib/core/wifi/wifi_service_impl.dart`

`Map.remove()` returns the removed value but does not call any cleanup on it. The removed `StreamSubscription` continued to fire `onData`/`onError` callbacks.

```dart
// Before:
onError: (Object e) {
  _stateSubscriptions.remove(deviceId);  // removes from map but does not cancel
  _emitState(deviceId, WifiDirectState.failed);
},

// After:
onError: (Object e) {
  _stateSubscriptions.remove(deviceId)?.cancel();  // ← chain .cancel()
  _emitState(deviceId, WifiDirectState.failed);
},
```

### Bug G — No in-flight deduplication for concurrent connectGroup calls

**Files:** `lib/core/wifi/wifi_service_impl.dart`

Two concurrent `connectGroup(deviceId)` calls both entered the connect sequence, each canceling the other's EventChannel subscription and racing on BLE + Android P2P connect.

```dart
// Add class-level field (alongside other Map<String, ...> fields):
final Map<String, Completer<WifiDirectGroup>> _inflightConnects = {};

// Wrap _connectGroupInternal:
@override
Future<WifiDirectGroup> connectGroup(String deviceId) async {
  final existing = _inflightConnects[deviceId];
  if (existing != null) return existing.future;

  final completer = Completer<WifiDirectGroup>();
  _inflightConnects[deviceId] = completer;
  try {
    final group = await _connectGroupInternal(deviceId);
    completer.complete(group);
    return group;
  } catch (e) {
    completer.completeError(e);
    rethrow;
  } finally {
    _inflightConnects.remove(deviceId);
  }
}
```

### Bug H — StopWifiDirectCommand not sent on disconnect

**Files:** `lib/core/models/command.dart`, `lib/core/ble/ble_protocol.dart`, `lib/mock/emulator/mock_ble_service.dart`, `lib/core/wifi/wifi_service_impl.dart`

`disconnectGroup` tore down the Android P2P side without telling the firmware to release its P2P group over BLE. `StopWifiDirectCommand` (proto field 54) existed in the generated proto but was absent from the Dart command hierarchy.

Add to `command.dart`:
```dart
class StopWifiDirectCommand extends BleCommand {}
```

Wire in `ble_protocol.dart` (`_toProtoCommand` and `_mapOkResponse`) and `mock_ble_service.dart` (`_encodeCommand`, `_buildResponse`, `_mapResponse`):
```dart
StopWifiDirectCommand() => proto.Command(
  correlationId: correlationId,
  stopWifiDirect: proto.StopWifiDirectCommand(),
),
// in _mapOkResponse:
StopWifiDirectCommand() => BleCommandResponse.ok(null as T?),
```

Update `disconnectGroup` in `wifi_service_impl.dart`:
```dart
@override
Future<void> disconnectGroup(String deviceId) async {
  // Early return when already idle — nothing to tear down.
  if (_currentGroups[deviceId] == null && _inflightConnects[deviceId] == null) {
    return;
  }

  await _stateSubscriptions.remove(deviceId)?.cancel();
  _emitState(deviceId, WifiDirectState.stopping);

  if (!Platform.isIOS) {
    // Tell firmware to release its P2P group before tearing down Android side.
    try {
      await _ble.sendCommand<void>(deviceId, StopWifiDirectCommand());
    } catch (_) { /* best-effort */ }
    try {
      await _channel.disconnect();
    } catch (_) { /* best-effort */ }
  }

  _currentGroups.remove(deviceId);
  _emitState(deviceId, WifiDirectState.idle);
}
```

## Why This Works

**Bug E:** An explicit `.timeout()` ensures callers always receive a `TimeoutException` they can handle rather than blocking indefinitely. 15 seconds covers expected worst-case hardware response time.

**Bug F:** `Map.remove()` removes the reference from the map but leaves the underlying listener wired to the live stream. Chaining `.cancel()` tears down the listener, preventing any further `onData`/`onError` callbacks from that subscription after it has been removed.

**Bug G:** The Completer guard serializes callers: the second caller receives the same `Future` as the first and waits for its result, guaranteeing only one native connect sequence runs at a time per device. Both callers succeed or fail together.

**Bug H:** The BLE protocol is pull-model and symmetric — every resource the app requests must be explicitly released over BLE. Without `StopWifiDirectCommand`, the firmware has no signal that the app has disconnected and keeps its P2P group alive, blocking subsequent connects until its internal timeout. The idle guard avoids sending the command when no connection was ever established.

## Prevention

- All `invokeMethod` calls crossing the platform channel boundary must have `.timeout()` matching expected worst-case hardware response time.
- Rule: any `Map<K, StreamSubscription>.remove(key)` call must chain `.cancel()`. Consider a helper extension `cancelAndRemove(key)` to make this impossible to omit.
- Any async service method that starts hardware/network work must have an in-flight deduplication guard. Document this as a service-layer convention.
- Checklist: for every BLE command that allocates a firmware resource, a corresponding release command must exist in `command.dart`, `ble_protocol.dart`, and `mock_ble_service.dart` before the allocating command ships. The exhaustive switch in `_mapOkResponse` / `_mapResponse` will produce a compile error if a new command is added without covering all switch sites.

## Related Issues

- See also: `docs/solutions/integration-issues/wifi-direct-native-platform-channel-correctness-2026-06-09.md` — native platform channel bugs for the same WiFi Direct feature
- See also: `docs/solutions/logic-errors/core-importing-feature-layer-inversion-2026-05-26.md` — another `StreamSubscription` leak pattern in service-layer code
