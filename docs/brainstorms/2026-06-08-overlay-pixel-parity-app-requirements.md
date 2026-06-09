---
date: 2026-06-08
status: ready-for-planning
tags: [overlay, rendering, fonts, pixel-parity, firmware-response]
related_cross_repo: docs/cross-repo/firmware/inbound/2026-06-08-overlay-pixel-parity-contract.md
---

# Overlay pixel-parity — app-side requirements

Response to the firmware team's co-development request
(`docs/cross-repo/firmware/inbound/2026-06-08-overlay-pixel-parity-contract.md`).

## Background

The firmware is building a generic overlay compositor (Cairo + Pango) that renders
`PushOverlayLayout` pixel-for-pixel. For the Flutter in-session preview to match the
camera's recorded output, both sides must agree on fonts, coordinate semantics, and
scaling. This document records the app team's decisions on each open question.

## Decisions (response to firmware)

### 1. Canonical font set

**Inter Regular + Inter Bold** are the canonical overlay fonts for both sides.

- Inter is already the declared theme font in `lib/app.dart` (but currently falls back to
  the system font because the TTF files are not bundled — this is the bug being fixed).
- Font files will be placed in `assets/fonts/Inter-Regular.ttf` and
  `assets/fonts/Inter-Bold.ttf` and declared in `pubspec.yaml`.
- The app will send these exact two file names to the firmware team so they bundle
  the identical binaries. License: OFL 1.1 (bundling in firmware is permitted).
- `OverlayStyle.fontFamily` defaults to `'Inter'` when empty/null; weight `normal` maps to
  Regular, `bold` to Bold.

### 2. Coordinate / anchor / alignment semantics

The app renderer interprets the proto contract as follows. Firmware may treat this as
the canonical shared spec:

| Property | App behaviour |
|---|---|
| Canvas origin | `(0, 0)` = top-left; x right, y down |
| `bounds {x1, y1, x2, y2}` | Absolute canvas pixels; defines the element's rectangular clip |
| `z` order | Higher z rendered on top; `Stack` children ordered by ascending z |
| `font_size` | Canvas pixels, scaled by the **uniform** scale factor (see §3) |
| `text_align` | Left / center / right within `bounds` |
| Vertical text position | Text is scaled down to fit `bounds` if needed (`FittedBox.scaleDown`) and centered vertically within the box |
| `fill_color` / `text_color` | Hex `#RRGGBB` (no alpha channel in color; opacity handled by `opacity` field) |
| `corner_radius` | Canvas pixels, applied as `BorderRadius.circular` |
| `SHAPE_CIRCLE` | Ellipse inscribed in `bounds` (not forced-square) |

### 3. Canvas → surface scaling (uniform scale)

**The app will fix its renderer to use uniform `min(sx, sy)` scale** rather than the
current separate `sx`/`sy`. This matches firmware's stated uniform-scale behaviour.

Current bug: `overlay_renderer.dart` computes `sx = maxWidth / canvasWidth` and
`sy = maxHeight / canvasHeight` separately and applies them independently. If the
preview widget is constrained to a non-16:9 size the element proportions diverge from
firmware. Fixing to `s = min(sx, sy)` centres the canvas within the widget (letterbox
/ pillarbox for odd aspect ratios) and preserves proportions on both sides.

In practice the preview widget is always 16:9 so this is currently moot, but the fix
is low-risk and makes the contract explicit.

### 4. Banner `{{param}}` substitution

The Flutter overlay renderer will implement `{{param_name}}` substitution using
`BannerEventCommand.params`. When a banner template's `static_text` contains
`{{player}}`, `{{number}}`, or any other key, the renderer replaces it with the
matching value from `params` at display time.

This unblocks showing player names / numbers on card and substitution banners. The app
will also start populating `BannerEventCommand.params` when dispatching those events
(separate task — see residual finding #21 from the overlay wiring review).

### 5. `OverlayStyle.fontFamily` field type

`OverlayStyle.fontFamily` will be changed from `String` (empty-string sentinel) to
`String?` (nullable). An absent / null value means "use the canonical Inter font". A
non-empty value means "use this named font if bundled, fall back to Inter". This is
cleaner than the current empty-string check in the renderer and aligns with the proto
field's optional semantics.

## App-side work created

| # | Change | File(s) |
|---|---|---|
| 1 | Bundle Inter Regular + Bold as TTF font assets | `assets/fonts/`, `pubspec.yaml` |
| 2 | Fix renderer: uniform `min(sx, sy)` scale | `lib/features/match/session/overlay_renderer.dart` |
| 3 | Implement `{{param}}` substitution in renderer | `lib/features/match/session/overlay_renderer.dart` |
| 4 | Change `OverlayStyle.fontFamily` to `String?` | `lib/core/models/overlay_layout.dart` |
| 5 | Update `defaultScoreboardLayout()` to use `fontFamily: 'Inter'` | `lib/core/models/overlay_layout.dart` |
| 6 | Update renderer font lookup to use `null`-safe logic | `lib/features/match/session/overlay_renderer.dart` |

## Open question to firmware

> When the proto `font_family` field is empty / absent, does the firmware also default
> to Inter? Please confirm so both sides agree on the fallback.

## Acceptance criteria

- A given `OverlayLayout` renders visually equivalent on the app Flutter preview and
  the camera output: same font, same positions, same alignment, within antialiasing tolerance.
- Inter Regular and Bold produce identical glyph shapes on both platforms (confirmed
  by comparing a scoreboard screenshot from the app against a frame from the camera stream).
- `{{param}}` values in banner templates are substituted at render time.
