---
title: "feat: Overlay Layout System — App Renderer + Session BLE Wiring"
type: feat
status: completed
date: 2026-06-03
origin: docs/brainstorms/2026-06-03-overlay-layout-requirements.md
---

# feat: Overlay Layout System — App Renderer + Session BLE Wiring

## Summary

Implements the `OverlayLayout` Dart model hierarchy and default scoreboard factory, extends `TeamRecord` with a color field (with picker in team registration), extends the `BleCommand` sealed class with six new session commands (recording, streaming, match control, score update, banner event, overlay push), and wires all session BLE commands from the session screen. The Flutter overlay renderer replaces `_LiveThumb`'s hardcoded scoreboard with a widget driven by the same `OverlayLayout` object sent to the camera — guaranteeing visual parity by construction. Home team color flows from the team registration DB record; away color is null in v1 (opponent is a string, not a linked `TeamRecord`).

---

## Problem Frame

The session screen has a hardcoded scoreboard widget driven entirely by local `LiveMatchState`. The camera's overlay renderer and the Flutter overlay are disconnected: design changes must be made in two places and there is no guarantee they match. Session commands (recording control, match events, score updates, banner events, overlay layout push) exist in the proto but are absent from the Dart command layer — nothing is ever sent to the camera during a session.

(see origin: docs/brainstorms/2026-06-03-overlay-layout-requirements.md)

---

## Requirements

- R1. A new `OverlayLayout` Dart model hierarchy lives in `lib/core/models/overlay_layout.dart`
- R2. A default scoreboard factory produces the canonical `OverlayLayout` for a session
- R3. `LiveMatchState` carries `homeColorHex` sourced from the home team's DB `TeamRecord.colorHex`; `awayColorHex` is always null in v1 (opponent is a string label, not a linked `TeamRecord`) — the overlay factory uses a grey fallback for the away team
- R4. A Flutter overlay renderer widget drives from `OverlayLayout` + `LiveMatchState`
- R5. `BleCommand` sealed class gains six new subclasses: `RecordingControlCommand`, `StreamingControlCommand`, `MatchControlCommand`, `ScoreUpdateCommand`, `BannerEventCommand`, `PushOverlayLayoutCommand` (`PushSessionConfigCommand` unification is deferred — see Scope Boundaries)
- R6. `BleService` interface and `BleProtocol` encode/decode all new command types
- R7. `MockBleService` handles all new commands with appropriate state side effects
- R8. All session user actions send the corresponding BLE command alongside local state updates
- R9. Session setup sends `PushSessionConfig` then `PushOverlayLayout`; both halves share the same `OverlayLayout` object

**Origin actors:** A1 (coach/user operating the app during a live match session)
**Origin flows:** F1 (session setup), F2 (live match control), F3 (overlay design change propagation)
**Origin acceptance examples:**
- AE1 (R8, R9): Tap "Kick Off" → `MatchControlCommand` visible in mock logs; `isRecording` flips as expected
- AE2 (R2, R4, R9): Same factory call produces both the Flutter widget layout and the BLE payload
- AE3 (R2, R4): Changing the default scoreboard design (factory) updates both Flutter and camera payload with no other code changes

---

## Scope Boundaries

- No user-editable overlay templates or a layout designer screen
- No `PushOverlayLayoutCommand` resend from a live session UI control
- No video playback overlay integration with `OverlayLayout` (existing `OverlayState`/`overlay_helper.dart` unchanged)
- No iOS build
- Away team `colorHex` is always null in v1 — opponent is a string label, not a linked `TeamRecord`; the factory uses a default grey accent for the away team
- `PushSessionConfigCommand` is NOT unified into the sealed hierarchy in this plan; `pushSessionConfig` stays as a dedicated `BleService` method; `pushOverlayLayout` is added in parallel
- The existing `MatchControlAction` enum in `match.dart` is not changed; a new `BleMatchControlAction` enum is added in `command.dart`

### Deferred to Follow-Up Work

- `PushOverlayLayoutCommand` resend during an active session from UI
- Video playback overlay bridge from `OverlayLayout` model
- `PushSessionConfigCommand` unification into `sendCommand<T>` sealed class
- Linking opponent team to a registered `TeamRecord` (enables away team color from DB)
- Setting away team color at session setup time from a UI picker

---

## Context & Research

### Relevant Code and Patterns

- `lib/core/models/command.dart` — sealed `BleCommand` hierarchy; `BleCommandResponse<T>`; `PushSessionConfig` payload class (dedicated, not sealed). Comment "Fix 14" explains why `PushSessionConfigCommand` was removed from the hierarchy.
- `lib/core/ble/ble_protocol.dart` — stateless `BleProtocol` with `_toProtoCommand()` and `_mapOkResponse()` exhaustive switch statements; each new command needs an arm in both
- `lib/mock/emulator/mock_ble_service.dart` — three parallel exhaustive switches (`_encodeCommand`, `_buildResponse`, `_mapResponse`) that must be extended atomically with new `BleCommand` subclasses
- `lib/features/match/setup_screen.dart` — `_startMatch` calls `ble.pushSessionConfig()` then `widget.onStart()`; stable `_matchUuid` guard for retry idempotency
- `lib/features/match/session/session_screen.dart` — `_LiveThumb` scoreboard overlay (target of R4 replacement); `_BottomControls` recording/streaming callbacks; `_kickoff` and `_confirmEnd` phase callbacks; `connected` guard pattern
- `lib/features/match/session/session_state.dart` — `LiveMatchController` (pure local state, no BLE dispatch); `loadFromUpcoming` hydration path
- `lib/core/db/tables/teams_table.dart` — `TeamsTable`; no `colorHex` column today
- `lib/core/models/team.dart` — `TeamRecord` (no `colorHex`); `TeamDraft` (no `colorHex`)
- `lib/features/teams/team_form_sheet.dart` — team create/edit form (gains color picker)
- `lib/models/proto/bluetooth.pb.dart` — proto bindings for `PushOverlayLayoutCommand`, `OverlayLayout`, `OverlayElement`, `OverlayRect`, `OverlayStyle`, `OverlayTemplate` already committed
- `test/mock/mock_ble_service_test.dart` — pattern: fresh instance `connectionDelay: Duration.zero`, `failureRate: 0.0`, assert `resp.isOk`
- `test/ble/ble_service_impl_proto_test.dart` — direct `BleProtocol` static method tests

### Institutional Learnings

