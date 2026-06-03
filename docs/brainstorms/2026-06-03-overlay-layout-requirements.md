---
title: Overlay Layout System — App Renderer + Session BLE Wiring
date: 2026-06-03
status: draft
---

# Overlay Layout System — App Renderer + Session BLE Wiring

## Problem

The session screen has a hardcoded scoreboard widget driven entirely by local `LiveMatchState`. The camera's overlay renderer and the app's Flutter overlay are disconnected: design changes must be made in two places and there is no guarantee they match. Session commands (recording control, match events, score updates, banner events, overlay layout push) exist in the proto but are absent from the Dart command layer — nothing is ever sent to the camera during a session.

---

## Goals

1. App and camera render the same overlay spec — sync is guaranteed by construction, not convention.
2. All session BLE commands are wired: recording control, streaming control, match events, score updates, banner events, and overlay layout push.
3. The Flutter overlay renderer is driven by the same `OverlayLayout` Dart model that is sent to the camera.
4. Overlay design changes happen in one place (the Dart model layer) and propagate to both app and camera automatically.

## Non-goals

- User-editable overlay templates or a layout designer in the app UI.
- Multiple named layout presets (e.g. per-sport variants).
- Resending `PushOverlayLayoutCommand` mid-session from a UI control.
- Video playback overlay integration with the new model (existing `OverlayState` / `overlay_helper.dart` system is unchanged).
- iOS build.

---

## Architectural principle (user-stated)

**Dart models are the contracts. Proto definitions are serialization of those models.**

The `OverlayLayout` types live in `lib/core/models/` as plain Dart classes. The proto
definitions mirror them. The app, its widgets, and its tests depend only on Dart models.
Proto encoding is a concern of `BleProtocol` / `BleServiceImpl` only — consistent with how
the rest of the BLE layer is structured.

---

## Requirements

### R1 — Overlay layout Dart model

A new file `lib/core/models/overlay_layout.dart` defines:

- `OverlayLayout` — canvas size, list of persistent elements, list of templates
- `OverlayElement` — id, shape, bounds (`OverlayRect`), style (`OverlayStyle`), binding, visibility
- `OverlayRect` — `x1`, `y1`, `z`, `x2`, `y2` in canvas pixels
- `OverlayStyle` — fill color, text color, opacity, corner radius, font family/size, text align, font weight, static text
- `OverlayTemplate` — event type string, duration ms, list of elements
- `OverlayBinding` enum — STATIC, SCORE_A, SCORE_B, SCORE_VS, TEAM_A_NAME, TEAM_B_NAME, MATCH_CLOCK, PERIOD_LABEL
- `OverlayShape` enum — RECT, TEXT, CIRCLE
- Supporting enums: `TextAlign` (LEFT, CENTER, RIGHT), `FontWeight` (NORMAL, BOLD)

The default canvas is 1920 × 1080. (0, 0) is top-left; z = 0 is the video background.

### R2 — Default scoreboard layout factory

A factory function in `lib/core/models/overlay_layout.dart` produces the canonical scoreboard `OverlayLayout` from session config (team names and color hex strings). This is the single definition of the scoreboard design used by both the app and the camera. It must include:

- Scoreboard background bar (RECT)
- Home team name (TEXT, `BINDING_TEAM_A_NAME`)
- Away team name (TEXT, `BINDING_TEAM_B_NAME`)
- Score display (TEXT, `BINDING_SCORE_VS`)
- Period label (TEXT, `BINDING_PERIOD_LABEL`)
- Clock (TEXT, `BINDING_MATCH_CLOCK`)
- Standard banner templates: `goal`, `yellow_card`, `red_card`, `substitution`

The layout produced by this factory is the ground truth. Any visual discrepancy between the app preview and the camera stream/recording indicates a bug.

### R3 — LiveMatchState carries team colors

`LiveMatchState` gains `homeColorHex` and `awayColorHex` fields (nullable string). These are
sourced from `TeamInfo.colorHex` at session initialization. The overlay factory (R2) and the
Flutter renderer (R4) use these fields to colour team labels and scoreboard accents.

### R4 — Flutter overlay renderer widget

A new widget renders an `OverlayLayout` + `LiveMatchState` onto a positioned/scaled surface:

- Accepts `OverlayLayout` and `LiveMatchState` as inputs.
- Scales canvas coordinates to the available preview surface dimensions.
- Renders `SHAPE_RECT` as filled rectangles (with optional corner radius and opacity).
- Renders `SHAPE_TEXT` as text, substituting bound values from `LiveMatchState`:
  - `BINDING_SCORE_A/B/VS` → current scores from state
  - `BINDING_TEAM_A/B_NAME` → team names from state
  - `BINDING_MATCH_CLOCK` → `state.clockText`
  - `BINDING_PERIOD_LABEL` → `state.phaseLabel` mapped to P1/P2/HT/FT per firmware spec §9.3
- Active banner templates are shown for their `duration_ms` and then hidden.
- Replaces the hardcoded `_LiveThumb` scoreboard widget in `session_screen.dart`.

### R5 — BleCommand sealed class completions

`lib/core/models/command.dart` gains the following sealed subclasses (currently absent):

