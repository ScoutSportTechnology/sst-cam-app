---
title: "feat: app-side logic alignment with firmware contract"
type: feat
status: active
date: 2026-06-09
origin: docs/brainstorms/2026-06-08-app-firmware-logic-alignment-requirements.md
---

# feat: App-Side Logic Alignment with Firmware Contract

## Summary

Replace the app's mock/no-op firmware-facing logic with real contract-conformant behavior: transmit session config, chunk large commands and ack inbound chunks, populate banner params, parse responses by payload variant with version checking, and bring the overlay preview into render parity with firmware — so the app actually interoperates against the amended proto contract.

---

## Problem Frame

An audit found the app and firmware share the wire format but diverge in behavior, with the app carrying the larger share of blockers because much of its firmware-facing layer is still mock or no-op. `pushSessionConfig` never transmits; outbound commands are never chunked and inbound chunks never acked; `banner_event` omits the jersey/params the preview substitutes locally; responses are parsed off the outbound command type; `protocol_version` is never read; and several overlay-preview rules drift from firmware's renderer. The net effect is an app that looks like setup succeeded but sends commands a real camera cannot act on, and renders a preview the camera cannot match. This plan covers `sst-cam-app`; it implements against the amended contract (proto plan `docs/plans/2026-06-09-001-feat-logic-alignment-contract-plan.md`).

---

## Requirements

- R1. Transmit `push_session_config` with all contract fields (origin R1).
- R2. Send `banner_event` with `params` + `player_id` (origin R2).
- R3. Chunk outbound commands exceeding MTU (origin R3).
- R4. Ack inbound multi-chunk responses + reassemble by `chunk_index` (origin R4).
- R5. Parse `CommandResponse` by payload variant (origin R5).
- R6. Surface `UNSUPPORTED` distinctly + check `protocol_version` (origin R6).
- R7. Stop dropping needed response fields (origin R7).
- R8. Clamp `corner_radius` to half smaller side (origin R8).
- R9. Render text `fill_color` background box per the KEEP decision (origin R9).
- R10. Baseline/font handling + unknown-shape skip in preview (origin R10).
- R11. Honor `WifiDirectGroupResponse.role` (origin R11).

**Origin acceptance examples:** none defined in origin.

---

## Scope Boundaries

- No firmware or proto changes (sibling plans).
- Commands the app never sends (`set_wifi_config`, `set_streaming_config`, `factory_reset`, `firmware_update`) stay unimplemented.
- No live BLE round-trip or side-by-side render-tolerance harness — per-repo unit tests only.

### Cross-Repo Scope (Sibling Plans, Same Release)

Concurrent prerequisites in the same coordinated lockstep release — not later-release work.

- Contract amendments: `sst-cam-proto` plan `docs/plans/2026-06-09-001-feat-logic-alignment-contract-plan.md`.
- Firmware symmetric chunking/render fixes: `sst-cam-firmware` plan `docs/plans/2026-06-09-001-feat-logic-alignment-firmware-plan.md`.

### Deferred to Follow-Up Work

- Unrelated mock layers (RTSP playback, chunked HTTP download) except where they block a listed unit.

---

## Context & Research

### Relevant Code and Patterns

- `lib/core/ble/ble_protocol.dart` — `encodeCommand` (L30), `decodeResponse` (L50), `_toProtoCommand` (L80), `_mapOkResponse` (L190), `_dartLayoutToProto`/`_dartElementToProto`. Single proto↔Dart translation boundary.
- `lib/core/ble/ble_service_impl.dart` — `pushSessionConfig` no-op (L262), `sendCommand` (L220); chunk reassembly in private `_ConnectedDevice` (`_startResponseListener` L350, single-chunk fast path L358, accumulate-by-correlationId L370+).
- `lib/features/match/session/overlay_renderer.dart` — `OverlayLayoutRenderer` widget; `_buildElement`, `_resolveBinding`, `_parseHex`, `_resolveTextAlign`, `_OvalPainter`.
- `lib/core/wifi/wifi_service_impl.dart` — `connectGroup`/`disconnectGroup`; sends Start/StopWifiDirectCommand.
- `lib/core/models/` — plain Dart view models (`command.dart`, `overlay_layout.dart`, `telemetry.dart`); proto bindings in `lib/models/proto/` (gitignored, `just gen-proto`).