- **Layer boundary** (`docs/solutions/logic-errors/core-importing-feature-layer-inversion-2026-05-26.md`): Core model files must contain only pure data — no feature-layer imports. The overlay factory takes plain strings; it must not import `LiveMatchState` or session types. Factory calls and BLE wiring live at the feature layer.
- **Connection state guards** (`docs/solutions/conventions/isdevbackend-must-not-bypass-connection-state-guards-2026-05-19.md`): Every BLE-dispatching control must have a null callback or guard when disconnected. Never use `kAppEnv.isDevBackend ||` as a bypass. `MockBleService` already handles the full connected state.
- **Session setup / app as source of truth** (`docs/solutions/architecture-patterns/app-source-of-truth-drift-sqlite-2026-05-06.md`): Camera is a stateless executor; app pushes everything at session start. `OverlayLayout` is app-owned data — no retrieval commands needed from the camera.
- **StreamSubscription hygiene** (same doc): Any `listen()` in Riverpod notifiers must be cancelled via `ref.onDispose()`.

---

## Key Technical Decisions

- **`pushOverlayLayout` as dedicated `BleService` method, not `sendCommand<void>`**: Mirrors the existing `pushSessionConfig` pattern. Keeps `_startMatch`'s async error-handling and retry UI clean without restructuring the sealed hierarchy for setup-sequence calls.
- **Default scoreboard factory accepts only plain strings**: `defaultScoreboardLayout({required String homeName, required String awayName, String? homeColorHex, String? awayColorHex}) → OverlayLayout`. No feature-layer imports. Layer boundary preserved per institutional learning.
- **`OverlayLayout?` stored in `LiveMatchState`**: Nullable; null before session setup completes and after `reset()`. Renderer shows blank canvas when null. Set via `LiveMatchController.setOverlayLayout(OverlayLayout)`.
- **BLE dispatch in `SessionScreen`, not `LiveMatchController`**: Controller stays pure local state. Session screen already holds `liveMatchProvider.notifier` + `bleServiceProvider` refs. BLE calls added alongside controller method calls via a `_sendIfConnected` helper.
- **`_sendIfConnected(WidgetRef ref, BleCommand cmd)` helper in `session_screen.dart`**: Reads `activeCameraIdProvider` and `connectionStateProvider`, dispatches `sendCommand<void>` only when connected, discards the `Future`. Centralizes the 15+ disconnect-guard sites.
- **Banner timer: single active slot in overlay renderer widget `State`**: A `Timer` is created on each banner-triggering state change; a new banner overwrites the previous `Timer`. Session screen is never navigated away from during an active session, so widget `State` lifetime is stable.
- **Team color picker: fixed set of basic colors in team registration**: Options: white, black, green, red, blue, yellow, orange. Default/no-color mapped to a neutral grey (`#808080`) in the factory when `colorHex` is null. Stored as a hex string (e.g. `'#FF0000'`).
- **U4 + U5 must land atomically**: Adding `BleCommand` subclasses makes `MockBleService`'s exhaustive switches non-exhaustive immediately (compile error). Both files must be in the same commit.
- **`periodLabelForOverlay` getter on `LiveMatchState`**: Returns firmware §9.3 strings without changing the existing `phaseLabel` getter (used by `_TopBar` and `_ScoreBlock`).
- **Two-step setup failure recovery**: If `pushOverlayLayout` fails after `pushSessionConfig` succeeds, show the same `_pushError` + Retry UI. Retry re-runs both steps; step 1 is idempotent (stable `_matchUuid`); step 2 is stateless on camera side (resending is safe).
- **`toggleRecPause` BLE dispatch reads `state.rec` before the controller call**: The current `rec` state determines whether START, PAUSE, or RESUME is the correct BLE command to send. Reading after `ctl.toggleRecPause()` would see the already-mutated state.

---

## Open Questions

### Resolved During Planning

- **Keep `pushSessionConfig` as dedicated method?**: Yes — keep it, add `pushOverlayLayout` in parallel. (see Key Technical Decisions)
- **BLE dispatch location for session actions?**: `SessionScreen` via `_sendIfConnected` helper. Controller stays pure.
- **Banner timer?**: Single-slot in widget `State`. Session screen is not navigated during session.
- **Single or multi-slot active banners?**: Single slot, last-fired wins.
- **How to distinguish yellow/red cards?**: Separate top-level event types in `EventSheet`.
- **`phaseLabel` vs overlay period label?**: `periodLabelForOverlay` getter added; `phaseLabel` unchanged.
- **Two-step setup failure?**: Show existing error + retry; both steps retry; idempotent.
- **Overlay scale / letterboxing?**: Fill full Stack bounds; 1920×1080 → widget bounds directly.
- **Away team color?**: Null in v1 — only home team has a DB-backed color via `TeamRecord`.
- **Team color picker UX?**: Fixed set (white/black/green/red/blue/yellow/orange), default grey, stored as hex string.

### Deferred to Implementation

- Exact Drift migration version number — check current `schemaVersion` in `lib/core/db/app_database.dart` at implementation time
- Whether `colorHex` should also be exposed in team list rows or only the form (design detail)
- Whether `PushSessionConfig.teamAColorHex` should send the hex string or a parsed int — check proto field type in `bluetooth.pb.dart` at implementation time

---

## High-Level Technical Design

> *This illustrates the intended approach and is directional guidance for review, not implementation specification. The implementing agent should treat it as context, not code to reproduce.*

### Session setup sequence

```
SetupScreen._startMatch
  │
  ├─→ ble.pushSessionConfig(deviceId, config [+ teamAColorHex])
  │     └─ [throw] → _pushError shown, Retry available
  │
  ├─→ layout = defaultScoreboardLayout(homeName, awayName, homeColorHex, null)
  ├─→ ble.pushOverlayLayout(deviceId, layout)
  │     └─ [throw] → _pushError shown, Retry re-runs both steps
  │
  ├─→ controller.setOverlayLayout(layout)
  ├─→ controller.setTeamColors(homeColorHex, null)
  └─→ widget.onStart()   ← navigate to SessionScreen
```

### Session BLE dispatch pattern

