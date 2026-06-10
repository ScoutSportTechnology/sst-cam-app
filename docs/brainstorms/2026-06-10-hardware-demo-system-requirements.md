---
date: 2026-06-10
topic: hardware-demo-system
---

# Hardware Demo — System Spec (intelligence-deferred)

## Summary

A cross-repo demo that lights the entire SST Cam pipeline on real Jetson hardware and a real phone — dual capture, orchestration, postprocess, storage, download, overlay, RTSP preview, and RTMP-to-platform streaming — with the **Intelligence** layer (AI → physics → decision) replaced by a static "always cam 0, full frame" decision stand-in. This is the hub spec; `sst-cam-firmware`, `sst-cam-app`, and `sst-cam-proto` each carry a sibling requirements doc that inherits the scope and definition-of-done fixed here.

---

## Problem Frame

Full operation — including intelligence — is needed in three weeks. Intelligence (TensorRT model, physics, dynamic camera/crop decision) is the hardest, longest, and most hardware-coupled part of the build, and none of it has started. Meanwhile the firmware modules around it are mostly built as isolated ports but have never run as a wired pipeline on the device: orchestration, storage, streaming, and overlay are all "not started," and the app's capture & transfer flow has only ever run against the in-app mock backend.

The risk is discovering hardware, GStreamer, BLE/WiFi-Direct, and cross-stack integration problems late, stacked on top of unfinished intelligence work, with no slack. The cost is a failed full-operation deadline.

This demo pulls all the non-intelligence integration risk forward: everything except intelligence is made to work on real hardware first, so the intelligence work lands on a proven, moving pipeline rather than a paper one. A side benefit compounds directly into the intelligence phase — recording raw dual-camera footage produces the training data the AI model needs.

---

## Actors

- A1. **Operator** — person running the demo; holds the phone, drives the app, points the camera at action.
- A2. **App** (`sst-cam-app`) — Flutter companion on an Android phone; always initiates, controls firmware over BLE, pulls preview/downloads over WiFi Direct.
- A3. **Firmware** (`sst-cam-firmware`) — C++ runtime on the Jetson Orin Nano with dual IMX477; runs the pipeline, responds to commands, never pushes.
- A4. **Proto** (`sst-cam-proto`) — shared wire contract both stacks build against; gates any new command/descriptor the demo needs.
- A5. **Streaming platform** — external RTMP/HLS endpoint (e.g. YouTube) that receives the live broadcast.

---

## Key Flows

- F1. **Proof-of-life (M0)**
  - **Trigger:** Operator opens app, scans, taps the real `sst-cam-NNNN` Jetson.
  - **Actors:** A1, A2, A3
  - **Steps:** App discovers by UUID + name prefix → BLE pair → MTU negotiate → poll telemetry on timer → display device info + live telemetry.
  - **Outcome:** App is paired to real firmware and polling telemetry over BLE on hardware.
  - **Covered by:** R1, R2

- F2. **Live preview (M1)**
  - **Trigger:** Operator taps "preview" after pairing.
  - **Actors:** A1, A2, A3
  - **Steps:** App sends `StartWifiDirectCommand` → joins WiFi Direct group → firmware orchestration runs dual capture → static decision picks cam 0 full-frame → postprocess → RTSP H.264 on `:8554` → app renders live preview.
  - **Outcome:** Operator sees live cam-0 video on the phone; the full hardware pipeline is moving frames.
  - **Covered by:** R3, R4, R5, R6

- F3. **Record and transfer (M2)**
  - **Trigger:** Operator taps record, later taps stop, then download.
  - **Actors:** A1, A2, A3
  - **Steps:** App start-recording command → firmware storage sink writes final (cam-0) frames to a file → stop → app lists recordings → pulls file over WiFi Direct HTTP (range) → plays it back locally.
  - **Outcome:** A cam-0 recording exists on device and is downloaded and playable on the phone.
  - **Covered by:** R7, R8, R9

- F4. **Raw dual-camera capture for training (M3)**
  - **Trigger:** Operator enables raw-capture mode and records a match.
  - **Actors:** A1, A2, A3
  - **Steps:** App raw-record command → firmware taps both materialized per-camera streams → writes two raw files (one per camera) → app downloads both.
  - **Outcome:** Synchronized raw footage from both cameras on the phone, usable as YOLO training data.
  - **Covered by:** R10, R11

- F5. **Overlay + broadcast (M4–M5)**
  - **Trigger:** Operator configures banner/scoreboard and a platform stream target, starts streaming.
  - **Actors:** A1, A2, A3, A5
  - **Steps:** App sends overlay state + platform target → firmware overlay module renders banner/scoreboard → composites onto final frames → streaming sink pushes RTMP/HLS to the platform.
  - **Outcome:** A live, overlay-composited cam-0 broadcast is visible on the external platform.
  - **Covered by:** R12, R13, R14

---

## Requirements

**Pipeline (firmware)**
- R1. Firmware advertises, pairs, and answers commands over BLE on real hardware, honoring the pull model and `correlation_id` matching.
- R2. Firmware serves telemetry on demand over BLE on real hardware.
- R3. Pipeline orchestration wires both cameras through capture → preprocess → materialize → per-camera buffer with real worker threads, running on the Jetson.
- R4. A static decision stand-in selects **camera 0, full sensor frame, no crop/zoom**, implemented behind a real swappable decision port so the intelligence layer can replace it later without rewiring.
- R5. Postprocess runs on the chosen (cam-0) frame and feeds the final buffer.

