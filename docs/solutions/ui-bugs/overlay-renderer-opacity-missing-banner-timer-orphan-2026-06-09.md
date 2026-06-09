---
title: "OverlayLayoutRenderer: opacity ignored on text/circle shapes; banner hide-timer orphaned on unmatched event"
date: 2026-06-09
category: ui-bugs
module: overlay_renderer
problem_type: ui_bug
component: frontend_stimulus
severity: medium
symptoms:
  - "SHAPE_TEXT and SHAPE_CIRCLE elements render at full opacity regardless of the opacity field in the layout spec"
  - "After a match event whose templateId is absent from the layout, the active banner stays visible forever"
  - "Banner hide-timer canceled without a replacement; orphaned banner requires app restart or layout reload to clear"
root_cause: logic_error
resolution_type: code_fix
related_components: [overlay_layout, session_state]
tags: [flutter, overlay, renderer, opacity, banner, timer, spec-compliance, shape-text, shape-circle, ui-bug, did-update-widget]
---

# OverlayLayoutRenderer: opacity ignored on text/circle shapes; banner hide-timer orphaned on unmatched event

## Problem

`OverlayLayoutRenderer` violated two layout spec invariants: the `opacity` field was applied only to `SHAPE_RECT` elements and silently ignored for `SHAPE_TEXT` and `SHAPE_CIRCLE`, and the banner hide-timer was canceled unconditionally when a recognized event arrived, even if no matching template existed in the current layout — orphaning the active banner permanently.

## Symptoms

- Overlay text and circle elements with `opacity < 1.0` rendered at full opacity; only `SHAPE_RECT` respected the field
- When a match event's `labelPrefix` mapped to a known `templateId` but that template was absent from the current layout, the previously visible banner remained on screen indefinitely
- The orphaned banner persisted across subsequent match events and required an app restart or layout reload to clear

## What Didn't Work

Root causes were identified directly through spec comparison and code inspection; no failed intermediate attempts.

## Solution

### Bug J — Opacity not applied to text and circle shapes

**File:** `lib/features/match/session/overlay_renderer.dart`

The `opacity` field on `OverlayStyle` applies to all element types per the `OverlayLayout` spec. Only the `rect` branch had an `Opacity` widget wrapper because it was implemented first; subsequent branches were written without it.

```dart
// Before — opacity silently ignored for text and circle:
case OverlayShape.text:
  return FittedBox(fit: BoxFit.scaleDown, ...);
case OverlayShape.circle:
  return CustomPaint(painter: _OvalPainter(_parseHex(el.style.fillColor)));

// After — all three shapes apply opacity:
case OverlayShape.text:
  return Opacity(
    opacity: el.style.opacity,
    child: FittedBox(fit: BoxFit.scaleDown, alignment: _resolveAlign(el.style.textAlign),
      child: Text(
        _resolveBinding(el.binding, el.style.staticText),
        style: TextStyle(
          color: _parseHex(el.style.textColor),
          fontSize: el.style.fontSize * s,
          fontWeight: el.style.fontWeight == OverlayFontWeight.bold
              ? FontWeight.bold : FontWeight.normal,
          fontFamily: el.style.fontFamily,
        ),
      ),
    ),
  );
case OverlayShape.circle:
  return Opacity(
    opacity: el.style.opacity,
    child: CustomPaint(painter: _OvalPainter(_parseHex(el.style.fillColor))),
  );
```

### Bug K — Banner hide-timer orphaned when template is absent

**File:** `lib/features/match/session/overlay_renderer.dart`

The invariant is: *a timer is canceled only when a new timer is about to replace it.* The old code broke this by canceling before confirming a replacement was possible.

```dart
// Before (buggy) — cancel runs even when template is null:
final templateId = _labelToTemplateId[labelPrefix];
if (templateId != null) {
  final template = widget.layout.templates
      .where((t) => t.eventType == templateId).firstOrNull;
  _bannerTimer?.cancel();       // ← runs even when template == null
  if (template != null) {
    setState(() { _activeBannerTemplate = template; ... });
    _bannerTimer = Timer(Duration(milliseconds: template.durationMs), () { ... });
  }
}

// After (fixed) — cancel only when a replacement is confirmed:
if (templateId != null) {
  final template = widget.layout.templates
      .where((t) => t.eventType == templateId).firstOrNull;
  if (template != null) {
    _bannerTimer?.cancel();     // ← moved inside the guard
    setState(() { _activeBannerTemplate = template; ... });
    _bannerTimer = Timer(Duration(milliseconds: template.durationMs), () { ... });
  }
}
```

## Why This Works

**Bug J:** The `opacity` field is defined by `OverlayStyle` as a universal property applying to all element types. Wrapping all three `_buildElement` branches in `Opacity` ensures the rendered widget tree matches the proto-defined style model regardless of shape type.

**Bug K:** When `template == null`, the cancel executed but the branch body was skipped, leaving `_activeBannerTemplate` set to its previous non-null value with no timer to clear it. Moving the cancel inside the `if (template != null)` guard restores the invariant: the timer is only disturbed when a valid replacement is confirmed.

## Prevention

- When implementing a switch over a sealed enum of shape types, verify that every case applies the same set of universal style properties (`opacity`, `visible`, z-order). A missing property in one branch is a spec violation.
- Add a parameterized widget test asserting `Opacity.opacity == el.style.opacity` for every `OverlayShape` value, run as part of the overlay renderer test suite.
- For any "start timer / cancel timer" state machine pattern: enforce the invariant in code — always cancel and start in the same conditional branch. Name the pattern explicitly (e.g., a `_replaceBannerTimer(Timer)` helper) so the pairing is impossible to miss during review.
- Add a regression test: emit a `BannerEvent` whose `templateId` is absent from the layout, then assert the active banner is still hidden after its original duration (the orphan scenario must not occur).

## Related Issues

- `docs/solutions/integration-issues/wifi-direct-native-platform-channel-correctness-2026-06-09.md` — unrelated but from the same review session