```
SessionScreen
  │
  ├─ _sendIfConnected(ref, cmd):
  │     activeId = ref.read(activeCameraIdProvider)
  │     connected = (connectionState == connected)
  │     if (activeId == null || !connected) return;   // drop silently
  │     ref.read(bleServiceProvider).sendCommand<void>(activeId, cmd);
  │
  ├─ onKickoff → ctl.startPeriod(...) + _sendIfConnected(MatchControlCommand(kickoff, nextPeriod))
  ├─ onRecToggle (idle)   → ctl.toggleRecPause() + _sendIfConnected(RecordingControlCommand(start))
  ├─ onRecToggle (rec)    → ctl.toggleRecPause() + _sendIfConnected(RecordingControlCommand(pause))
  ├─ onRecToggle (paused) → ctl.toggleRecPause() + _sendIfConnected(RecordingControlCommand(resume))
  ├─ onRecStop  → ctl.stopRecording() + _sendIfConnected(RecordingControlCommand(stop))
  ├─ onStreamToggle (on)  → ctl.setStreaming(true)  + _sendIfConnected(StreamingControlCommand(start, null))
  ├─ onStreamToggle (off) → ctl.setStreaming(false) + _sendIfConnected(StreamingControlCommand(stop, null))
  ├─ onEndPeriod → ctl.endPeriod() + _sendIfConnected(MatchControlCommand(periodEnd, currentPeriod))
  ├─ onTimerTap (running→paused) → ctl.toggleTimer() + _sendIfConnected(MatchControlCommand(clockPause, ...))
  ├─ onTimerTap (paused→running) → ctl.toggleTimer() + _sendIfConnected(MatchControlCommand(clockResume, ...))
  └─ addEvent(Goal) → ctl.addEvent(...) + _sendIfConnected(ScoreUpdateCommand) + _sendIfConnected(BannerEventCommand('goal',...))
     addEvent(Yellow Card) → ctl.addEvent(...) + _sendIfConnected(BannerEventCommand('yellow_card',...))
     addEvent(Red Card)    → ctl.addEvent(...) + _sendIfConnected(BannerEventCommand('red_card',...))
     addEvent(Sub)         → ctl.addEvent(...) + _sendIfConnected(BannerEventCommand('substitution',...))
```

### OverlayLayout data flow

```
defaultScoreboardLayout(names, colors)
           │
           ├──→ ble.pushOverlayLayout()  →  camera renders overlay
           │
           └──→ LiveMatchState.overlayLayout
                        │
                        └──→ OverlayLayoutRenderer(layout, matchState)
                                  │
                                  ├─ LayoutBuilder → sx = w/1920, sy = h/1080
                                  ├─ Persistent elements: Stack + Positioned per element
                                  │    RECT  → Container (color, cornerRadius, opacity)
                                  │    TEXT  → Text (binding resolved from matchState)
                                  │    CIRCLE→ Container (circle shape)
                                  └─ Active banner template elements (timer in State)
```

---

## Implementation Units

### U1. OverlayLayout Dart model hierarchy

**Goal:** Define the canonical `OverlayLayout` type hierarchy in `lib/core/models/overlay_layout.dart`, including all enums and the default scoreboard factory function.

**Requirements:** R1, R2

**Dependencies:** None

**Files:**
- Create: `lib/core/models/overlay_layout.dart`
- Create: `test/core/models/overlay_layout_test.dart`

**Approach:**
- Immutable data classes: `OverlayLayout` (canvasWidth, canvasHeight, elements, templates), `OverlayElement` (id, shape, bounds, style, binding, visible), `OverlayRect` (x1, y1, z, x2, y2), `OverlayStyle` (fillColor, textColor, opacity, cornerRadius, fontFamily, fontSize, textAlign, fontWeight, staticText), `OverlayTemplate` (eventType, durationMs, elements)
- Enums: `OverlayShape` (rect, text, circle), `OverlayBinding` (static, scoreA, scoreB, scoreVs, teamAName, teamBName, matchClock, periodLabel), `OverlayTextAlign` (left, center, right), `OverlayFontWeight` (normal, bold)
- Factory: `OverlayLayout defaultScoreboardLayout({required String homeName, required String awayName, String? homeColorHex, String? awayColorHex})` — produces the R2 canonical layout with: scoreboard background bar (RECT), home name (TEXT, teamAName binding), away name (TEXT, teamBName binding), score (TEXT, scoreVs binding), period label (TEXT, periodLabel binding), clock (TEXT, matchClock binding), and four banner templates: goal (5000ms), yellow_card (4000ms), red_card (4000ms), substitution (4000ms)
- When `homeColorHex` / `awayColorHex` is null, use `'#808080'` as fallback colour for that team's label accent
- No imports from feature layer — only `dart:ui` if needed for color parsing

**Patterns to follow:**
- `lib/core/models/device.dart` — immutable model, const constructor, named required fields
- `lib/core/models/match.dart` — co-located enums

**Test scenarios:**
- Happy path: `defaultScoreboardLayout` returns non-null `OverlayLayout` with canvas 1920×1080
- Happy path: returned layout contains all six required persistent elements with correct bindings (teamAName, teamBName, scoreVs, periodLabel, matchClock, and a RECT background)
- Happy path: layout contains exactly four banner templates with eventType strings matching 'goal', 'yellow_card', 'red_card', 'substitution'
- Happy path: goal template has `durationMs == 5000`; card/sub templates have `durationMs == 4000`
- Happy path: factory with null colors → style fields use `'#808080'` fallback (no null values in rendered style)
- Happy path: factory with both colors present → team label styles carry the provided hex strings
- Edge case: `OverlayRect` with equal x1/x2 — model accepts it without assertion
- Edge case: `OverlayLayout` with empty elements list — valid model, no crash

**Verification:**
- `test/core/models/overlay_layout_test.dart` passes
- `just analyze` clean

---

### U2. Teams DB colorHex column + migration + team form color picker

**Goal:** Add a nullable `colorHex` column to `TeamsTable`, thread it through `TeamRecord`, `TeamDraft`, the Drift DAO, and `UpcomingMatch`, and add a color picker (fixed palette) to the team registration/edit form.

**Requirements:** R3 (prerequisite for team color in session)

**Dependencies:** None

**Files:**
- Modify: `lib/core/db/tables/teams_table.dart` — add nullable `colorHex` column
- Modify: `lib/core/models/team.dart` — add `colorHex` to `TeamRecord` + `copyWith`; add `colorHex` to `TeamDraft`
- Modify: `lib/core/db/app_database.dart` — increment `schemaVersion`, add `MigrationStep`
- Modify: `lib/core/db/daos/` (teams DAO) — update row-to-`TeamRecord` mapping
- Modify: `lib/features/match/match_state.dart` — expose `homeColorHex` from `UpcomingMatch.team`
- Modify: `lib/features/teams/team_form_sheet.dart` — add color picker row
- Create or Modify: `test/core/db/teams_migration_test.dart`