**Outputs (firmware)**
- R6. Firmware streams the final frames as RTSP H.264 over WiFi Direct for live preview.
- R7. A storage sink records the final (cam-0) frames to a file on device, start/stop controlled by the app.
- R8. Recordings are served for download over the WiFi Direct data plane (HTTP with range support).
- R10. A raw-capture path records **both cameras' materialized frames** to per-camera files, independent of the decision/postprocess path.
- R12. An overlay module renders the app-authored banner/scoreboard and composites it onto final frames when enabled.
- R13. A streaming sink pushes the (optionally overlaid) final frames to an external RTMP/HLS platform target.

**App**
- R9. App controls recording and downloads/plays a finished recording against real firmware.
- R11. App exposes raw dual-camera record control and downloads both raw files.
- R14. App configures the platform stream target and sends overlay state to firmware; live preview view renders the real RTSP stream.

**Contract (proto)**
- R15. The wire contract covers every command/descriptor the demo needs (recording control, WiFi Direct handshake, RTSP descriptor, overlay state, platform-stream target, raw-capture control); any gap is added as a backward-compatible optional amendment, not a breaking change.

---

## Acceptance Examples

- AE1. **Covers R1, R2.** Given a powered Jetson advertising `sst-cam-0001`, when the operator pairs in the app, then the app shows device info and telemetry updating on its poll timer.
- AE2. **Covers R3, R4, R5, R6.** Given a paired camera, when the operator starts preview, then live cam-0 video renders on the phone within a few seconds, sourced from the orchestrated pipeline (not a canned file).
- AE3. **Covers R7, R8, R9.** Given preview is working, when the operator records 10s then downloads, then the downloaded file plays back the recorded cam-0 footage on the phone.
- AE4. **Covers R10, R11.** Given raw-capture enabled, when the operator records a clip, then two per-camera raw files exist and both download to the phone, frame-aligned enough to label.
- AE5. **Covers R12, R13, R14.** Given a banner/scoreboard and a YouTube RTMP target configured, when the operator starts the broadcast, then the platform shows live cam-0 video with the overlay composited on top.

---

## Success Criteria

- The operator demonstrates, on real Jetson + real phone, every path except intelligence: pair, telemetry, live preview, record, download, raw dual record, overlay, and platform broadcast.
- Integration risk for the full-operation deadline is retired: GStreamer, BLE, WiFi Direct, storage, and streaming are proven working together on hardware before intelligence work begins.
- The decision stand-in is a clean seam — dropping in real AI/physics/decision requires replacing one port implementation, not restructuring the pipeline.
- Raw dual-camera footage is being captured and is usable as YOLO training data.
- Each per-repo requirements doc is concrete enough that ce-plan can produce its sequential plans without inventing demo scope or definition-of-done.

---

## Scope Boundaries

- **Intelligence is out** — no AI/tracking model, no physics/world-coordinate estimation, no dynamic camera/crop decision. The decision stage is a fixed cam-0 stand-in.
- **Emulator is out** — deferred to a separate session; the demo targets real hardware.
- **No dynamic camera switching or zoom** — cam 0, full frame, for the whole demo.
- **No new overlay authoring UX** — reuse the app's existing authoring; only on-device render + composite is new.
- **Microphone / dual-mic audio is out.**
- **iOS device validation is out** — demo runs on an Android phone.
- **Hardware-bound tests are written but not expected to pass in the devcontainer** — they pass on-device later (per firmware test convention); a remote-compile / remote-adb or emulator path for running them is a future, separate concern.

---

## Key Decisions

- **Static decision behind a real port, not a hack:** keeps the intelligence drop-in to a single port swap and exercises the real orchestration handoff during the demo. Rationale: the demo's whole purpose is to de-risk the pipeline the intelligence layer will plug into.
- **Raw dual record built inside orchestration, not later:** the demo already runs both cameras through materialize; tapping those frames to disk is cheap there and yields training data — the bridge to the intelligence phase. Rationale: highest-leverage add, near-zero marginal cost on top of work already required.
- **Live preview is milestone 1 (proof-of-life):** cheapest end-to-end proof that the hardware pipeline moves frames. Rationale: fail fast on the integration-riskiest path.
- **System spec + per-repo docs:** prevents the app⇄firmware drift the repos' own `docs/solutions/` already warn about, while mapping to the per-repo sequential-plan workflow.

---

## Dependencies / Assumptions

- Physical Jetson Orin Nano + dual IMX477 + an Android phone are available for on-device validation.
- Phases 1–2 (contract, connect & control) hold on real hardware; M0 validates this assumption first.
- Proto changes needed for the demo are additive/optional (no `protocol_version` break expected); confirmed in the proto requirements doc.
- The WiFi Direct data plane (RTSP preview + HTTP download) behaves on real radio as the mock-camera-wifi service modeled it in dev.

---

## Outstanding Questions

### Deferred to Planning

- [Affects R3][Technical] Threading/orchestration model for the worker threads (per-camera + shared consumer) — decide in the firmware plan.
- [Affects R13][Needs research] RTMP/HLS push from Jetson NVENC over the phone-shared or separate network path — bandwidth and network topology for the live platform stream.
- [Affects R6, R13][Technical] Whether RTSP preview and RTMP platform stream share one encode or run two encodes — resolve in the firmware plan.
- [Affects R10][Technical] Raw file format/container for per-camera capture that is both writable on the hot path and labelable for YOLO — resolve in the firmware + app plans.