| Class | Fields |
|-------|--------|
| `PushSessionConfigCommand` | *(was a one-off method; unified into sealed class)* |
| `RecordingControlCommand` | `action` (START / STOP / PAUSE / RESUME) |
| `StreamingControlCommand` | `action` (START / STOP), `rtmpUrl` (nullable) |
| `MatchControlCommand` | `action` (KICKOFF / PERIOD_END / PERIOD_START / FINAL_WHISTLE / CLOCK_PAUSE / CLOCK_RESUME), `period` |
| `ScoreUpdateCommand` | `teamId`, `delta` |
| `BannerEventCommand` | `templateId`, `params` (Map<String, String>), `durationSeconds` |
| `PushOverlayLayoutCommand` | `layout` (OverlayLayout) |

### R6 — BleService interface extensions

`lib/core/ble/ble_service.dart` exposes the new commands through the same
`sendCommand<T>(BleCommand cmd)` surface (or equivalent). `BleProtocol` encodes and decodes
all new command types.

### R7 — MockBleService handles new commands

`lib/mock/emulator/mock_ble_service.dart` returns `OK` for all new commands. Additionally:

- `RecordingControlCommand(START)` → sets mock `isRecording = true` in next telemetry tick
- `RecordingControlCommand(STOP)` → sets `isRecording = false`
- `StreamingControlCommand(START)` → sets `isStreaming = true`
- `StreamingControlCommand(STOP)` → sets `isStreaming = false`
- All other new commands → `OK` with no state side effect

### R8 — Session BLE command wiring

During a live session, when the user takes the following actions the corresponding BLE command is sent to the camera **in addition to** updating local `LiveMatchState`:

| User action | BLE command sent |
|-------------|-----------------|
| Tap "Start Recording" | `RecordingControlCommand(START)` |
| Tap "Stop Recording" | `RecordingControlCommand(STOP)` |
| Tap "Pause Recording" | `RecordingControlCommand(PAUSE)` |
| Tap "Resume Recording" | `RecordingControlCommand(RESUME)` |
| Toggle streaming on | `StreamingControlCommand(START, rtmpUrl)` |
| Toggle streaming off | `StreamingControlCommand(STOP)` |
| Tap "Kick Off" (period 1) | `MatchControlCommand(MATCH_KICKOFF, period=1)` |
| Tap "End Period" | `MatchControlCommand(MATCH_PERIOD_END, period=N)` |
| Tap "Start Period N" | `MatchControlCommand(MATCH_PERIOD_START, period=N)` |
| Tap "Final Whistle" | `MatchControlCommand(MATCH_FINAL_WHISTLE, period=N)` |
| Clock pause (VAR / stoppage) | `MatchControlCommand(MATCH_CLOCK_PAUSE, period=N)` |
| Clock resume | `MatchControlCommand(MATCH_CLOCK_RESUME, period=N)` |
| Goal scored | `ScoreUpdateCommand(teamId, +1)` + `BannerEventCommand("goal", params, 5)` |
| Yellow card | `BannerEventCommand("yellow_card", params, 4)` |
| Red card | `BannerEventCommand("red_card", params, 4)` |
| Substitution | `BannerEventCommand("substitution", params, 4)` |

If BLE is not connected when the action fires, the command is dropped silently (local state still updates). No retry, no queue.

### R9 — Session setup sequence

At session start (before recording can begin), the app sends in order:

1. `PushSessionConfigCommand` — team IDs, names, colors, periods, RTMP URL, paths
2. `PushOverlayLayoutCommand` — the layout produced by the factory (R2) for this session's config

The same `OverlayLayout` used in step 2 is also stored in session state and passed to the Flutter renderer (R4). This is the guarantee: both halves render the same object.

---

## Scope boundaries

### Deferred

- User-editable overlay layouts or a layout designer screen
- `PushOverlayLayoutCommand` resend during an active session (firmware supports it; app UI does not yet)
- Video playback overlay integration with the new `OverlayLayout` model

### Out of scope

- Overlay canvas editor
- Non-scoreboard layout types
- Firmware implementation (covered by `docs/firmware-spec.md`)

---

## Dependencies and assumptions

- `TeamInfo.colorHex` already exists in `lib/core/models/match.dart`; it just needs to be threaded through to `LiveMatchState`.
- The default scoreboard layout (R2) is hardcoded — not user-configurable in v1.
- BLE must be connected for session commands to reach the camera; the app functions in local-only mode when disconnected (dev workflow, mock emulator).
- `PushSessionConfigCommand` needs the same `MatchConfig`-derived data it uses today — unifying it into the sealed class should be a pure structural refactor with no behavior change.
- Where BLE command dispatch lives (`LiveMatchController` vs UI layer) is an open implementation decision for planning.

---

## Success criteria

- Tapping "Kick Off" in the app → `MatchControlCommand` visible in mock logs and telemetry `is_recording` flips as expected.
- Scoreboard overlay in the Flutter preview and the scoreboard layout sent to the camera are built from the same factory call.
- Changing the default scoreboard design (e.g. moving the score box) in one place (the factory) updates both the Flutter widget and the `PushOverlayLayoutCommand` payload with no other code changes.
- All existing tests continue to pass. New commands covered by unit tests in `test/ble/`.
- `just ci` passes.

---

## Related

- `docs/firmware-spec.md` §8.2 (session workflow), §9 (overlay layout spec), §10 (command reference)
- `proto/bluetooth.proto` §11 (overlay messages)
- `lib/features/match/session/session_screen.dart` — `_LiveThumb` widget to replace
- `lib/features/match/session/session_state.dart` — `LiveMatchController`, `LiveMatchState`
- `lib/core/models/command.dart` — sealed `BleCommand` hierarchy
- `lib/mock/emulator/mock_ble_service.dart`
