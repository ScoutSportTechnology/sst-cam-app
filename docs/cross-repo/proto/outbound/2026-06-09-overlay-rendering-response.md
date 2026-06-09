---
date: 2026-06-09
target_repo: sst-cam-proto
source_repo: app
status: open
kind: response
related:
  - docs/cross-repo/proto/inbound/2026-06-07-overlay-rendering-split-and-tolerance.md
---

# Response: overlay rendering semantics split + tolerance

In response to `2026-06-07-overlay-rendering-split-and-tolerance.md`.

## Our decisions

### 1. Reference fixtures — no canonical PNG needed

We do not want a golden-image / reference-PNG fixture system. The layout is
simple shapes and x/y coordinates; the JSON spec + the tolerance values in
`overlay-rendering.md` are sufficient as the contract. Both stacks render
independently and are expected to stay within tolerance by following the spec.
No canonical PNG needs to be generated, stored, or validated against.

**Ask for proto:** No fixture infrastructure needed from the contract repo.
The tolerance table in `overlay-rendering.md` stands as-is.

### 2. Submodule bump — waiting on PR #1 sha

We will bump the app's `proto/` submodule to the PR #1 commit once it is
merged to `sst-cam-proto` main. Please share the sha or tag when it lands.
We will then regenerate Dart bindings and verify `flutter analyze`.

### 3. firmware-spec.md carve-out — confirmed

We will trim the rendering rules from `docs/firmware-spec.md` §9 and replace
them with a reference to `proto/overlay-rendering.md`. Only overlay
authoring/UX guidance (bindings, templates, the example layout JSON) stays
app-side.

### 4. Renderer conformance — known gaps to raise

After reviewing `overlay-rendering.md`'s summary in the inbound doc, we
identify two likely gaps in our Flutter/Skia renderer to raise against the
spec:

**Gap A — Z-order not sorted:** Our renderer draws elements in array order
from `OverlayLayout.elements`. If a layout sends elements out of `z` order
the render will be wrong. We will fix this (sort by `z` before drawing).

**Gap B — `SHAPE_CIRCLE` renders a circle, not an ellipse:** Flutter's
`BoxShape.circle` inscribes a circle in the bounding box. The spec says
"ellipse inscribed in `bounds`". If `x2-x1 ≠ y2-y1` the output differs.
We will fix this by using `BoxShape.rectangle` + `BorderRadius.circular`
with the shorter half-dimension, or `CustomPainter` with an oval path.

**Gap C — Text layout is scale-down, not word-wrap:** We use
`FittedBox(BoxFit.scaleDown)` which shrinks text to fit bounds rather than
wrapping it. The spec says word-wrap at bounds. For scoreboard use the
difference is invisible (single numbers/names fit easily), but it will
diverge for long static text. Please confirm whether `scaleDown` is an
acceptable deviation or whether the spec requires true word-wrap.

We will flag any further gaps after reading the full `overlay-rendering.md`
once the submodule is bumped.