**Approach:**
- `TeamsTable`: `TextColumn get colorHex => text().nullable()();`
- `TeamRecord.colorHex`: `final String? colorHex;` — nullable, optional in constructor; `copyWith` includes it
- `TeamDraft.colorHex`: `final String? colorHex;` — passed from form to DAO on create/update
- **Note**: Only `TeamRecord` and `TeamDraft` in `team.dart` gain `colorHex`. `TeamMatch`, `TeamMatchDraft`, `Player`, and `PlayerDraft` are unchanged.
- Migration: add a `MigrationStep` using `customStatement('ALTER TABLE teams ADD COLUMN color_hex TEXT');` (consistent with existing migration style; no Drift codegen ordering dependency). Existing rows get null (no default).
- DAO row mapping: `colorHex: row.colorHex` (Drift exposes the new nullable field automatically after codegen)
- Run `just gen-db` after table change
- `UpcomingMatch`: expose `String? get homeColorHex => team.colorHex;` (no schema change needed — reads from `TeamRecord`)
- **Team form color picker**: A `WfSection('Color')` + `Wrap` chip row (matches the sport-row Wrap pattern; handles narrow screens correctly). Palette: `['#FFFFFF', '#000000', '#4CAF50', '#F44336', '#2196F3', '#FFEB3B', '#FF9800']` with display labels White/Black/Green/Red/Blue/Yellow/Orange. Tapping a chip sets `_colorHex` state. A "None" chip sets null. The selected color is shown as a filled circle with a 1px `T.hair` border (ensures white and yellow swatches remain legible against the T.accent active chip background). On team edit (`widget.existing != null`), `_colorHex` is initialized to `widget.existing!.colorHex` (null pre-selects "None").

**Patterns to follow:**
- Existing `MigrationStrategy` pattern in `lib/core/db/app_database.dart`
- `WfChip` active/inactive pattern from `setup_screen.dart` format picker

**Test scenarios:**
- Happy path: existing DB (before migration) upgraded → `colorHex` column exists, existing rows have null
- Happy path: `TeamRecord` with `colorHex = null` — `copyWith` preserves null
- Happy path: DAO round-trip — insert team with `colorHex = '#FF0000'` → read back → value preserved
- Happy path: `UpcomingMatch.homeColorHex` returns `team.colorHex`
- Happy path: form with a color selected → `TeamDraft.colorHex` is the selected hex string
- Edge case: form with no color selected ("None") → `TeamDraft.colorHex` is null

**Verification:**
- `just gen-db` completes without error
- `just analyze` clean
- Migration test passes with in-memory Drift database

---

### U3. LiveMatchState — color fields + `periodLabelForOverlay` + `OverlayLayout?`

**Goal:** Add `homeColorHex`, `awayColorHex`, `OverlayLayout?`, and `periodLabelForOverlay` to `LiveMatchState`; add `setOverlayLayout` and `setTeamColors` to `LiveMatchController`; update `loadFromUpcoming` to thread team colors.

**Requirements:** R3, R4 (PERIOD_LABEL binding), R9 (layout stored in state)

**Dependencies:** U1 (for `OverlayLayout` type), U2 (for color on `UpcomingMatch`)

**Files:**
- Modify: `lib/features/match/session/session_state.dart`
- Create or Modify: `test/features/match/session/session_state_test.dart`

**Approach:**
- `LiveMatchState` gains: `final String? homeColorHex;`, `final String? awayColorHex;`, `final OverlayLayout? overlayLayout;` — all nullable, absent from `LiveMatchState.initial`
- `copyWith` updated with optional parameters for all three new fields; `overlayLayout` requires an `Object? overlayLayout = _sentinel` sentinel pattern (or `OverlayLayout? Function()?` wrapper) to allow setting to null via `copyWith`
- `periodLabelForOverlay` getter (firmware §9.3):
  - `MatchPhase.idle` → `'PRE'`
  - `MatchPhase.period` → `'P$currentPeriod'`
  - `MatchPhase.periodBreak && !isLastPeriod` → `'HT'`
  - `MatchPhase.periodBreak && isLastPeriod` → `'FT'`
  - `MatchPhase.ended` → `'FT'`