### Institutional Learnings

- `docs/solutions/ui-bugs/overlay-renderer-opacity-missing-banner-timer-orphan-2026-06-09.md` — opacity ignored on TEXT/CIRCLE; banner hide-timer orphan. Directly relevant to U6.
- `docs/solutions/logic-errors/wifi-direct-dart-service-lifecycle-correctness-2026-06-09.md` — WifiService timeouts, subscription leak, concurrent-connect dedup. Relevant to U7.
- `docs/solutions/architecture-patterns/app-source-of-truth-drift-sqlite-2026-05-06.md` — app-as-source-of-truth, stateless BLE executor; frames the session-config contract.

---

## Key Technical Decisions

- Keep `BleProtocol` as the single proto↔Dart boundary; all new encode/decode logic lands there, not scattered across features. Rationale: matches existing architecture, keeps the translation testable in one place.
- Chunking/ack live in `_ConnectedDevice` (already owns the reassembly buffers) and `encodeCommand` (outbound split). Rationale: co-locate with existing partial implementation.
- Preview render fixes conform to the amended `overlay-rendering.md` (uniform scale already correct app-side; add clamp, text bg box, baseline). Rationale: contract is the arbiter.

---

## Open Questions

### Resolved During Planning

- Mock library: none — use hand-written doubles (`MockBleService`) + Riverpod overrides, per repo convention.
- Test location: BLE tests flat under `test/ble/`; renderer tests under `test/features/match/session/`.

### Deferred to Implementation

- Exact MTU value / negotiation hook on the app BLE stack — discover from the transport code at implementation time.
- `protocol_version` mismatch UX (block vs warn) — follow the behavior the amended contract states (proto U4).

---

## Implementation Units

- U1. **Transmit `push_session_config` with full payload**

**Goal:** Remove the no-op; serialize and send session config with all contract fields, in the contract-mandated order (after WiFi Direct, before overlay).

**Requirements:** R1

**Dependencies:** proto plan U4 (§11 ordering) for the contract-published ordering. NOTE: the `PushSessionConfigCommand` proto fields (incl. team id/name/color) already exist in the vendored contract — this unit is NOT blocked on the proto3-optional change (proto U2), which only affects overlay element fields. Re-bump is a verification step, not a code blocker.

**Files:**
- Modify: `lib/core/ble/ble_service_impl.dart` (`pushSessionConfig` L262)
- Modify: `lib/core/ble/ble_protocol.dart` (add a dedicated `encodeSessionConfig` helper — do NOT route through `_toProtoCommand`)
- Modify: `lib/core/models/command.dart` (add `teamAId`/`teamBId`/`teamAName`/`teamBName` to `PushSessionConfig` — currently only color hex fields exist)
- Modify: `lib/features/match/session/setup_screen.dart` (~L347 — source the team id/name fields at the call site)
- Test: `test/ble/ble_service_impl_proto_test.dart`

