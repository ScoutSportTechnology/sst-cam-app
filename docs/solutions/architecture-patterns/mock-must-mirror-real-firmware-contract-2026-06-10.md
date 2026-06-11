---
title: "A mock standing in for a contract consumer must mirror it, or mock-green tests hide cross-stack drift"
date: 2026-06-10
category: architecture-patterns
module: ble_service
problem_type: architecture_pattern
component: service_object
severity: high
applies_when:
  - "A mock/emulator stands in for a real wire-contract consumer (MockBleService/MockWifiService as emulated firmware)"
  - "Adding or changing a proto field that both the app and firmware must honor"
  - "Relying on mock-backed unit/widget tests for app-to-firmware behavior that has no on-hardware coverage"
  - "Building the planned sst-cam-emulator or any second source of contract truth"
tags:
  - mock
  - emulated-firmware
  - cross-stack-drift
  - firmware-contract
  - proto3
  - test-fidelity
  - ble
related_components:
  - mock_ble_service
  - ble_protocol
  - device_handler
  - raw_capture_state
---

# A mock standing in for a contract consumer must mirror it, or mock-green tests hide cross-stack drift

## Context

The app is built contract-first against a test-double BLE/WiFi layer: `MockBleService`
in `lib/mock/emulator/` is the **emulated firmware** that backs both the dev backend
and the test suite. The whole app runs and is tested without hardware.

That makes the mock a **second source of contract truth**. The proto wire contract
(`sst-cam-proto`) has two real consumers — the app and the C++ firmware — but in every
app test the firmware peer is the mock. When the mock's observable wire behavior drifts
from what real firmware actually does, the test suite stays green against a fiction.
Per-repo tests already cannot catch cross-stack semantic drift (see the contract-drift
learning); a mock makes it worse by manufacturing confidence.

A cross-repo review of the raw-capture hardware-demo work surfaced four P1s, **every one
invisible to a fully green app suite** because the mock masked it. This learning captures
the pattern the bugs share, not just the individual fixes.

## Guidance

Treat the mock as part of the contract surface, not as test scaffolding. For every wire
behavior the **real** consumer produces or honors, the mock must reproduce it identically —
in **both** directions:

- **Don't set fields the real peer omits.** If the mock populates a telemetry/response
  field that real firmware can fail to set, app tests pass while the device shows the
  wrong state.
- **Don't omit records/shapes the real peer produces.** If the mock can't reach the same
  list/response state real firmware reaches, the app's happy path is *unreachable in the
  mock* — so "it's tested" is an illusion; the branch never ran.
- **Mirror status/error mapping exactly.** Decode statuses the same way the real wire
  decoder does, or divergent branches pass for the wrong reason.

Make the happy path genuinely reachable in the mock and assert the app's *full* flow
against it. When the proto contract changes, diff the mock against real firmware behavior
in the same change — the mock edit is part of the contract amendment, not a follow-up.

## Why This Matters

A wrong high-fidelity mock is worse than no mock: it produces false green. The danger is
asymmetric and bidirectional —

- Mock **more** capable than firmware → false green (path passes that fails on hardware).
- Mock **less** capable than firmware → dead path (happy path never executes in tests, so
  a real bug there is never exercised).

Both shipped to `main` here under a green suite. The first real on-Jetson bring-up — not
the test suite — would have been where they surfaced. The mock's job is to make that
bring-up boring; a drifted mock does the opposite.

## When to Apply

Any time a test double or emulator stands in for a real consumer of a shared wire contract:
`MockBleService`/`MockWifiService` today, the planned `sst-cam-emulator` next. Especially
when adding a proto field, because the new field has to be wired in *three* places that can
silently disagree — firmware, app, and the mock.

## Examples

All three are real instances from the raw dual-camera capture work (proto fields
`is_raw_capturing` = 14, `RecordingMetadata.is_raw`/`camera_index`/`capture_group_id` = 8–10).

**1. Mock more faithful than firmware → false green.** Real firmware never set telemetry
field 14; the app decoded it; the mock *did* set it — so app tests showed raw-capturing
state correctly while a real device would always report not-capturing.

```dart
// MockBleService — set the field...
GetTelemetryCommand() => proto.CommandResponse(
  telemetry: _makeProtoTelemetry(0),  // includes isRawCapturing: isRawCapturingActive
);
```
```cpp
// firmware DeviceHandler::HandleTelemetry — ...but the real peer forgot it.
t->set_is_recording(is_recording_ && is_recording_());
t->set_is_streaming(is_streaming_ && is_streaming_());
// (no set_is_raw_capturing — field 14 left default-false on every response)
```
Fix: wire `IRawCaptureSink::IsCapturing()` into `DeviceHandler` so the real peer sets it too.

**2. Mock less faithful than firmware → dead happy path.** `stop()` does
`STOP → ListRecordings → filter raw by group → download the pair`. Real firmware writes two
per-camera files stamped with the `capture_group_id` and lists them. The mock's
`_recordings` never contained raw entries, so the filter always returned empty and every
mock-backed run hit the "incomplete" error branch — the download+persist path never ran.

```dart
// MockBleService._buildRecordingListResponse — model what firmware leaves on disk.
final rawGroup = lastRawCaptureGroupId;
if (rawGroup != null) {
  for (var cam = 0; cam < 2; cam++) {
    protoRecs.add(proto.RecordingMetadata(
      id: 'raw__${rawGroup}__cam$cam',
      isRaw: true, cameraIndex: cam, captureGroupId: rawGroup, /* ... */));
  }
}
```

**3. Mock status mapping diverged → branch passed for the wrong reason.** The real
`BleProtocol` maps `UNSUPPORTED → unsupported` and `TIMEOUT → timeout`; the mock collapsed
every non-OK into a generic `error`. The raw pause/resume test asserted only `isOk == false`,
which passed against both — hiding the divergence. Fix: the mock now mirrors
`BleProtocol._statusToResponse` (distinct `unsupported`/`timeout`), and the test asserts
`status == BleResponseStatus.unsupported`.

## Prevention

- When adding a proto field, change **three** call sites in the same unit of work and
  verify they agree: firmware producer, app consumer, and the mock. A field is not "done"
  until the mock produces it exactly as firmware does.
- Prefer assertions that exercise the app's full happy path *through the mock*
  (e.g. `start → list → pair → download → persist`) rather than asserting on the mock's
  side-effect flags — a flag check can pass while the path is unreachable.
- The real gap-closer is an emulator-backed integration suite that runs the same proto
  bytes through real firmware, not the mock (see emulator strategy). Until then, the mock's
  fidelity is load-bearing; review mock changes as contract changes.

## Related Issues

- Firmware + app fixes from this review: `sst-cam-firmware@6c08bff` (telemetry wiring,
  raw-sink race, RTMP reliability), `sst-cam-app@fbb03d7` (download lifecycle, mock fidelity).
- App-side faithful-peer wiring (different angle, same area):
  `docs/solutions/integration-issues/app-firmware-contract-alignment-ble-wiring-2026-06-09.md`
- Contract-drift origin (why semantic drift on a two-consumer contract is the danger):
  `sst-cam-proto` `docs/solutions/architecture-patterns/cross-stack-contract-drift-2026-06-09.md`
- Firmware side of the contract: `sst-cam-firmware`
  `docs/solutions/logic-errors/proto-contract-logic-alignment-2026-06-09.md`
