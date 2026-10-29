# Requirements — Multi-cam recording, overlay ownership & dual preview (Bug #6)

**Date:** 2026-06-26
**Scope:** Deep — joint app + firmware + proto architecture change
**Source:** `docs/handoffs/2026-06-26-bug-sweep-and-local-dev-workflow.md` (Bug #6)
**Status:** decisions locked, ready for planning

## Problem

Today the firmware records a single MP4 with overlay **baked in**, and the app
*also* renders the same overlay on its live preview — the two rasterizers
(firmware Cairo, app Skia) must be kept perceptually identical (the SSIM/tolerance
machinery in `proto/overlay-rendering.md`). That dual-render sync is the convoluted
logic to remove. We also want both cameras captured for AI training, and a way to
retrieve footage with *or* without overlays without paying duplicate storage.

## Terminology (locked — "raw" was overloaded)

- **L0 — raw:** exactly what each sensor sees. cam0 + cam1. Internal / AI-training / dev only. Never user-facing.
- **L1 — post-processed:** chosen camera, zoom / color-correct / resize. **No overlay.** This is the canonical match video (what today is mislabelled "raw match.mp4").
- **L2 — overlayed:** L1 with overlay baked in. **Never stored** — produced on demand.

## Decisions (locked)

1. **Overlay is firmware-owned, single-rasterizer.** The broadcast/RTMP stream
   originates from the Jetson, so overlay *must* be baked firmware-side for the
   outbound stream. Given that, the app **stops rendering overlay entirely** — on
   both live preview and playback. The app only displays the firmware-baked stream
   and sends `PushOverlayLayout` commands. → The app↔firmware perceptual-equivalence
   contract (`proto/overlay-rendering.md` tolerances/SSIM) is **retired**.

2. **Recording splits clean from overlaid.** Firmware records **clean L1** plus an
   **overlay-timeline** (the layout events over time, timestamped — tiny data, the
   app authored it). No burned L2 file is ever stored. The live/stream tap still
   gets the overlaid frame.

3. **L0 raw** reuses the existing dual raw-capture path (cam0 + cam1), unchanged in
   spirit. Internal/training, not surfaced to the user.

4. **Overlayed retrieval = on-demand Jetson burn.** When a user asks for the
   overlayed video, firmware replays the overlay-timeline onto L1, encodes L2, sends
   it, deletes it. App stays 100% overlay-free. Accepted cost: software re-encode on
   the no-NVENC Orin Nano. Mitigations: run as a **background job** (app
   requests → polls → downloads), **never during a live session**; most retrieval is
   highlight-clip length, not full match.

5. **Dual preview = firmware-composited single stream.** A side-by-side (cam0 | cam1)
   view is composited **on the firmware** and served as one RTSP stream. The app stays a
   single VLC view. A dropdown drives a `set-preview-layout` command (single |
   side-by-side). The single-cam live view carries baked overlay; side-by-side is a
   clean monitoring view ("see what both cameras see").
   **Correction (review):** the existing `GstOverlayCompositor` is the overlay-over-video
   *source* half, **not** a dual-camera compositor — it is NOT the starting point. A new
   dual-input stage is required (`videomixer`/`compositor`, or CPU `cv::hconcat`). And the
   side-by-side encode contends with the live x264 budget on the no-NVENC Jetson — gated on
   a benchmark. **This is the most expensive, riskiest #6 unit and a DEFER candidate** (see
   firmware plan F6d + Scope).

## The recording matrix (result)

```
always (internal):   L0 cam0  +  L0 cam1                  raw, sensor-exact
on "record match":  +L1 post-processed (clean)            canonical video
                    +overlay-timeline (data)              authored by app
retrieve "clean":    send L1
retrieve "overlayed": firmware burns L2 = L1 + timeline, sends, deletes
broadcast/stream:    firmware composites overlay live (ephemeral, not stored)
```

Both caveats the user raised are resolved by storing overlay as **data, not a file**:
no duplicate storage, and any past clip can be overlayed later (or have its overlay
changed) because record-time overlay state no longer constrains retrieval.

## Success criteria

- App contains **zero** overlay-rendering code paths (live or playback).
- A match yields: 2× L0 raw, 1× L1 clean MP4, 1× overlay-timeline. No stored L2.
- "Download overlayed" returns an L2 produced on demand, then cleaned up on-device.
- Live preview supports single-cam (overlaid) and side-by-side (clean) via a dropdown,
  switched by one firmware command. Same control on the match preview.
- The broadcast/RTMP stream carries the baked overlay (firmware-side).

## Key seams that must agree (app ⟂ firmware ⟂ proto)

1. **Recorder tap is clean.** Firmware fan-out must split: `tee → recorder (clean L1)`
   and `tee → overlay-composite → streaming/RTSP (overlaid)`. Today overlay is
   composited *before* the fan-out (both branches overlaid) — that is the core
   firmware change.
2. **Overlay-timeline persistence + replay.** Firmware must timestamp & persist every
   `PushOverlayLayout` and be able to replay it for the on-demand burn. New proto:
   a "download/export overlayed" command + job/poll/transfer, and overlay-timeline
   storage tied to the recording's `capture_group_id`/match uuid.
3. **Preview layout control.** New proto `set-preview-layout` (single | side_by_side).
   `PreviewStreamDescriptor` stays single-stream (firmware composites), but aspect can
   now be 9:16 / 1080×1920 — descriptor already carries width/height, app must stop
   hardcoding 16:9.
4. **`camera_index` referent** stays pinned to `nvarguscamerasrc sensor-id` 0/1 on
   both stacks (already consistent). Side-by-side ordering must honor it.

## Out of scope / deferred

- ≥3 *simultaneously encoded* H.264 streams (rejected — no NVENC, software x264 won't
  sustain it; the clean-L1 + on-demand-burn model avoids needing it).
- App-side video compositing / export burn (rejected in favor of Jetson on-demand burn;
  revisit only if Jetson burn proves too slow in practice).
- L0 raw encoding/compression strategy (currently NV12) — secondary, decide during
  firmware planning.

## Follow-on docs

- App plan: `docs/plans/2026-06-26-app-bug-sweep-and-multicam.md`
- Firmware plan: `sst-cam-firmware/docs/plans/2026-06-26-firmware-bug-sweep-and-multicam.md`
- `docs/firmware-spec.md` must be updated to this model (single recording → clean L1 +
  timeline; overlay firmware-only; preview layouts).
