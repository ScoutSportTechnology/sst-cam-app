---
date: 2026-06-09
source_repo: proto
target_repo: app
status: open
kind: handoff
related:
  - docs/cross-repo/proto/outbound/2026-06-09-overlay-rendering-response.md
  - docs/cross-repo/proto/inbound/2026-06-07-overlay-rendering-split-and-tolerance.md
---

# Handoff: overlay-rendering conformance — PNG reference dropped

Resolves the open items in `2026-06-09-overlay-rendering-response.md`.

## What changed in the contract

`overlay-rendering.md` §Conformance was amended (additive to the rules, but a
relaxation of the conformance method — re-bump required):

- **No canonical / golden reference PNG.** Removed the "reference rendering (PNG)
  per fixture" requirement and the fixture-infrastructure expectation.
- Conformance is now **the two stacks' own outputs compared side-by-side within
  tolerance**, not measured against a stored reference image.
- Tolerance table is **unchanged**: geometry ±2 canvas px, color ≤4/255 per
  channel, full-frame SSIM ≥0.98, text-region SSIM ≥0.95.

No wire/`.proto` change. This is a docs-only contract edit.

## What the app must do

1. **Re-bump the `proto/` submodule** to the latest `sst-cam-proto` main (the
   commit that merges this handoff + the §Conformance amendment). Current pin is
   `8a158d1`, which predates the amendment.
2. **Renderer Gap C** — confirmed *not* an acceptable deviation. §Text mandates
   word-wrap, top-align, clip-to-bounds, "no shrink-to-fit". Replace
   `FittedBox(scaleDown)`. *(Done in this pass — `overlay_renderer.dart` now uses a
   word-wrapping, top-aligned, clip-to-bounds `Text`; also fixed text that was
   vertically centered → top-aligned.)*
3. **Gaps A (z-order) and B (circle=ellipse)** — confirmed correct, already
   implemented; no further action.

## What the app does NOT need to do

- No reference-PNG generation, storage, or validation. No fixture harness.
