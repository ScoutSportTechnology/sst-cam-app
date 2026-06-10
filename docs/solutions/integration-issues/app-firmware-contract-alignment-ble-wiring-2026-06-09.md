---
title: "App-side firmware contract alignment: pushSessionConfig no-op, missing chunk transport, absent version handshake"
date: 2026-06-09
category: integration-issues
module: ble_service
problem_type: integration_issue
component: service_object
symptoms:
  - "pushSessionConfig() returns Future.value() and never transmits; firmware gates overlay apply on it so overlays never apply"
  - "Commands larger than one MTU cannot be sent; app never emits ChunkAck so firmware chunked responses stall"
  - "Protocol-version skew is silently accepted: app never reads DeviceInfo.protocol_version at connect"
  - "Goal events route by display label not configured team id; firmware drops the score as an unknown team"
  - "match-state updated_at decoded with a spurious *1000, so timestamps land thousands of years in the future"
root_cause: missing_workflow_step
resolution_type: code_fix
severity: high
tags:
  - ble
  - proto3
  - chunked-transport
  - firmware-contract
  - version-handshake
  - flutter
related_components:
  - ble_protocol
  - ble_service_impl
  - session_screen
  - wifi_service_impl
---

# App-side firmware contract alignment: pushSessionConfig no-op, missing chunk transport, absent version handshake

## Problem
The app's firmware-facing layer shared the proto/BLE wire contract with the firmware but was largely mock/no-op ("pending firmware wiring"). Against real firmware (and the planned emulator), the app could not transmit session config, could not send/receive multi-chunk frames, silently accepted version-skewed sessions, and mis-routed scores and timestamps. (PR #11, `feat/logic-alignment`, merged to `main` as `1d28416`, 2026-06-09.)

Scope note: this doc covers the **BLE transport + session-config + version-handshake + score-routing** core. The overlay opacity / banner-timer rendering fixes from the same effort are documented separately in `docs/solutions/ui-bugs/overlay-renderer-opacity-missing-banner-timer-orphan-2026-06-09.md` — not repeated here.

## Symptoms
- `pushSessionConfig()` was a literal no-op → firmware gates overlay apply on it, so overlays never applied.
- Commands larger than one MTU could not be sent; app never emitted `ChunkAck`, so firmware chunked responses stalled.
- Protocol-version skew silently accepted — app never read `DeviceInfo.protocol_version` at connect.
- Goal events routed by display label, not configured team id → firmware drops the score as an unknown team.
- `match-state` `updated_at` decoded with a spurious `*1000` → timestamps land thousands of years in the future.

## What Didn't Work
The mock/no-op baseline. `pushSessionConfig` (pre-`a844ae2`, `lib/core/ble/ble_service_impl.dart` ~line 262):
```dart
Future<void> pushSessionConfig(String deviceId, PushSessionConfig config) {
  // Noop until firmware wiring is complete.
  return Future<void>.value();
}
```
Outbound writes were single-frame only; inbound reassembly keyed buffers by arrival order with no ack emitted; the version check (when it briefly lived in `decodeResponse`) only logged an error response instead of refusing the session.

## Solution

**(a) pushSessionConfig wiring + Fix-14 dedicated encode helper** — `a844ae2`. `ble_service_impl.dart` now drives the real completer/timeout/correlation machinery; `ble_protocol.dart` adds `encodeSessionConfigFrames` that **bypasses `_toProtoCommand`** — Fix 14 preserved: `PushSessionConfig` stays OUT of the `BleCommand` sealed hierarchy.
```dart
// ble_service_impl.dart (after)
final frames = BleProtocol.encodeSessionConfigFrames(config, corrId);
await conn._writeFrames(corrId, frames);
final responseBytes = await completer.future.timeout(const Duration(seconds: 10), ...);
final resp = BleProtocol.decodeSessionConfigResponse(responseBytes, corrId);
if (!resp.isOk) throw BleConnectionException('pushSessionConfig failed: ${resp.errorMessage}');
```
```dart
// ble_protocol.dart — single wire-translation point, NOT via _toProtoCommand
static List<Uint8List> encodeSessionConfigFrames(PushSessionConfig config, String correlationId) {
  final protoCmd = _sessionConfigToProtoCommand(config, correlationId);
  return _splitIntoFrames(protoCmd.writeToBuffer(), correlationId);
}
// proto3 optional: leave unset when null so the receiver distinguishes "no streaming" from ""
if (config.rtmpUrl != null) pb.rtmpUrl = config.rtmpUrl!;
if (config.streamKey != null) pb.streamKey = config.streamKey!;
```

