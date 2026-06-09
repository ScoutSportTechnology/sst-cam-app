---
date: 2026-06-07
target_repo: app
source_repo: proto
status: open
kind: handoff
related:
  - overlay-rendering.md
  - docs/cross-repo/firmware/inbound/2026-06-08-gatt-uuids-and-overlay-semantics.md
  - docs/plans/2026-06-07-001-feat-overlay-rendering-semantics-plan.md
---

# Overlay rendering semantics moved to the contract repo (+ guarantee reframe)

## Context (proto side)

The firmware↔proto discussion on overlay pixel-parity resolved this way in the
contract repo (`sst-cam-proto`):

- The proto comment's promise of **"pixel-accurate sync"** between the app preview
  and the camera stream is not achievable — the app (Flutter / Skia) and firmware
  (Cairo / Pango) use **independent rasterizers** that differ in text metrics,
  wrapping, hinting, and anti-aliasing.
- The realistic, enforceable guarantee is **visual equivalence within a defined
  tolerance**, backed by **shared reference fixtures**.
- The rules both stacks must render identically are **shared contract**, so they
  now live in the contract repo (the only artifact both consumers pin to the same
  sha) — not in either consumer.

## What proto decided / changed

Shipped in `sst-cam-proto` (PR #1):

1. **New `overlay-rendering.md`** in the contract repo — the normative source for
   overlay rendering: coordinate space, z-order, shapes (incl. `SHAPE_CIRCLE` =
   ellipse inscribed in `bounds`), text layout (`font_size` = em size in canvas
   px, baseline/line-height, word-wrap at `bounds`, alignment, `font_family`
   nearest-available with required `monospace`/`sans-serif`/`serif` faces),
   color/opacity (sRGB, source-over), `corner_radius`, and the conformance
   tolerance + reference-fixture mechanism.
2. **`bluetooth.proto` §11 comment** reworded — no more "pixel-accurate"; points
   to `overlay-rendering.md`. Comment-only; generated bindings unchanged.
3. **`README.md`** now splits ownership: overlay **rendering semantics** live in
   the contract repo; overlay **authoring/UX** stays in the app's
   `docs/firmware-spec.md`.

Tolerance values currently in `overlay-rendering.md` (working contract, adjustable
once both stacks report real fixture results):

| Aspect | Tolerance |
| ------ | --------- |
| Geometry (non-text edges, after scaling) | within ±2 canvas px |
| Color (solid fill / text regions) | per-channel sRGB delta ≤ 4/255 |
| Overall structural similarity (full frame) | SSIM ≥ 0.98 |
| Text regions (each `SHAPE_TEXT` bounding box) | SSIM ≥ 0.95 |

## Ask for the app repo

1. **Carve out `firmware-spec.md`.** Overlay *rendering semantics* are now
   governed by `overlay-rendering.md` in the pinned `proto/` submodule. Trim the
   rendering rules from the app's `docs/firmware-spec.md` and have it **reference**
   `proto/overlay-rendering.md` instead, keeping only overlay *authoring/UX*
   guidance. Avoid two diverging copies of the rendering rules.
2. **Conform the Flutter overlay renderer.** The app's in-session preview renderer
   must implement `overlay-rendering.md` and meet the tolerance against the shared
   reference fixtures. Flag any rule the Flutter/Skia stack cannot meet (e.g. the
   baseline/line-height model, wrapping behavior, `font_family` fallbacks) so the
   contract can be adjusted rather than silently drifting.
3. **Reference fixtures.** The fixtures (input `OverlayLayout` + reference PNG) are
   produced/maintained by the consuming repos against the spec. Decide ownership:
   who generates the canonical reference renders, and where they live so both app
   and firmware validate against the same set. (Open question — see below.)
4. **Pickup is lockstep.** Bump the app's `proto/` submodule to the PR #1 commit
   to get `overlay-rendering.md`; keep the same sha as firmware. See
   `docs/cross-repo/app/coordination.md` (overlay-rendering impact row added).

## Acceptance / what "aligned" looks like

- App `firmware-spec.md` no longer duplicates rendering rules — it points at
  `proto/overlay-rendering.md`; only authoring guidance remains app-side.
- The Flutter renderer is validated against the shared fixtures within tolerance,
  with any unmeetable rules raised back to the contract.
- A clear owner/location for the canonical reference fixtures, used by both stacks.
- App and firmware pin the same `proto/` sha.

## Response (fill in from the app session)

Responded in `docs/cross-repo/proto/outbound/2026-06-09-overlay-rendering-response.md`.

Summary:
- **No reference fixtures** — tolerance spec is sufficient; no canonical PNG system.
- **Submodule bump** — waiting on PR #1 sha; will bump once merged to proto main.
- **firmware-spec.md carve-out** — confirmed; will trim §9 rendering rules and point to `proto/overlay-rendering.md`.
- **Renderer gaps raised** — z-order sort (fix), circle-as-ellipse (fix), word-wrap vs scaleDown (clarification requested from proto).