- `phaseLabel` getter — unchanged
- `LiveMatchController.setOverlayLayout(OverlayLayout layout)`: `state = state.copyWith(overlayLayout: layout);`
- `LiveMatchController.setTeamColors(String? home, String? away)`: `state = state.copyWith(homeColorHex: home, awayColorHex: away);`
- `LiveMatchController.loadFromUpcoming`: add `String? homeColorHex` parameter; set both fields in the resulting state
- `LiveMatchController.reset()`: `state = LiveMatchState.initial` already clears overlayLayout (it's null in initial)

**Patterns to follow:**
- Existing `copyWith` pattern in `session_state.dart`
- Existing `loadFromUpcoming` named parameter pattern

**Test scenarios:**
- Happy path: `loadFromUpcoming(homeColorHex: '#FF0000', ...)` → `state.homeColorHex == '#FF0000'`
- Happy path: `loadFromUpcoming(homeColorHex: null, ...)` → `state.homeColorHex == null`
- Happy path: `setOverlayLayout(layout)` → `state.overlayLayout == layout`
- Happy path: `reset()` → `state.overlayLayout == null`, `state.homeColorHex == null`
- Happy path: `periodLabelForOverlay` == `'P1'` when `phase == period && currentPeriod == 1`
- Happy path: `periodLabelForOverlay` == `'HT'` when `phase == periodBreak && currentPeriod == 1 && numPeriods == 2`
- Happy path: `periodLabelForOverlay` == `'FT'` when `phase == ended`
- Happy path: `periodLabelForOverlay` == `'FT'` when `phase == periodBreak && isLastPeriod`
- Edge case: `copyWith` with no arguments → all three new fields preserved unchanged
- Edge case: `phaseLabel` still returns `'BRK'` for periodBreak non-last-period (unchanged)

**Verification:**
- Existing `liveMatchProvider` tests pass unchanged
- New tests pass
- `just analyze` clean

---

### U4. BleCommand sealed subclasses + BleProtocol + BleService

**Goal:** Add six new `BleCommand` sealed subclasses with supporting enums, extend `BleProtocol` encode/decode arms, and add `BleService.pushOverlayLayout()`.

**Requirements:** R5, R6

**Dependencies:** U1 (for `OverlayLayout` type in `PushOverlayLayoutCommand`)

**Files:**
- Modify: `lib/core/models/command.dart` — 6 new subclasses + 3 new enums; `PushSessionConfig` gains color fields
- Modify: `lib/core/ble/ble_protocol.dart` — 6 new arms in `_toProtoCommand()` + `_mapOkResponse()`
- Modify: `lib/core/ble/ble_service.dart` — `pushOverlayLayout()` method signature
- Modify: `lib/core/ble/ble_service_impl.dart` — `pushOverlayLayout()` implementation
- Modify: `test/ble/ble_service_impl_proto_test.dart` — encoding tests for new commands

**⚠ ATOMIC with U5**: Adding new `BleCommand` subclasses makes `MockBleService`'s exhaustive switches non-exhaustive (compile error). U4 and U5 must land in the same commit.

**Approach:**

New enums in `command.dart`:
- `enum RecordingAction { start, stop, pause, resume }`
- `enum StreamingAction { start, stop }`
- `enum BleMatchControlAction { kickoff, periodEnd, periodStart, finalWhistle, clockPause, clockResume }`

New sealed subclasses:
- `RecordingControlCommand({ required RecordingAction action })`
- `StreamingControlCommand({ required StreamingAction action, String? rtmpUrl })`
- `MatchControlCommand({ required BleMatchControlAction action, required int period })`
- `ScoreUpdateCommand({ required String teamId, required int delta })`
- `BannerEventCommand({ required String templateId, Map<String, String> params = const {}, required int durationSeconds, String? playerId })`
- `PushOverlayLayoutCommand({ required OverlayLayout layout })`

`PushSessionConfig` payload class gains: `String? teamAColorHex`, `String? teamBColorHex`

`BleProtocol`:
- `_toProtoCommand()`: one arm per new subclass; maps Dart enum values → proto enum values using already-committed bindings in `lib/models/proto/bluetooth.pb.dart`
- `_mapOkResponse()`: all 6 new commands return `BleCommandResponse<void>.ok()` (fire-and-forget)

`BleService.pushOverlayLayout(String deviceId, OverlayLayout layout) → Future<void>`: throws on non-OK response, mirrors `pushSessionConfig` contract

`BleServiceImpl.pushOverlayLayout()`: encodes layout as `PushOverlayLayoutCommand(layout: layout)` and dispatches through the existing BLE write path

**Patterns to follow:**
- Existing `_toProtoCommand()` and `_mapOkResponse()` arms in `ble_protocol.dart`
- `pushSessionConfig` in `ble_service.dart` and `ble_service_impl.dart`

**Test scenarios:**
- Happy path: `_toProtoCommand(RecordingControlCommand(action: RecordingAction.start), corrId)` → proto `recording_control.action == RECORDING_START`
- Happy path: encoding for each new command type → proto field number matches `bluetooth.proto` definition
- Happy path: `_mapOkResponse(RecordingControlCommand(...), ...)` → `BleCommandResponse<void>.ok()`
- Happy path: `_toProtoCommand(PushOverlayLayoutCommand(layout: layout), ...)` → proto `push_overlay_layout.layout.canvas_width == 1920`
- Happy path: `MatchControlCommand(action: BleMatchControlAction.kickoff, period: 1)` → `match_control.action == MATCH_KICKOFF`
- Edge case: `BannerEventCommand` with empty params map → encodes without error
- Edge case: `MatchControlCommand(action: clockPause, period: 0)` → encodes correctly (period 0 is valid)

**Verification:**
- `test/ble/ble_service_impl_proto_test.dart` passes with new groups
- MockBleService compiles (requires U5 to land atomically)
- `just analyze` clean

---

### U5. MockBleService new command handling (⚠ ATOMIC with U4 — same commit)

**Goal:** Extend `MockBleService`'s three exhaustive switch statements for all six new commands, add recording/streaming state side effects, and implement `pushOverlayLayout`. (⚠ **Must be implemented and committed in the same git commit as U4** — new `BleCommand` subclasses make these switches non-exhaustive immediately, breaking compilation.)

**Requirements:** R7

**Dependencies:** U4 (must land atomically)

**Files:**
- Modify: `lib/mock/emulator/mock_ble_service.dart`
- Modify: `test/mock/mock_ble_service_test.dart`

**Approach:**

All three switch statements (`_encodeCommand`, `_buildResponse`, `_mapResponse`) gain arms for each new subclass.

State side effects:
- `RecordingControlCommand(start)` → `_isRecording = true`
- `RecordingControlCommand(stop/pause)` → `_isRecording = false`
- `StreamingControlCommand(start)` → `_isStreaming = true`
- `StreamingControlCommand(stop)` → `_isStreaming = false`
- All other new commands → `BleCommandResponse.ok()` with no side effect

Inspectable fields added (for test assertions):
- `BleMatchControlAction? lastMatchControlAction`
- `RecordingAction? lastRecordingAction`
- `OverlayLayout? lastPushedOverlayLayout`
- `BannerEventCommand? lastBannerEvent`

`MockBleService.pushOverlayLayout(String deviceId, OverlayLayout layout)`: stores `lastPushedOverlayLayout = layout` and returns normally (no throw). Follows the `pushSessionConfig` mock pattern.

**Patterns to follow:**
- Existing `MockBleService._encodeCommand` / `_buildResponse` / `_mapResponse` triple-switch pattern
- `lastPushedConfig`, `failNextPushSessionConfig` — existing inspectable field pattern

**Test scenarios:**
- Happy path: `sendCommand<void>(id, RecordingControlCommand(action: start))` → `resp.isOk == true`, `lastRecordingAction == start`
- Happy path: telemetry emits `isRecording: true` after `RecordingControlCommand(start)` (if mock telemetry reads `_isRecording`)
- Happy path: `sendCommand<void>(id, RecordingControlCommand(action: stop))` → `isRecording` field reflects false
- Happy path: `sendCommand<void>(id, StreamingControlCommand(action: start, rtmpUrl: null))` → `resp.isOk`, `_isStreaming == true`
- Happy path: `sendCommand<void>(id, MatchControlCommand(action: kickoff, period: 1))` → `resp.isOk`, `lastMatchControlAction == kickoff`
- Happy path: `sendCommand<void>(id, BannerEventCommand(templateId: 'goal', durationSeconds: 5))` → `resp.isOk`, `lastBannerEvent.templateId == 'goal'`
- Happy path: `sendCommand<void>(id, PushOverlayLayoutCommand(layout: layout))` → `resp.isOk`
- Happy path: `pushOverlayLayout(id, layout)` → completes without throw; `lastPushedOverlayLayout == layout`
- Integration: connect mock → `sendCommand(RecordingControlCommand(start))` → next `sendCommand(GetTelemetryCommand)` → telemetry `isRecording == true`

**Verification:**
- `test/mock/mock_ble_service_test.dart` passes with all new groups
- MockBleService compiles without error (exhaustive switches satisfied)
- `just ci` passes when U4 + U5 land together

---

### U6. Session setup two-step push

**Goal:** Update `_startMatch` in `setup_screen.dart` to execute the full setup sequence — `PushSessionConfig` → `PushOverlayLayout` — then store the layout in session state and thread team colors.

**Requirements:** R9, R3 (color threading into session)

**Dependencies:** U1, U2, U3, U4, U5

**Files:**
- Modify: `lib/features/match/setup_screen.dart`

**Approach:**

In `_startMatch`:
1. Build `PushSessionConfig` — add `teamAColorHex: widget.match.team.colorHex` (now available after U2)
2. Await `ble.pushSessionConfig(deviceId, config)` — on throw: `_pushError`, return
3. Build `layout = defaultScoreboardLayout(homeName: ..., awayName: ..., homeColorHex: widget.match.team.colorHex, awayColorHex: null)`
4. Await `ble.pushOverlayLayout(deviceId, layout)` — on throw: `_pushError` (same string), return
5. `controller.setOverlayLayout(layout)` — stores in `LiveMatchState`
6. `controller.setTeamColors(widget.match.team.colorHex, null)` — sets colors in state
7. `controller.loadFromUpcoming(...)` — already called earlier when the match is selected; this step updates colors. Alternatively pass `homeColorHex` to `loadFromUpcoming` if called here.
8. `widget.onStart()`

Both steps share `_pushing = true` / `setState(() => _pushing = false)` — the loading indicator covers the full two-step push. On retry, both steps re-run (step 1 is idempotent via `_matchUuid`; step 2 sends a fresh layout object, safe to repeat).

`if (!mounted) return;` guard after each `await`.

**Patterns to follow:**
- Existing `_startMatch` try/catch structure in `setup_screen.dart`
- `_pushing` / `_pushError` state pattern

**Test scenarios:**
- Happy path: both pushes succeed → `lastPushedOverlayLayout` non-null in mock; session screen shown (Covers AE2)
- Happy path: `lastPushedOverlayLayout.canvasWidth == 1920` (same factory output as renderer will use)
- Error path: step 1 throws → `_pushError` shown; `lastPushedOverlayLayout` remains null
- Error path: step 2 throws → `_pushError` shown; session not started
- Retry after step 2 failure → `lastPushedConfig` updated again (idempotent), then `lastPushedOverlayLayout` set
- Edge case: `!mounted` after step 1 → early return, no crash

**Verification:**
- Manual dev-mode test: "Start match" → mock `lastPushedOverlayLayout` is non-null in `DiagnosticsPage` or debug log
- `just ci` passes

---

### U7. EventSheet yellow/red card distinction

**Goal:** Replace the single 'Card' event type in `EventSheet` with separate 'Yellow Card' and 'Red Card' types to enable correct BLE `templateId` dispatch.

**Requirements:** R8 (yellow_card, red_card banner events)

**Dependencies:** None (UI-only change)

**Files:**
- Modify: `lib/features/match/session/event_sheet.dart`

**Approach:**
- In the event type list in `EventSheet`, replace `'Card'` with two separate entries: `'Yellow Card'` and `'Red Card'`
- `onSave` callback passes the full type string; `addEvent` in `LiveMatchController` receives it unchanged
- `addEvent` already handles unknown types gracefully — no score change for card types (only `'Goal'` increments score)
- Event log displays the full string `'Yellow Card · Team Name'` or `'Red Card · Team Name'`

**Patterns to follow:**
- Existing event type list in `event_sheet.dart`

**Test scenarios:**
- Happy path: 'Yellow Card' appears in event type list; tapping it calls `onSave` with `type: 'Yellow Card'`
- Happy path: 'Red Card' appears in event type list; tapping it calls `onSave` with `type: 'Red Card'`
- Happy path: neither card type increments the score in `addEvent`
- Happy path: 'Card' no longer appears in the type list
- Happy path: event log renders `'Yellow Card · FCB · #7'` without error

**Verification:**
- Widget test for `EventSheet` confirms both card types present, neither triggers score change

---

### U8. Session BLE command wiring

**Goal:** Wire all R8 user actions in `session_screen.dart` to send the corresponding BLE command via `_sendIfConnected`, alongside existing local state updates.

**Requirements:** R8

**Dependencies:** U3, U4, U5, U7

**Files:**
- Modify: `lib/features/match/session/session_screen.dart`
- Create: `test/features/match/session/session_ble_wiring_test.dart`

**Approach:**

Add `_sendIfConnected` free function (or `SessionScreen` method) at the bottom of `session_screen.dart`:
```
void _sendIfConnected(WidgetRef ref, BleCommand cmd) {
  final id = ref.read(activeCameraIdProvider);
  if (id == null) return;
  final state = ref.read(connectionStateProvider(id)).valueOrNull;
  if (state != CameraConnectionState.connected) return;
  ref.read(bleServiceProvider).sendCommand<void>(id, cmd); // discard Future
}
```

Full R8 wiring (read `state.rec` and `state.timer` BEFORE calling controller methods to dispatch the correct BLE action):

| Callback | Local action | BLE command |
|---|---|---|
| `_kickoff` (period 1 start) | `ctl.startPeriod(...)` | `MatchControlCommand(kickoff, nextPeriod)` |
| `onEndPeriod` | `ctl.endPeriod()` | `MatchControlCommand(periodEnd, state.currentPeriod)` |
| `onStartNextPeriod` | `ctl.startPeriod()` | `MatchControlCommand(periodStart, state.currentPeriod + 1)` |
| `onEndMatch` (`_confirmEnd` dialog → ctl.endMatch) | `ctl.endMatch(...)` | `MatchControlCommand(finalWhistle, state.currentPeriod)` |
| `onTimerTap` (running) | `ctl.toggleTimer()` | `MatchControlCommand(clockPause, state.currentPeriod)` |
| `onTimerTap` (paused) | `ctl.toggleTimer()` | `MatchControlCommand(clockResume, state.currentPeriod)` |
| `onRecToggle` (rec.idle) | `ctl.toggleRecPause()` | `RecordingControlCommand(start)` |
| `onRecToggle` (rec.recording) | `ctl.toggleRecPause()` | `RecordingControlCommand(pause)` |
| `onRecToggle` (rec.paused) | `ctl.toggleRecPause()` | `RecordingControlCommand(resume)` |
| `onRecStop` | `ctl.stopRecording()` | `RecordingControlCommand(stop)` |
| `onStreamToggle(true)` | `ctl.setStreaming(true)` | `StreamingControlCommand(start, null)` |
| `onStreamToggle(false)` | `ctl.setStreaming(false)` | `StreamingControlCommand(stop, null)` |
| Goal event | `ctl.addEvent(...)` | `ScoreUpdateCommand(teamId, +1)` + `BannerEventCommand('goal', {}, 5, null)` |
| Yellow Card event | `ctl.addEvent(...)` | `BannerEventCommand('yellow_card', {}, 4, null)` |
| Red Card event | `ctl.addEvent(...)` | `BannerEventCommand('red_card', {}, 4, null)` |
| Substitution event | `ctl.addEvent(...)` | `BannerEventCommand('substitution', {}, 4, null)` |

`ScoreUpdateCommand.teamId`: use `state.homeName` or `state.awayName` as the teamId string placeholder (away team has no `TeamRecord` ID in v1; noted as known limitation).

The kickoff prompt (`_showStartPrompt`) is already `async`; BLE dispatch fires after the modal resolves, before `ctl.startPeriod` is called — use the pre-modal `state.currentPeriod + 1` as the target period.

**Patterns to follow:**
- Existing `connected ? callback : null` pattern in `_BottomControls`
- `ref.read(activeCameraIdProvider)` in `SessionScreen.build`

**Test scenarios:**
- Happy path: connected + tap Record → `RecordingControlCommand(start)` dispatched; `lastRecordingAction == start` (Covers AE1)
- Happy path: connected + tap Kickoff → `MatchControlCommand(kickoff, 1)` dispatched (Covers AE1)
- Happy path: not connected + tap Record → no BLE command; local state still updates (isRecording becomes true)
- Happy path: Goal event → both `ScoreUpdateCommand` and `BannerEventCommand('goal')` dispatched
- Happy path: Yellow Card event → only `BannerEventCommand('yellow_card')` dispatched, no score change
- Happy path: `toggleRecPause` while `rec.recording` → sends PAUSE, not START
- Happy path: `toggleRecPause` while `rec.paused` → sends RESUME
- Happy path: `toggleTimer` while `timer.running` → sends `clockPause`
- Edge case: `_sendIfConnected` with null `activeCameraId` → no crash, no command dispatched

**Verification:**
- `test/features/match/session/session_ble_wiring_test.dart` passes
- `just ci` passes

---

### U9. Flutter overlay renderer widget

**Goal:** Build `OverlayLayoutRenderer` — a `StatefulWidget` that renders an `OverlayLayout` onto a scaled surface with binding substitution from `LiveMatchState` and single-slot banner timer — and replace `_LiveThumb`'s hardcoded scoreboard with it.

**Requirements:** R4, R9 (same layout object rendered in Flutter and sent to camera)

**Dependencies:** U1, U3

**Files:**
- Create: `lib/features/match/session/overlay_renderer.dart`
- Modify: `lib/features/match/session/session_screen.dart` — replace hardcoded scoreboard in `_LiveThumb`
- Create: `test/features/match/session/overlay_renderer_test.dart`

**Approach:**

`OverlayLayoutRenderer extends StatefulWidget` — required inputs: `OverlayLayout layout`, `LiveMatchState matchState`.

`_OverlayLayoutRendererState`:
- `String? _activeBannerTemplateId`
- `Timer? _bannerTimer`
- `int _lastEventCount = 0`
- `@override void didUpdateWidget(...)`: use **O(1) detection** — `if (widget.matchState.events.length > _lastEventCount)`, inspect `widget.matchState.events.first` for a banner-triggering type. Events are always prepended so `events.first` is always the newest. Extract the type from the label prefix (before ` · `) and match against template `eventType` strings ('goal', 'yellow_card', 'red_card', 'substitution'). On match: cancel any prior `_bannerTimer`, set `_activeBannerTemplateId = template.eventType`, start `Timer(Duration(milliseconds: template.durationMs), () => setState(() => _activeBannerTemplateId = null))`. Always set `_lastEventCount = widget.matchState.events.length` at end of method. This O(1) pattern prevents re-firing banners on historical events during widget rebuilds.
- `@override void dispose()`: `_bannerTimer?.cancel(); super.dispose();`

`build()`:
- `LayoutBuilder` → `sx = constraints.maxWidth / layout.canvasWidth`, `sy = constraints.maxHeight / layout.canvasHeight`
- `Stack(children: [...persistentWidgets, ...bannerWidgets])`
- For each `OverlayElement` where `visible == true`, compute `Positioned(left: el.bounds.x1 * sx, top: el.bounds.y1 * sy, width: (el.bounds.x2 - el.bounds.x1) * sx, height: (el.bounds.y2 - el.bounds.y1) * sy, child: _buildElement(el, sx, sy))`
- `_buildElement` by shape:
  - `RECT`: `Opacity(opacity: el.style.opacity, child: Container(decoration: BoxDecoration(color: _parseHex(el.style.fillColor), borderRadius: BorderRadius.circular(el.style.cornerRadius))))`
  - `TEXT`: `Text(_resolveBinding(el.binding, el.style.staticText), style: TextStyle(color: _parseHex(el.style.textColor), fontSize: el.style.fontSize * sy, fontWeight: ..., fontFamily: el.style.fontFamily))`
  - `CIRCLE`: `Container(decoration: BoxDecoration(color: _parseHex(el.style.fillColor), shape: BoxShape.circle))`
- Banner elements: when `_activeBannerTemplateId != null`, find template → render its elements the same way (on top of persistent elements)
- `_resolveBinding(OverlayBinding binding, String? staticText)` → match state fields as specified in R4; `STATIC` → `staticText ?? ''`
- `_parseHex(String? hex)` → `Color` from `'#RRGGBB'` string; returns `Colors.transparent` for null

`_LiveThumb` change: replace the `Positioned(left: 8, right: 8, bottom: 8, child: scoreboard Container)` block with `Positioned.fill(child: OverlayLayoutRenderer(layout: state.overlayLayout ?? _emptyLayout, matchState: state))`. Define `_emptyLayout` as `OverlayLayout(canvasWidth: 1920, canvasHeight: 1080, elements: [], templates: [])` — renders nothing when layout not yet set.

**Execution note:** The `_LiveThumb` scoreboard replacement is the visible change; start with the renderer widget rendering correctly from the factory output, then swap out the hardcoded scoreboard.

**Patterns to follow:**
- `LayoutBuilder` pattern in existing Flutter widgets
- `Stack + Positioned` in `_LiveThumb` (the existing structure the renderer replaces)

**Test scenarios:**
- Smoke test: `pumpWidget(OverlayLayoutRenderer(layout: defaultScoreboardLayout(...), matchState: LiveMatchState.initial))` → renders without error
- Happy path: SCORE_VS binding → rendered text is `'0 – 0'` for initial match state
- Happy path: TEAM_A_NAME binding → rendered text equals `matchState.homeName`
- Happy path: PERIOD_LABEL binding → renders `matchState.periodLabelForOverlay`
- Happy path: MATCH_CLOCK binding → renders `matchState.clockText`
- Happy path: score update in matchState → text widget shows updated `'1 – 0'`
- Happy path: null `overlayLayout` → empty layout shows no elements, no crash (Covers M3 risk)
- Happy path: RECT element renders with non-transparent background color
- Edge case: `OverlayElement` with `visible == false` → not rendered in tree
- Banner: when a 'goal' event appears in `matchState.events`, the goal template elements become visible; after `fakeAsync.elapse(Duration(milliseconds: 5000))`, they are hidden
- Banner: a second banner before the first expires → first timer cancelled, new timer starts, only new banner shown
- Covers AE2, AE3: `defaultScoreboardLayout` output → same layout object rendered in widget

**Verification:**
- `test/features/match/session/overlay_renderer_test.dart` passes (including fakeAsync banner tests)
- Visual: dev app session screen shows a scoreboard driven by `OverlayLayoutRenderer`, not `_ScoreBlock`
- `just ci` passes

---

## System-Wide Impact

- **Interaction graph:** `_LiveThumb` is the only scoreboard overlay call site — change is contained to `session_screen.dart`. `setup_screen.dart._startMatch` is the only session setup entry point. All new BLE dispatch is additive; no existing dispatch removed or changed.
- **Error propagation:** BLE command dispatch failures during sessions are silently dropped (design intent, R8). Setup sequence failures surface via `_pushError` UI — the two-step push adds one more failure point but uses the same UI path.
- **State lifecycle risks:** `OverlayLayout?` in `LiveMatchState` is null until `setOverlayLayout` completes. `reset()` clears it. Renderer handles null via empty `_emptyLayout` fallback. No race between setup completion and session screen render.
- **API surface parity:** `BleService.pushOverlayLayout` must be implemented in both `BleServiceImpl` (production) and `MockBleService` (dev/test). New `BleCommand` subclasses must update both `BleProtocol` and `MockBleService` in the same commit.
- **Integration coverage:** Unit tests alone don't prove the end-to-end setup sequence. U6 verification via mock's `lastPushedOverlayLayout` assertion covers the "same factory output sent to camera and stored in state" guarantee.
- **Unchanged invariants:** `OverlayState`/`overlay_helper.dart` (video playback overlay system) — entirely unaffected. `phaseLabel` getter on `LiveMatchState` — unchanged. `BleService.pushSessionConfig` interface — unchanged. `_TopBar` widget — unchanged. The `_ScoreBlock` and `_LiveThumb` scoreboard widgets remain in the file; only the `Positioned` scoreboard child inside `_LiveThumb` is replaced.

---

## Risks & Dependencies

| Risk | Mitigation |
|------|------------|
| U4 + U5 atomicity: new `BleCommand` subclasses break `MockBleService` compile | Implement U4 + U5 in a single commit; run `just ci` only after both are complete |
| DB migration incorrect `MigrationStep` / missing codegen | Run `just gen-db` before `just analyze`; test with in-memory Drift DB |
| Proto field number mismatch in new BleProtocol arms | Cross-check each arm against `bluetooth.proto` field numbers at implementation time; proto bindings already committed and can be read directly |
| `toggleRecPause` dispatches wrong BLE action (START vs PAUSE vs RESUME) | Read `state.rec` before `ctl.toggleRecPause()` at call site; unit test all three branches explicitly |
| Banner timer doesn't fire correctly in widget tests | Use `fakeAsync` + `FakeAsync.elapse` in banner timer tests |
| Away team color remains null even after team is registered — factory defaults to grey | Documented limitation; grey default produces a valid overlay with no crash |
| `_sendIfConnected` discards `Future` — analyzer may warn | Use `unawaited()` from `dart:async` or `// ignore: discarded_futures` as needed |

---

## Sources & References

- **Origin document:** [docs/brainstorms/2026-06-03-overlay-layout-requirements.md](docs/brainstorms/2026-06-03-overlay-layout-requirements.md)
- `docs/firmware-spec.md` §8.2 (session workflow), §9 (overlay layout spec + §9.3 period label strings), §10 (command reference)
- `proto/bluetooth.proto` §11 (overlay messages and field numbers)
- `lib/features/match/session/session_screen.dart` — `_LiveThumb` scoreboard (target of R4 replacement)
- `lib/features/match/session/session_state.dart` — `LiveMatchController`, `LiveMatchState`
- `lib/core/models/command.dart` — sealed `BleCommand` hierarchy
- `lib/mock/emulator/mock_ble_service.dart` — triple-switch exhaustive pattern
- `lib/core/ble/ble_protocol.dart` — encode/decode switch pattern
- Institutional: `docs/solutions/logic-errors/core-importing-feature-layer-inversion-2026-05-26.md`
- Institutional: `docs/solutions/conventions/isdevbackend-must-not-bypass-connection-state-guards-2026-05-19.md`
- Institutional: `docs/solutions/architecture-patterns/app-source-of-truth-drift-sqlite-2026-05-06.md`