**(b) Outbound chunking + inbound ChunkAck** — `a844ae2`. `_splitIntoFrames` emits N ordered `ChunkedPayload` frames (sequential `chunk_index`, shared `correlation_id`, `total_chunks=N`) above `maxChunkDataBytes`; sub-MTU keeps a single-frame fast path. `_writeFrames` is ack-gated — awaits the inbound `ChunkAck` for each `chunk_index` before sending the next. Inbound, `ChunkReassembler` places data **by `chunk_index`, not arrival order**, acks every inbound chunk, and disambiguates ack-vs-payload by the `total_chunks == 0` sentinel:
```dart
if (total == 0) { _pendingAcks[corrId]?.remove(chunk.chunkIndex)?.complete(); return; }
```

**(c) Version handshake at connect** — `3ca9732`, `connect()` (~line 135). The gate was relocated out of `decodeResponse` (which stays pure) into connect, which reads `DeviceInfo` and **refuses** on skew:
```dart
final info = await sendCommand<DeviceInfoResponse>(deviceId, GetDeviceInfoCommand());
if (!info.isOk || info.payload == null) { await device.disconnect(); throw BleConnectionException('Device info handshake failed'); }
if (info.payload!.protocolVersion != kAppProtocolVersion) {
  await device.disconnect();
  throw BleProtocolVersionException(expected: kAppProtocolVersion, actual: info.payload!.protocolVersion);
}
```

**(d) Score routing by configured team id** — `de384fa`, `lib/features/match/session/session_screen.dart` ~line 336:
```dart
// before: ScoreUpdateCommand(teamId: team, delta: 1)   // 'team' was the display label
final live = ref.read(liveMatchProvider);
final teamId = team == live.homeName ? match.team.id : live.awayName;
_sendIfConnected(ref, ScoreUpdateCommand(teamId: teamId, delta: 1));
```

**(e) Banner params + player_id** — `8037793`. Builds the `{{param}}` substitution map (`jersey`) and threads `params`/`playerId` into every `BannerEventCommand` (goal/yellow/red/sub), keeping keys in sync with `overlay_renderer`'s `_resolveBinding`.

**(f) Epoch-ms timestamp + shared timeout budget** — `3ca9732`. `updatedAt: DateTime.fromMillisecondsSinceEpoch(s.updatedAt.toInt())` (dropped the `* 1000`); `_writeFrames` takes a shared `deadline` so multi-chunk commands cannot stack per-chunk timeouts past the overall budget; ack timeouts surface as `BleTimeoutException`.

Result: 528 unit tests pass.

## Why This Works
The defects were skipped contract steps (`missing_workflow_step`): no transmit, no ack, no handshake, no id-based routing — plus two pure logic errors (the `*1000` timestamp and the label-vs-id score). Routing every session-config/command through the same completer/correlation/deadline machinery, and gating connect on the version read, makes the app a faithful contract peer instead of a mock. proto3 `optional` on streaming fields lets the firmware distinguish "no streaming" from an empty string.

## Prevention
- The two P1 slices — score-routing UI (`session_screen`) and the connect version handshake (`BleServiceImpl.connect`) — **merged WITHOUT integration tests** (review-confidence only; 528 unit tests pass but these app↔firmware paths are uncovered). The planned `sst-cam-emulator` is the intended gap-closer.
- Add an emulator-backed integration suite asserting: (1) overlay apply only after a transmitted session config, (2) connect refusal on version skew, (3) goal routing by configured team id, (4) multi-chunk command round-trips with ack gating.
- Never leave a firmware-facing method as a `Future.value()` no-op behind a real interface — that is a skeleton; wire it or track it outside the tree.
- Set proto3 `optional` fields only when present; never encode null as empty string.

## Related Issues
- Origin plan: `docs/plans/2026-06-09-016-feat-logic-alignment-app-plan.md`
- Requirements/brainstorm: `docs/brainstorms/2026-06-08-app-firmware-logic-alignment-requirements.md`
- Overlay rendering fixes (same effort, separate doc): `docs/solutions/ui-bugs/overlay-renderer-opacity-missing-banner-timer-orphan-2026-06-09.md`
- WiFi-Direct counterparts: `docs/solutions/integration-issues/wifi-direct-native-platform-channel-correctness-2026-06-09.md`, `docs/solutions/logic-errors/wifi-direct-dart-service-lifecycle-correctness-2026-06-09.md`
- Firmware side of the same contract: `sst-cam-firmware` `docs/solutions/logic-errors/proto-contract-logic-alignment-2026-06-09.md`
- Contract amendment: `sst-cam-proto` `docs/solutions/architecture-patterns/cross-stack-contract-drift-2026-06-09.md`