**Approach:**
- **Preserve "Fix 14":** `PushSessionConfig` is deliberately NOT a `BleCommand` (see `command.dart:62-65`); the dedicated `pushSessionConfig()` method is the correct API. Do NOT re-add it to the sealed hierarchy. Instead add `BleProtocol.encodeSessionConfig(config, corrId)` that builds `proto.Command(pushSessionConfig: ...)` wrapped in `ChunkedPayload`, and have `pushSessionConfig()` write it via the connection + await a response (mirroring `sendCommand`'s completer/timeout machinery), bypassing the `_toProtoCommand` switch.
- Add the four team id/name fields to the Dart `PushSessionConfig` model and thread them from `setup_screen.dart:347`.
- Ensure the setup flow ordering (WiFi Direct → session → overlay) holds; firmware U8 enforces it.

**Patterns to follow:** `sendCommand`'s completer/timeout/correlation-id machinery (do not reuse its `_toProtoCommand` switch).

**Test scenarios:**
- Happy path: a populated session model encodes to a `Command` with `push_session_config` set and every contract field present (team a/b id, name, color, match uuid, output paths, periods).
- Edge case: optional fields (rtmp_url/stream_key) absent → encoded as unset, not empty-string.
- Integration: `pushSessionConfig` results in a real write through `sendCommand` (assert via `MockBleService` capture), not a `Future.value()` no-op.

**Verification:** sending session config produces a wire write; no path returns without transmitting.

---

- U2. **Populate `banner_event` params and player_id**

**Goal:** Send the jersey/params the preview substitutes locally so firmware template substitution matches.

**Requirements:** R2

**Dependencies:** None

**Files:**
- Modify: `lib/features/match/session/session_screen.dart` (banner construction ~L326)
- Modify: `lib/core/ble/ble_protocol.dart` (`_toProtoCommand` banner branch ~L159)
- Test: `test/ble/ble_service_impl_proto_test.dart`

**Approach:**
- Thread the event-sheet jersey number and any `{{param}}` values into `BannerEventCommand.params` + `player_id` before encode.

**Patterns to follow:** how the preview's `_resolveBinding` reads the local params map — mirror those keys on the wire.

**Test scenarios:**
- Happy path: a banner event with jersey "10" encodes with `params["jersey"]="10"` (and/or `player_id`) populated.
- Edge case: banner with no params → encodes with empty params, no crash.

**Verification:** wire `params`/`player_id` match what the preview substitutes for the same event.

---

- U3. **Chunk outbound commands over MTU**

**Goal:** Split large serialized commands into ordered `ChunkedPayload` frames instead of always one frame.

**Requirements:** R3

**Dependencies:** proto plan U5 (symmetric ack wording)

**Files:**
- Modify: `lib/core/ble/ble_protocol.dart` (`encodeCommand` L30)
- Modify: `lib/core/ble/ble_service_impl.dart` (outbound write path / `sendCommand`)
- Test: `test/ble/ble_service_impl_proto_test.dart`

**Approach:**
- **U3 + U4 are one coupled chunk-transport rewrite, not an extension.** Today `encodeCommand` (`ble_protocol.dart:30-39`) hard-codes `chunkIndex:0, totalChunks:1` and `sendCommand` does a single `write` (L235); there is no outbound chunking at all.
- When the serialized command exceeds the chunk size, emit N `ChunkedPayload` frames with sequential `chunk_index`, shared `correlation_id`, `total_chunks=N`. This requires `sendCommand` to become an **ack-gated write loop** (multiple writes awaiting the inbound `ChunkAck` between frames), where today it registers one completer per correlation-id assuming a single outstanding write — confirm the ack-wait loop reuses or replaces that completer model.

**Patterns to follow:** existing single-chunk envelope construction in `encodeCommand`; the `_ConnectedDevice` correlation-id completer/timeout machinery (extended, not as-is).

**Test scenarios:**
- Happy path: a sub-MTU command emits exactly one frame `{chunk_index:0, total_chunks:1}` (unchanged behavior).
- Edge case: a command just over the chunk size emits 2 frames with correct indices/total and identical `correlation_id`.
- Edge case: a large `push_overlay_layout` (many elements) splits into the expected frame count.
- Error path: a missing/late `ChunkAck` does not advance to the next chunk before timeout.

**Verification:** large commands transmit fully; frame indices/total are correct.

---

- U4. **Ack inbound chunks + reassemble by index**

**Goal:** Acknowledge each inbound response chunk and reassemble by `chunk_index`, not arrival order.

**Requirements:** R4

**Dependencies:** proto plan U5

**Files:**
- Modify: `lib/core/ble/ble_service_impl.dart` (`_ConnectedDevice._startResponseListener` L350+)
- Test: `test/ble/ble_service_impl_proto_test.dart`

**Approach:**
- The current reassembly (`_startResponseListener` L363-368) concatenates `buf + chunk.data` **in arrival order** and ignores `chunk_index`. Replace the `Uint8List`-per-correlationId buffer with an **index-addressed structure** (e.g. `Map<int,List<int>>` per correlationId): place `data` at `chunk_index`, complete when all indices present.
- On each received `ChunkedPayload`, write a `ChunkAck{correlation_id, chunk_index}` back. The receive path must also **disambiguate an inbound `ChunkAck`** (for U3's outbound chunking flow-control) from an inbound `ChunkedPayload` response — mirror the firmware's convention (`total_chunks==0` → ack).

**Patterns to follow:** existing accumulate-by-correlationId buffers (rewritten to index-addressed); firmware's ack-vs-payload disambiguation.

**Test scenarios:**
- Happy path: a 3-chunk response reassembles to the correct payload and emits 3 acks.
- Edge case: out-of-order arrival (index 2 before 1) still reassembles correctly.
- Edge case: duplicate chunk index is ignored, not double-counted.
- Integration: a multi-chunk `recording_list`/`thumbnail` response decodes end-to-end.

**Verification:** multi-chunk responses no longer stall; acks are emitted per chunk.

---

- U5. **Parse responses by payload variant, with version + status handling**

**Goal:** Decode `CommandResponse` by its actual payload, surface `UNSUPPORTED` distinctly, check `protocol_version`, and stop dropping needed fields.

**Requirements:** R5, R6, R7

**Dependencies:** proto plan U4 (protocol_version requirement)

**Files:**
- Modify: `lib/core/ble/ble_protocol.dart` (`decodeResponse` L50, `_mapOkResponse` L190, `_dartTelemetry`)
- Modify: `lib/core/models/command.dart` (surface `unsupported` status; device-info/telemetry fields)
- Test: `test/ble/ble_service_impl_proto_test.dart`

**Approach:**
- Switch on `resp.whichPayload()` rather than the outbound command type. Map `ResponseStatus.UNSUPPORTED` to the existing `BleResponseStatus.unsupported` (currently never produced). Read `DeviceInfoResponse.protocol_version` and raise a clean version-skew signal on mismatch per contract. Carry `battery_level_pct` and the dropped device-info fields into the Dart models.

**Patterns to follow:** existing `_mapOkResponse` structure; `decodeResponse` correlation-id check at L59.

**Test scenarios:**
- Happy path: each response variant (device_info, telemetry, recording_list, download_token, match_state, thumbnail, wifi_direct_group) decodes from its own payload.
- Edge case: `OK` status with an empty/mismatched payload is detected (not silently read as defaults).
- Error path: `UNSUPPORTED` surfaces distinctly from generic `ERROR`; `error_message` preserved.
- Error path: `protocol_version` mismatch raises the version-skew signal.
- Happy path: telemetry decode includes `battery_level_pct`.

**Verification:** responses parsed off payload; version skew detectable; no needed field dropped.

---

- U6. **Overlay preview render parity**

**Goal:** Clamp corner radius, paint the text `fill_color` background box (KEEP), align baseline/fonts, and skip unknown shapes.

**Requirements:** R8, R9, R10

**Dependencies:** proto plan U3 (hardened render rules). The `corner_radius` clamp rule is already in `overlay-rendering.md` §Color & opacity ("a value larger than half the smaller side of `bounds` is clamped to that half") — conform to the existing rule.

**Files:**
- Modify: `lib/features/match/session/overlay_renderer.dart` (`_buildElement`, text branch, `_OvalPainter`)
- Test: `test/features/match/session/overlay_renderer_test.dart`

**Approach:**
- Clamp `corner_radius` to `min(w,h)/2` (conforming to the existing contract rule). For `SHAPE_TEXT` with non-empty `fill_color`, paint a background box over `bounds` behind the glyphs (wrap a `Container`/`DecoratedBox` + `Text` inside the existing per-element `Opacity`).
- Apply the baseline rule (first-line baseline one ascent below bounds top) within Flutter's constraints — best-effort, since Flutter's `Text` lays out from the top of the line box; exact baseline needs `Baseline`/`TextPainter` work. Ensure a metric-comparable family for `monospace`/`sans-serif`/`serif`.
- **Do NOT re-add per-element opacity** — it is already applied on all three shape branches (`overlay_renderer.dart:134,148,168`); that specific bug is already fixed.
- `SHAPE_UNKNOWN` skip: the Dart `OverlayShape` enum is exhaustive (`rect/text/circle`) and the renderer is outbound-only (it never decodes an inbound layout), so there is no constructable "unknown" value today — note the enum is exhaustive by construction; no skip branch or test is needed unless inbound layout decoding is added later.

**Patterns to follow:** existing `_buildElement` switch and the `SHAPE_RECT` fill path (reuse for the text background); the opacity/banner-timer learning doc (`overlay-renderer-opacity-missing-...`) — note it documents an already-resolved bug.

**Test scenarios:**
- Happy path: a text element with `fill_color` renders a background box widget plus the text.
- Edge case: `corner_radius` larger than half the smaller side renders clamped (capsule), not overflowing.
- Happy path: existing covered cases in the renderer test file still pass (z-order, circle inscribed, text wrap/clip).

**Verification:** preview matches the amended contract rules for the audited divergences.

---

- U7. **Honor WiFi Direct role**

**Goal:** Use `WifiDirectGroupResponse.role` rather than parsing and ignoring it.

**Requirements:** R11

**Dependencies:** None

**Files:**
- Modify: `lib/core/wifi/wifi_service_impl.dart` (`connectGroup` / group handling)
- Modify: `lib/core/models/wifi.dart` (already carries `role`)
- Test: `test/wifi/wifi_service_impl_test.dart` (new — the existing `test/mock/mock_wifi_service_test.dart` exercises the mock, not the impl, so it won't cover the role change). Testing `connectGroup` role handling needs a fake `BleService` returning a `WifiDirectGroup` with a chosen `role`, plus a seam past the `Platform.isIOS` / `WifiP2pChannel` (native EventChannel) calls.

**Approach:**
- Branch join behavior on `role` (camera as group owner vs client); at minimum assert/guard the expected role and surface a clear error if the camera reports an unexpected role.

**Patterns to follow:** the wifi-direct lifecycle learning doc; existing `connectGroup` dedup/timeout handling.

**Test scenarios:**
- Happy path: a group response with the expected GO role connects normally.
- Error path: an unexpected role surfaces a clear error rather than proceeding on a fixed assumption.

**Verification:** `role` is read and affects/guards behavior; no longer dead.

---

## System-Wide Impact

- **Interaction graph:** `BleProtocol` is the single translation boundary — U1/U2/U3/U5 all flow through it; `_ConnectedDevice` owns chunk state (U3/U4).
- **Error propagation:** U5 makes `UNSUPPORTED` and version-skew first-class instead of flattened to generic error.
- **State lifecycle risks:** chunk buffers (U4) must clear on completion/disconnect to avoid leaks; mirror existing reassembly cleanup.
- **API surface parity:** session-config and overlay encoders must stay in sync with firmware's decoders (cross-repo, contract-mediated).
- **Unchanged invariants:** the proto↔Dart boundary stays in `BleProtocol`; feature code keeps using plain Dart view models.

---

## Risks & Dependencies

| Risk | Mitigation |
|------|------------|
| Generated proto Dart is gitignored — stale bindings hide schema changes | Run `just gen-proto` after the proto re-bump before implementing/testing |
| Chunking change could regress the working single-chunk path | Keep the single-chunk fast path; test it explicitly (U3 happy path) |
| Cross-repo: app encoders must match firmware decoders | Both implement the same amended contract; verify field-by-field against `bluetooth.proto` |
| App preview and firmware use different rasterizers | Contract tolerance is perceptual, not pixel-identical; conform to rules, not bytes |

---

## Dependencies / Prerequisites

- Most of the contract surface this plan consumes (`ChunkAck`, `ResponseStatus.UNSUPPORTED`, `protocol_version`, `battery_level_pct`, `PushSessionConfigCommand` fields) is **already vendored** in this checkout — only the proto3-`optional` change for `visible`/`opacity` (proto U2) and the doc amendments (proto U1/U3/U4/U5) are new, and those affect U6 render conformance, not the BLE-encoding units.
- After the proto submodule pin moves to the amended commit, run `just gen-proto` to regenerate the (gitignored) Dart bindings. Treat the proto dependency as a verification step, not a hard blocker for the BLE-encoding units (U1-U5).

---

## Sources & References

- **Origin document:** [docs/brainstorms/2026-06-08-app-firmware-logic-alignment-requirements.md](docs/brainstorms/2026-06-08-app-firmware-logic-alignment-requirements.md)
- Sibling plans: `sst-cam-proto` `docs/plans/2026-06-09-001-feat-logic-alignment-contract-plan.md`, `sst-cam-firmware` `docs/plans/2026-06-09-001-feat-logic-alignment-firmware-plan.md`
- Test patterns: `test/ble/ble_service_impl_proto_test.dart`, `test/features/match/session/overlay_renderer_test.dart`
