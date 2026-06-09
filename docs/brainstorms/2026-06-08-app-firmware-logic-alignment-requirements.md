---
date: 2026-06-08
topic: app-firmware-logic-alignment
---

# App ⇄ Firmware Logic Alignment — App Slice

## Summary

Replace the app's mock/no-op firmware-facing logic with real contract-conformant behavior — wire session config onto the link, implement BLE chunking + acks, populate banner params, harden response parsing and version checking, and fix the overlay-preview render rules — so the app actually interoperates with firmware against the shared proto contract.

---

## Problem Frame

An audit (2026-06-08) found the app and firmware share the wire format but diverge in behavior, and the app side carries the larger share of the blockers because much of its firmware-facing layer is still mock or no-op ("pending firmware wiring"). `pushSessionConfig` never transmits; outbound commands are never chunked and inbound chunks are never acked; `banner_event` is sent without the jersey/params the preview substitutes locally; responses are parsed off the outbound command type rather than the response payload; `protocol_version` is never read; and several overlay-preview rules (corner-radius clamp, text background, baseline) drift from the renderer firmware uses. The net effect is that an app that looks like it completed setup sends overlay and recording commands a real camera cannot act on, and renders a preview the camera cannot match.

This slice covers the `sst-cam-app` repo. Contract amendments are in the proto slice (`proto/docs/brainstorms/2026-06-08-app-firmware-logic-alignment-requirements.md`); firmware fixes in `sst-cam-firmware`.

---

## Requirements

**Session + command transmission**
- R1. Wire `push_session_config` to actually serialize and send over BLE (remove the no-op), populating all contract fields including the team id/name/color fields currently omitted.
- R2. Send `banner_event` with its `params` and `player_id` populated from the data the event sheet already collects, so firmware template `{{param}}` substitution matches the preview.

**BLE framing**
- R3. Chunk outbound commands that exceed the negotiated MTU into `ChunkedPayload` frames per the contract, instead of always emitting a single frame.
- R4. Acknowledge inbound multi-chunk responses with `ChunkAck` per the contract's flow-control rule, and reassemble by `chunk_index` rather than arrival order.

**Response handling**
- R5. Parse each `CommandResponse` by its actual payload variant (check which payload is set) rather than inferring it from the outbound command type.
- R6. Surface `UNSUPPORTED` distinctly from generic error, and read + check `DeviceInfoResponse.protocol_version` to detect wire-format skew per the amended contract (R8 of the proto slice).
- R7. Stop dropping fields the app needs from responses (e.g. telemetry `battery_level_pct`, device-info fields).

**Overlay preview parity**
- R8. Clamp `corner_radius` to half the smaller side of `bounds`, matching the firmware/contract clamp.
- R9. Render the text `fill_color` background box (or not) consistently with the resolved contract decision (R2 of the proto slice).
- R10. Implement the baseline / metric-comparable-font handling and a skip path for unknown shapes, so preview stays inside the contract's render tolerance.

**WiFi Direct**
- R11. Honor the `WifiDirectGroupResponse.role` field rather than parsing and ignoring it.

---

## Success Criteria

- A session started in the app results in real `push_session_config`, chunked-as-needed `push_overlay_layout`, and recording commands reaching firmware — no silent no-op in the setup path.
- For any `OverlayLayout` the app authors, its preview matches firmware's render within the contract tolerance (the audited render divergences are gone).
- Every audited app finding has a unit test (encode/decode, response parsing, or overlay render) that runs in the app dev container, and a reviewer can map each test to its finding.

---

## Scope Boundaries

- No firmware or proto changes in this slice (sibling docs cover those).
- Commands the app never sends (`set_wifi_config`, `set_streaming_config`, `factory_reset`, `firmware_update`) stay unimplemented — consistent with firmware.
- No live BLE round-trip integration test or side-by-side render-tolerance harness this pass — per-repo unit tests only.
- Mock layers unrelated to the audited gaps (e.g. RTSP playback, chunked HTTP download) are out of scope except where they block a listed requirement.

---

## Key Decisions

- Contract is the binding arbiter; the app conforms to the (possibly amended) proto + `overlay-rendering.md`. Rationale: single source of truth, set in the proto slice.
- Verification is app-side unit tests in the dev container, one per finding. Rationale: chosen done-signal; catches regression without standing up cross-repo infrastructure.

---

## Dependencies / Assumptions

- Proto slice contract decisions (R2 / R6 / R7 there) gate R2, R9, and any command-disposition work here — resolve them first.
- Firmware slice must land the symmetric chunking/ack and render fixes for end-to-end behavior, but each repo's tests are independent.

---

## Outstanding Questions

### Deferred to Planning

- [Affects R3, R4][Technical] Exact MTU negotiation and chunk-size handling on the app's BLE stack — answer during planning from the transport code.
- [Affects R6][Technical] What the app does on a `protocol_version` mismatch (block, warn, degrade) — follows the amended contract's stated behavior.
