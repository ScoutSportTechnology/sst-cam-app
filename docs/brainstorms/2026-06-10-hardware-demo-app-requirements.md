---
date: 2026-06-10
topic: hardware-demo-app
---

# Hardware Demo — App Requirements (intelligence-deferred)

## Summary

Take the app's capture & transfer, preview, overlay, and streaming flows — all built and tested against the mock backend — and make them work against real firmware on a real Jetson over BLE + WiFi Direct, plus add a raw dual-camera record control that produces YOLO training footage. Inherits scope from `docs/brainstorms/2026-06-10-hardware-demo-system-requirements.md`; feeds sequential ce-plan docs.

---

## Problem Frame

The app already runs its full feature surface against the in-app mock (`mock/emulator/`): BLE control, WiFi Direct preview, recording control, downloads, overlay authoring, streaming destinations. None of it has touched real firmware. The contract-first design means the wiring should mostly hold, but real BLE timing, MTU negotiation, WiFi Direct group bring-up, real RTSP, and real HTTP range downloads are unproven.

For the demo the app must drive the real device through every non-intelligence path and add one new capability — raw dual-camera recording — that turns the demo into a training-data capture tool for the upcoming intelligence work.

---

## Requirements

**Real-device control & preview**
- R1. App discovers, pairs, and controls real firmware over BLE (prod backend), honoring the pull model, `correlation_id` matching, and `ChunkedPayload`/`ChunkAck` flow control against real MTU.
- R2. App polls and displays real telemetry on its timer.
- R3. App brings up WiFi Direct against real firmware (`StartWifiDirectCommand` → credentials → join) and renders the real RTSP preview stream in the live-preview view.

**Capture & transfer**
- R4. App controls recording (start/stop) against real firmware and reflects recording state.
- R5. App lists, downloads (WiFi Direct HTTP range), and plays back real recordings.

**Raw dual-camera capture**
- R6. App exposes a control to record **both raw camera feeds**, distinct from the normal cam-0 recording, surfaced clearly as a training-data capture mode.
- R7. App downloads both per-camera raw files and stores them locally with enough metadata (camera id, session, timing) to be usable for labeling.

**Overlay & broadcast**
- R8. App sends existing banner/scoreboard overlay state to real firmware (no new authoring UX) and toggles compositing on outputs.
- R9. App configures a platform stream target (e.g. YouTube RTMP) via the existing streaming-destinations surface and starts/stops the live broadcast.

**Validation**
- R10. The real backend (`main_prod.dart`) is exercised end-to-end against hardware; existing mock-backed widget/unit tests stay green, and real-device integration steps are documented for on-device runs.

---

## Acceptance Examples

- AE1. **Covers R1, R2.** Given a powered Jetson, when the operator pairs in the prod build, then device info and live telemetry display over real BLE.
- AE2. **Covers R3.** Given a paired camera, when the operator opens preview, then the real RTSP cam-0 stream renders in the live-preview view.
- AE3. **Covers R4, R5.** Given preview working, when the operator records then downloads, then the real file plays back in the app.
- AE4. **Covers R6, R7.** Given raw-capture mode, when the operator records a clip, then two per-camera files download and are stored with camera/session metadata.
- AE5. **Covers R8, R9.** Given a configured banner and YouTube target, when the operator starts the broadcast, then the platform shows overlay-composited cam-0 video.

---

## Success Criteria

- Every app flow except intelligence display works against real firmware on real hardware from a single demo session.
- Raw dual-camera footage is captured and pulled to the phone in a form ready to label for YOLO.
- The contract-first design is validated on hardware — divergences between mock and real behavior are surfaced and fixed, not hidden.
- ce-plan can sequence the app work without inventing demo behavior.

---

## Scope Boundaries

- No AI/auto-framing display (intelligence is deferred; no detections/decision to show).
- No new overlay authoring UX — reuse existing authoring.
- No iOS device validation — Android phone for the demo.
- No emulator wiring — real hardware only this session.
- No new local data model beyond what raw-capture metadata requires.

---

## Key Decisions

- **Raw dual record is a first-class app control, framed as training capture:** it is the bridge from this demo to the intelligence phase, so it earns explicit UI rather than a hidden dev toggle.
- **Reuse existing streaming-destinations + overlay-authoring surfaces:** the demo needs them wired to real firmware, not redesigned.
- **Prod backend is the demo target:** mock stays for tests; the demo proves `main_prod.dart` against hardware.

---

## Dependencies / Assumptions

- Firmware exposes recording, raw-capture, overlay-state, preview, and platform-target commands per the proto contract.
- WiFi Direct group bring-up and RTSP/HTTP behave on real radio close enough to the dev mock-camera-wifi service that the existing `WifiService`/`BleService` impls need wiring fixes, not redesign.
- Phases 1–3 app modules hold against real firmware (validated incrementally per system milestones).
- Proto amendments for raw capture / platform target land before the app wires them.

---

## Outstanding Questions

### Deferred to Planning

- [Affects R6, R7][Technical] Local storage shape and metadata schema for paired raw recordings (two files per session, camera id, alignment) — resolve against the raw file format firmware chooses.
- [Affects R1][Technical] Real-MTU chunking edge cases (negotiated MTU below dev assumptions) surfaced only against real BLE.
- [Affects R9][Needs research] Whether the platform-target config needs stream key handling/secret storage in the app, or only passes a target through to firmware.
- [Affects R10][Technical] How real-device integration steps are captured and run (manual runbook now; remote-adb/emulator later).
