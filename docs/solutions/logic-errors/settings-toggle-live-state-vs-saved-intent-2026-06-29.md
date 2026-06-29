---
title: "A settings toggle that displays live device state must not persist that live state as configured intent"
date: 2026-06-29
category: logic-errors
module: settings
problem_type: logic_error
component: widget_state
severity: medium
symptoms:
  - "Opening a settings page and tapping Save (with no edit) silently flips a persisted enabled flag from false to true"
  - "An interface the device brought up on its own (NM-managed ethernet) shows the toggle ON even though the stored config disabled it — and Save makes that ON durable"
  - "The control that shows 'is it up right now' and the control that means 'should it be enabled' are the same widget, so reading reality writes intent"
tags:
  - settings
  - toggle
  - intent-vs-state
  - riverpod
  - persistence
  - ble
---

## Problem

Settings → Network derived the enable toggle from `config.enabled || result.up`
so the toggle would reflect the interface being **live** (a deliberate UX choice
— the user wanted the green dot + toggle to show "up"). But `_collect()` then sent
that same live-derived value back as the configured `enabled` on Save. So merely
opening the page over a live NM-managed ethernet and tapping Apply persisted
`enabled = true` even though the user never intended to enable it — reading
reality silently rewrote intent, and the flip survived reboot.

The root cause is conflating two different questions in one boolean:
**"is this interface up right now?"** (live, observed) vs **"should this interface
be enabled?"** (intent, persisted). A toggle that answers the first must not be
the source of truth for the second.

## Fix

Separate display from saved intent. Keep the toggle's **displayed** value
live-derived, but track the **original configured** value and a per-control dirty
flag; on collect, send the live-derived state only if the user actually toggled
it, otherwise preserve the original stored intent. See
`lib/features/settings/network/network_settings_page.dart`:

```dart
_ethEnabled       = config.ethernet.enabled || result.ethernetUp; // DISPLAY (live)
_ethConfigEnabled = config.ethernet.enabled;                      // original INTENT
_ethToggleDirty   = false;                                        // set true in onChanged
// ...
enabled: _ethToggleDirty ? _ethEnabled : _ethConfigEnabled,       // _collect()
```

## Why it matters / how to apply

Any settings control that mirrors live device/hardware state is exposed to this.
The test that catches it: load with `configured=false` + `live=true`, **do not
touch the toggle**, Save, and assert the pushed config still has `enabled=false`;
plus a second test that toggling on pushes `enabled=true`. Whenever a single
widget shows both "current reality" and "desired setting," split the two — display
from one source, persist from another, and only let an explicit user action move
intent. Related: [[mock-must-mirror-real-firmware-contract-2026-06-10]] (the mock
must reproduce the live-vs-configured distinction or the test passes falsely).
