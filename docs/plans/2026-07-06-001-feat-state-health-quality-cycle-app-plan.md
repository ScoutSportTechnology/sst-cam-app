---
title: "feat: Universal handshake, silent rejoin, health gating, auto-reconnect, polish"
type: feat
status: active
date: 2026-07-06
origin: docs/brainstorms/2026-07-06-state-health-quality-cycle-requirements.md
---

# feat: Universal handshake, silent rejoin, health gating, auto-reconnect, polish

## Summary

Move the connect flow into the BLE service layer as one universal handshake (protocol check → time push → snapshot read → rehydrate → reconcile), persist scoreboard/match state so silent rejoin survives app kills, gate all capture features on per-camera health with an inoperable-device UX + diagnostics indicators, add BLE auto-reconnect and the auto-stop setting, bring `MockBleService` to parity so all of it tests pre-metal, and close with a structural polish sweep. Contract: `sst-cam-proto/docs/plans/2026-07-06-001-feat-state-health-contract-plan.md`; firmware counterpart: `sst-cam-firmware/docs/plans/2026-07-06-001-feat-state-health-quality-cycle-firmware-plan.md`.

---

## Problem Frame

Connect logic is duplicated across two page-level call sites, reads nothing but the protocol version, and force-resets selections; scoreboard state is in-memory and dies with the app; commands are fire-and-forget while disconnected, so app and firmware silently diverge; there is no health concept, so a dead camera fails as a blank preview. See origin doc for the full frame.

---

## Requirements

Origin R-IDs: R1–R5 (state/reconnect/persistence/auto-stop), R7–R9 (inoperable error, gating, diagnostics), R12–R14 (quality/process), R15 (AF mode control — app side), R16 (time push), R17 (auto-reconnect). Origin flows F1–F3; acceptance examples AE1–AE6.

---

## Scope Boundaries

- Firmware behavior (session survival, health computation, enforcement) — firmware plan.
- Contract definition — proto plan.
- No mic support (placeholders only), no degraded single-camera mode.
- Overlay divergence during a disconnect is permanent and accepted — "zero scoreboard loss" applies to app data, not already-baked video frames.

### Deferred to Follow-Up Work

- Emulator repo (`sst-cam-emulator`) parity with the new contract: separate cycle.

---

## Context & Research

### Relevant Code and Patterns

- BLE: `lib/core/ble/ble_service.dart` (port), `ble_service_impl.dart` (connect sequence: connect → MTU → discover → notify → `GetDeviceInfo` protocol gate; telemetry 1 Hz + match-state 2 s pollers; unexpected-disconnect keeps per-device stream slot), `ble_protocol.dart`, `ble_providers.dart`.
- Connect call sites (the duplication to kill): `lib/features/discovery/discovery_page.dart` `_attemptConnect`, settings `_ConnectCameraBanner` CTA. `lib/core/state/selection_sync.dart` (`resetSelectionOnConnect` — the primitive ancestor of the handshake; header documents that the connection-state stream misses reconnect edges → anchor behavior at connect, not at disconnect edges).
- Session/scoreboard: `lib/features/match/session/session_state.dart` (`LiveMatchController`, in-memory; UI-timer tick; auto-fires period end), `session_screen.dart` (`_sendIfConnected` fire-and-forget), `setup_screen.dart` (session config push), `lib/core/db/` (Drift; `team_matches` finalization).
- Dormant hook: `matchStateProvider` (`ble_providers.dart`) — polled every 2 s, zero consumers today.
- Gating template: `liveSessionActiveProvider` (`lib/features/video/video_state.dart`) — derived provider folding app state + firmware telemetry; consumed to lock downloads. The health gate is this shape inverted.
- Error surfacing: persistent banner cards (bluetooth-off, `_ConnectCameraBanner`, `_EndedBanner`) = precedent for the inoperable banner; typed exceptions in `ble_service.dart`; typed response statuses (no substring matching).
- Diagnostics: `lib/features/discovery/diagnostics_page.dart` (`_CameraDiagnostics`, `_StatTile` grid, Activity chips; convention: unreported fields render "—", never fabricated).
- Mock: `lib/mock/emulator/mock_ble_service.dart` (1733 ln; no phase machine, static `isRecording`, nothing survives mock disconnects).
- Conventions: UI only touches `BleService`/`WifiService` ports; tests override providers via `ProviderScope(overrides:)`; feature owns UI + `*_state.dart`; cross-feature providers → `core/state/`; theme tokens only; keep `docs/firmware-spec.md` in sync.

### Institutional Learnings

- `docs/solutions/logic-errors/settings-toggle-live-state-vs-saved-intent-2026-06-29.md` — observed state and user intent stay separate values; reading reality must not rewrite intent.
- `docs/solutions/architecture-patterns/mock-must-mirror-real-firmware-contract-2026-06-10.md` — mock drift makes tests green against fiction; parity is a work item.
- `docs/solutions/logic-errors/wifi-direct-dart-service-lifecycle-correctness-2026-06-09.md` — timeouts on platform calls, in-flight dedup, subscription cleanup must survive the rework.
- `docs/solutions/conventions/isdevbackend-must-not-bypass-connection-state-guards-2026-05-19.md` — health gating must hold in dev/mock mode too.
- `docs/solutions/architecture-patterns/app-source-of-truth-drift-sqlite-2026-05-06.md` — app owns business data; this cycle adds: firmware owns runtime session facts; state the split wherever both docs are cited.

---

## Key Technical Decisions

- **Handshake lives in a connect controller above the port** (`lib/core/state/` — pages and the auto-reconnect loop call the controller, never `svc.connect()` directly): the controller drives `svc.connect()` → time push → snapshot read → provider rehydrate → reconcile commands, and returns only after reconcile completes (or fails typed). The `BleService` port stays pure wire (it's a plain class with no Riverpod Ref; rehydrate targets are providers + Drift), so `MockBleService` stays wire-level and never duplicates reconcile logic. Page-anchored logic is gone either way — the documented reconnect-edge unreliability plus auto-reconnect (R17) demanded one shared entry point.
- **Handshake order: protocol check → push device time → read snapshot → rehydrate providers → reconcile.** Rehydrate = adopt firmware actual state (active camera, preview layout, recording/streaming/raw-capture flags, recording elapsed for the duration display, match clock). Reconcile = push app-owned intent that the firmware can't know: absolute `SetMatchState` when the app's persisted match matches the running `match_uuid` (app score is authoritative — deltas made while disconnected were never sent; firmware clock is authoritative — it's the only clock that ran).
- **"Reconciling" lockout**: between BLE connect and reconcile-complete, session-affecting commands are blocked/queued; timeout → treated as failed connect. Prevents a Record tap racing the snapshot.
- **Scoreboard persists keyed `(device_id, match_uuid)`, wall-clock-anchored** (period-start anchor, not tick counts): survives app kill, immune to UI-timer drift, and can't hydrate match X against camera B.
- **Idle-with-history reconcile**: snapshot says idle but app holds a mid-match scoreboard → read last-session summary; show a one-line "ended while away" notice (end reason, end clock, file-valid); finalize the `team_matches` row. No prompt.
- **Unknown running session** (no persisted match for the `match_uuid`): adopt a scoreboard view rebuilt from firmware match state; silent rejoin per origin R3.
- **Continuous drift correction**: the currently-unused 2 s match-state poll corrects the app clock while connected (kills UI-timer drift); on rejoin, if adopted elapsed ≥ period length, fire period-end immediately.
- **Health gate is a derived provider** in the `liveSessionActiveProvider` shape, folding snapshot + 1 Hz telemetry health: any camera != OK → preview/record/stream actions disabled + persistent "device inoperable" banner; downloads and diagnostics stay reachable; RECOVERING shows as a soft "camera recovering…" state, not inoperable flapping. Gate holds in dev/mock mode.
- **Auto-reconnect is a service-layer loop** targeting only `lastConnectedDeviceId` after *unexpected* drops (never after manual disconnect), with backoff and a stop condition; every attempt runs the full handshake, which is what makes it safe. Manual connect stays for first-time/different-device.
- **`resetSelectionOnConnect` retired** — adopt-from-snapshot replaces force-reset; `selection_sync.dart` deleted once both call sites route through the service handshake.
- **Tolerate uncommanded transitions**: pollers may reveal recording→idle (auto-stop fired race) — the session controller treats firmware polls as truth for runtime flags, never throws on unexpected state.

---

## High-Level Technical Design

> *This illustrates the intended approach and is directional guidance for review, not implementation specification. The implementing agent should treat it as context, not code to reproduce.*

```
connect(deviceId)                                  [BleService, one implementation]
  ├─ BLE link + MTU + discover + notify
  ├─ GetDeviceInfo ──✗ version → typed failure (no partial connect)
  ├─ SetDeviceTime(phone epoch)
  ├─ snapshot ← GetSessionSnapshot
  ├─ REHYDRATE (adopt actual):  activeCamera, previewLayout, rec/stream flags,
  │                             match clock/period (firmware clock wins)
  ├─ RECONCILE (push intent):   persisted match for snapshot.match_uuid?
  │     yes → SetMatchState(app scores, firmware clock)   [app owns match data]
  │     no  → adopt firmware match state as scoreboard view
  │     idle + local mid-match history → last-session summary → notice + finalize row
  └─ unlock UI (reconciling → connected)

states: disconnected → connecting → reconciling → connected
                     ↖ auto-reconnect loop (unexpected drop only, lastConnectedDeviceId,
                       backoff, full handshake per attempt)

gate: anyCameraNotOk(snapshot ⊕ telemetry) → {preview, record, stream} disabled
      + inoperable banner;  downloads/diagnostics always reachable
```

---

## Implementation Units

### U1. Universal handshake in the BLE service layer

**Goal:** One connect implementation: protocol check, time push, snapshot read, rehydrate, reconcile, lockout state; page-level duplication and `resetSelectionOnConnect` retired.

**Requirements:** Origin R1, R2, R3, R16; F1; AE1–AE3

**Dependencies:** Proto plan U1; firmware plan U2 (for real-device use; mock parity U7 unblocks app-side tests earlier)

**Files:**
- Modify: `lib/core/ble/ble_service.dart`, `ble_service_impl.dart`, `ble_protocol.dart` (new commands), `ble_providers.dart`, `lib/core/models/device.dart` (`CameraConnectionState` enum gains `reconciling` — exhaustive switches surface via analyzer)
- Create: `lib/core/state/connect_controller.dart` (the connect/handshake orchestrator above the port: adopt/reconcile, lockout state; cross-feature per conventions — sole caller of `BleService.connect`)
- Modify: `lib/features/discovery/discovery_page.dart`, `lib/features/settings/settings_page.dart` (call sites shrink to `connect()`)
- Delete: `lib/core/state/selection_sync.dart`
- Modify: `lib/core/models/command.dart` (protocol version bump, new typed statuses)
- Test: `test/core/ble/`, `test/core/state/`

**Approach:**
- Service emits `connecting → reconciling → connected`; UI action gating keys off `connected` only. Reconcile failure or handshake timeout → typed failure, link dropped — no half-hydrated state. The service owns the sole handshake timeout; the settings banner's caller-side `.timeout(5s)` wrapper is removed when the call site shrinks (Dart's `Future.timeout` doesn't cancel the underlying op — caller and service would disagree).
- Telemetry and match-state pollers start only after reconcile completes (connection state == `connected`) — today they start inside `connect()`, and a match-state poll landing mid-handshake would mutate `LiveMatchState` from initial and persist-on-change would overwrite the real persisted scoreboard before restore reads it.
- Rehydrate writes firmware actuals into the same providers the UI already watches (active camera, preview layout) — adoption replaces force-reset.
- Intent vs observed stay separate values (settings-toggle learning): adopting runtime flags never rewrites persisted user intent.
- Keep in-flight dedup + timeouts from the lifecycle-correctness learning.

**Test scenarios:**
- Covers AE1 (reconciliation), AE2, AE3. Happy path: connect to idle firmware → defaults adopted from snapshot (not hardcoded); connect to recording firmware → UI state shows recording, selections match snapshot.
- Edge: match-state poll emitted while state is `reconciling` → never mutates or persists `LiveMatchState`; pollers observed to start only after `connected`.
- Happy path: persisted match matches running `match_uuid` → `SetMatchState` pushed with app scores + firmware clock.
- Edge: unknown running `match_uuid` → scoreboard view adopted from firmware, no `SetMatchState` push.
- Edge: command issued during `reconciling` → blocked/queued, never sent early.
- Error: snapshot read times out → connect fails typed, state returns to disconnected, no partial hydration.
- Error: protocol version mismatch → typed failure before any time push/snapshot.
- Integration: both former call sites produce identical behavior through the service; `resetSelectionOnConnect` no longer referenced anywhere.

**Verification:**
- All four origin connect scenarios pass in widget/service tests against the parity mock (U7); on metal each scenario ends in a correct UI within one connect.

---

### U2. Scoreboard persistence + clock reconcile + away-ended handling

**Goal:** Match state survives app kills; firmware clock corrects the app clock; matches that ended while away are explained and finalized.

**Requirements:** Origin R1, R4; F2; AE1, AE4 (app half)

**Dependencies:** U1

**Files:**
- Modify: `lib/features/match/session/session_state.dart` (persist-on-change; wall-clock period anchor; restore path; uncommanded-transition tolerance)
- Modify: `lib/core/db/` (persisted live-match table keyed device+match, or a scoped store — follow Drift patterns; regenerate via `just gen-db`)
- Modify: `lib/features/match/session/session_screen.dart` (away-ended notice; finalize path reuse), `ble_providers.dart` (match-state poll consumer)
- Test: `test/features/match/`

**Approach:**
- Persist `LiveMatchState` (scores, period, events, period-start wall anchor, match/device ids) on every mutation; restore on rejoin when `match_uuid` matches.
- Clock: elapsed derives from wall anchor while running locally; on rejoin and on every 2 s poll, firmware elapsed wins (drift correction); adopted elapsed ≥ period length → fire period-end immediately.
- Idle-with-history: last-session summary is used only when its `match_uuid` equals the persisted match's uuid → single-line notice ("Match ended while away — saved at 47:12" / "camera restarted — check the recording"), finalize `team_matches` with persisted app data, clear the live store. Summary absent or uuid mismatch → generic ended notice, finalize with app data only.
- Running-session uuid ≠ persisted uuid (camera rebooted mid-match Y and started match Z, or second phone's session): finalize the stale persisted match via the away-ended path first, then adopt the running session — the persisted row is never orphaned ("cleared exactly once" holds).
- Poll truth: recording→idle observed without command → session controller follows firmware, shows the same notice path.

**Test scenarios:**
- Covers AE1: kill app at 2–1 mid-recording, reopen, connect → scoreboard 2–1, recording in progress, clock = firmware elapsed.
- Covers AE4 (app half): reconnect after auto-stop → "ended while away" notice with end-reason, `team_matches` row finalized, live store cleared.
- Happy path: 2 s poll corrects a drifted local clock while connected.
- Edge: adopted elapsed ≥ period length → period-end fired once (not repeatedly).
- Edge: persisted match for camera A never hydrates against camera B (device-key check).
- Edge: app killed before first persist → rejoin falls back to firmware-derived view (no crash on empty store).
- Error: summary absent (old firmware/unknown) → generic ended notice, finalization still completes.
- Edge: camera rebooted mid-match then connect → summary uuid mismatch handled (no cross-match data in the notice); persisted match finalized via away-ended path before adopting the new session.
- Integration: full disconnect→score-in-app-not-sent→rejoin cycle: app scores win via `SetMatchState`, firmware clock wins, overlay divergence not treated as error.

**Verification:**
- AE1 provable in tests + on metal: zero scoreboard loss (app data), no footage loss, correct clock after rejoin.

---

### U3. Health gating + device-inoperable UX

**Goal:** Any camera not OK → preview/record/stream blocked with explicit "device inoperable" surface; downloads/diagnostics stay reachable; recovering never flaps.

**Requirements:** Origin R7, R8; F3; AE5

**Dependencies:** Proto plan U1 (health fields on the wire); firmware plan U3 (health computation/reporting); app U1 (snapshot read)

**Files:**
- Create: `lib/core/state/device_health.dart` (derived health provider: snapshot ⊕ telemetry)
- Modify: `lib/core/models/telemetry.dart` (per-camera health), `ble_protocol.dart` mapping
- Modify: preview/record/stream action surfaces: `lib/features/camera/main_page.dart`, `lib/features/match/session/session_screen.dart`, `setup_screen.dart`, `lib/core/widgets/live_preview_view.dart` (gate + disabled affordances)
- Create: inoperable banner widget (persistent-banner pattern) in `lib/core/widgets/`
- Test: `test/core/state/`, `test/features/camera/`

**Approach:**
- Provider yields `ok / recovering / inoperable` device-level state from per-camera values (any DOWN → inoperable; any RECOVERING → recovering). Consumers: action gating (disable + reason), banner visibility, diagnostics page.
- Inoperable: banner persistent, actions disabled with copy pointing at diagnostics; downloads flow untouched (gate never touches download/wifi paths). Recovering: soft inline indicator, actions stay enabled (firmware rejects starts anyway — typed rejection mapped to a clear snackbar as backstop).
- Gate active in dev/mock backend too (convention learning).

**Test scenarios:**
- Covers AE5: telemetry flips one camera DOWN → banner appears, preview/record/stream disabled, downloads button still enabled.
- Happy path: both OK → no banner, all actions enabled.
- Edge: RECOVERING → no inoperable banner, no action lockout, soft indicator shown; flapping OK↔RECOVERING never flashes the banner.
- Edge: conflicting snapshot vs telemetry (stale snapshot) → newest source wins.
- Error: start-recording typed rejection from firmware (gap window) → clear error surface, no silent failure.
- Integration: health provider drives the same gate on main page, session screen, and setup screen (no per-page divergence).

**Verification:**
- Camera-down simulation in mock shows the full gating UX; on metal, blinding a camera produces banner + gating within the health window.

---

### U4. Diagnostics indicators

**Goal:** Per-camera live status indicators + per-mic offline placeholders on the diagnostics page.

**Requirements:** Origin R9; AE6

**Dependencies:** U3 (health provider)

**Files:**
- Modify: `lib/features/discovery/diagnostics_page.dart`
- Test: `test/features/discovery/`

**Approach:**
- Camera 0/1 status tiles (OK/recovering/down/—) from the health provider; two mic tiles hardcoded offline placeholders per origin R9; follow the "unreported renders — never fabricated" page convention and existing `_StatTile` layout.

**Test scenarios:**
- Covers AE6: both cameras OK → two online camera tiles + two offline mic tiles.
- Edge: disconnected → camera tiles render "—" (unreported), not stale OK.
- Edge: one camera down → that tile shows down while the other stays OK.

**Verification:**
- Page renders correct states across mock health permutations.

---

### U5. Auto-stop setting

**Goal:** App-configurable unsupervised-session timeout, default 30 min, pushed with session config.

**Requirements:** Origin R5 (config side)

**Dependencies:** Proto plan U1

**Files:**
- Modify: `lib/features/settings/settings_page.dart` (or camera settings sub-page — follow settings layout), settings persistence (shared_preferences pattern)
- Modify: `lib/features/match/setup_screen.dart` + `ble_protocol.dart` (field on session config push; re-push on mid-session change)
- Test: `test/features/settings/`, `test/features/match/`

**Test scenarios:**
- Happy path: default 30 pushed when user never touched the setting.
- Happy path: user sets 90 → next session config carries 90; persists across app restarts.
- Happy path: setting changed while connected to an active session → new value pushed to firmware immediately (one extra command), not silently deferred to the next session.
- Edge: bounds enforced (no 0/negative; sensible max).

**Verification:**
- Firmware receives the configured value (contract test against mock; metal check via AE4 timing).

---

### U6. BLE auto-reconnect

**Goal:** Unexpected drop → app re-establishes to the last-connected camera automatically through the full handshake; manual disconnect never triggers it.

**Requirements:** Origin R17; F2

**Dependencies:** U1 (handshake makes reconnect safe)

**Files:**
- Modify: `lib/core/ble/ble_service_impl.dart` or a small reconnect controller beside it (service layer), `ble_providers.dart` (reconnecting surfaced in connection state)
- Modify: `lib/core/wifi/wifi_handoff.dart` — suppress the 400 ms disconnect-teardown while a session is active or the reconnect loop is still eligible; the group tears down only on manual disconnect, camera change, or loop give-up (firmware keeps its side up; the app must rejoin, not cycle)
- Modify: manual-disconnect call sites to mark intent (suppress loop)
- Test: `test/core/ble/`

**Approach:**
- Loop: on unexpected `disconnected` (edge from `connected` only — a failed attempt's own `disconnected` emission never re-arms or resets backoff), retry via the U1 connect controller (`lastConnectedDeviceId`) with backoff (a few quick attempts then slower cadence). Stop on: manual disconnect, different-device selection, bluetooth-off, success, or a permanent typed failure (protocol-version mismatch gets its own UI surface). Every attempt is the full U1 handshake — no shortcut path.
- In-flight dedup with manual connect attempts (one connect at a time, lifecycle learning).

**Test scenarios:**
- Happy path: unexpected drop → reconnect attempt fires, succeeds → rehydrated exactly like a manual connect.
- Happy path: unexpected drop mid-session → WiFi group stays up through the whole reconnect (no `disconnectGroup` from the handoff controller); preview resumes without group re-formation.
- Edge: manual disconnect → loop never starts.
- Edge: user taps connect manually while loop is backing off → single connect in flight, no race.
- Edge: bluetooth turned off mid-loop → loop stops, resumes eligibility on next unexpected drop only.
- Error: device stays gone → backoff caps, UI keeps honest disconnected state with reconnecting indicator, no infinite tight loop.

**Verification:**
- Mid-match camera power-cycle on metal: app reconnects and silently rejoins without user action (origin scenario 4 upgraded — button press no longer required).

---

### U7. Mock parity — make all of it testable pre-metal

**Goal:** `MockBleService`/`MockWifiService` implement the new contract semantics so U1–U6 (and firmware-behavior-dependent tests) run at the alpha CI rung.

**Requirements:** Origin R14 (verification path); every AE's testability

**Dependencies:** Proto plan U1 (shapes); developed alongside U1–U6

**Files:**
- Modify: `lib/mock/emulator/mock_ble_service.dart`, mock wifi service
- Test: mock behavior assertions in `test/mock/`

**Approach:**
- Mock gains: session survives mock disconnect; snapshot command (session axes, elapsed that ticks while "disconnected", match state, health, last-session summary); `SetMatchState`; auto-stop timer (compressed timescale for tests); injectable per-camera health; group-stays-up semantics.
- Mirror wire behavior, not app convenience (mock-parity learning).

**Test scenarios:**
- Mock disconnect→reconnect preserves running session + advanced clock.
- Injected DOWN camera propagates through telemetry + snapshot identically to real firmware semantics.
- Mock auto-stop fires on compressed timer → idle snapshot with summary.

**Verification:**
- Every AE1–AE6 test in U1–U6 runs green against the mock in `just ci` — no hardware required until the metal checkpoint.

---

### U8. App polish sweep

**Goal:** Whole-repo structural polish delivered as bounded per-area sweeps (origin R12), with the broad bug/optimization review riding each area (origin R13) — closed area list below covers the app repo end to end.

**Requirements:** Origin R12, R13

**Dependencies:** U1–U7, U9 (runs last — polishes final shapes)

**Files (per-area closed list — together these cover the repo):**
- Area A, match: `lib/features/match/` — `session_screen.dart` split (screen / modals / finalize logic), `setup_screen.dart`, opponent-name parsing → single helper; two-match-models seam — one explicit mapping layer between wire `MatchState` and `LiveMatchState` (U1/U2 build it; sweep removes leftover ad-hoc conversions)
- Area B, video: `lib/features/video/` — `download_sheet.dart` split, `video_match_detail_page.dart`, playback/library review
- Area C, settings + people: `lib/features/settings/` (all sub-pages: streaming, developer, sport presets, data), `users/`, `teams/` review
- Area D, camera + discovery: `lib/features/camera/`, `lib/features/discovery/`, landing/main pages — preview-button/layout-toggle row → shared widget
- Area E, core: `lib/core/` (ble, wifi, db, services, state, shell, widgets, models) — dedupe `Border.toBoxDecoration` → `core/`, logging consistency (`debugPrint` stragglers → `Logger`: `wifi_handoff.dart`, finalize path), import-direction check
- Area F, mock: `lib/mock/` — dedupe `mock_ble_service.dart`'s copy of `BleProtocol` encode/decode tables
- Delete: `_old/` tree, stray root files (`flutter_01.log`, `scout_camera.iml`)
- Docs drift: `CLAUDE.md` nonexistent-file references; `docs/firmware-spec.md` sync
- Test: suite stays green; add coverage only for touched untested seams

**Approach:**
- Behavior-preserving; each area gets the R13 broad bug/optimization review as it is swept (trivial findings fixed in that area's pass, behavioral ones surfaced first).

**Test scenarios:**
- Test expectation: behavior-preserving refactor — full suite green (627+) is the gate; new tests only where touched seams were untested.

**Verification:**
- `just ci` green (format, analyze, tests); no file repo-wide over ~600 lines without cause; core→feature import direction clean; every area A–F swept.

---

### U9. AF mode control

**Goal:** Operator can switch continuous-AF vs manual focus from the app; effective mode visible.

**Requirements:** Origin R15 (app side)

**Dependencies:** Firmware plan U6 (the AF loop this controls); wire surface already exists (`CameraFocusControlCommand.mode`)

**Files:**
- Modify: camera controls surface (follow where manual focus lives today) + `ble_protocol.dart` if the mode mapping is missing
- Modify: `lib/mock/emulator/mock_ble_service.dart` (mode echo parity)
- Test: `test/features/camera/`

**Approach:**
- Toggle sends `CameraFocusControlCommand(mode: auto|manual)`; UI reflects the effective mode echoed by `CameraFocusResponse` (observed state), separate from the user's last request (intent) per the intent-vs-observed learning.
- Copy notes AF pauses during recording (firmware default this cycle).

**Test scenarios:**
- Happy path: toggle to manual → command sent, UI shows manual after response echo.
- Edge: toggle while disconnected → blocked with the standard disconnected affordance (no fire-and-forget).
- Edge: firmware echoes a different effective mode than requested → UI shows the echo, not the request.

**Verification:**
- Mode round-trip works against the parity mock; on metal, toggling visibly starts/stops AF hunting.

---

## System-Wide Impact

- **Interaction graph:** connection-state consumers (hero card, session screen, preview widgets, `wifi_handoff` debounce) all see the new `reconciling` state — each audited in U1. `wifi_handoff` must not tear down/re-form the group on reconnect while a session is active (firmware keeps it up; app must rejoin, not cycle — coordinates with firmware plan U1).
- **Error propagation:** typed rejections (health-gated starts, protocol mismatch, handshake timeout) each get a distinct user surface; no silent fire-and-forget for session-affecting commands after this cycle.
- **State lifecycle risks:** persisted live-match store must be cleared exactly once per match (finalize paths: normal end, away-ended, unknown-session adoption); double-finalize of `team_matches` guarded.
- **API surface parity:** protocol version bump in `command.dart`; `docs/firmware-spec.md` updated (convention); mock parity is U7; emulator repo deferred.
- **Integration coverage:** the four connect scenarios + AE1–AE6 as end-to-end tests against the parity mock.
- **Unchanged invariants:** UI touches only `BleService`/`WifiService` ports; lean-recovery WiFi stance (OS rejoins persistent group; app never drives WiFi reconnection); pull model — app initiates everything.

---

## Risks & Dependencies

| Risk | Mitigation |
|------|------------|
| Handshake rework regresses the two working connect flows | Both call sites collapse to one tested implementation; four-scenario test matrix against parity mock before metal |
| Auto-reconnect loops against a flaky link drain battery / spam firmware | Backoff with cap; loop stops on manual intent; reconnecting state visible |
| Persisted live-match store drifts from `team_matches` finalization | Single finalize path shared by normal/away-ended/adopted flows (U2) |
| Mock parity lags and tests go green against fiction | U7 developed alongside U1–U6, not after; AE tests written against mock semantics defined by the proto contract |
| dda0017-class regression: firmware and app defaults diverge on connect | Adoption-from-snapshot removes the default-assumption entirely — snapshot is the only source |

---

## Open Questions

### Resolved During Planning

- Score authority on rejoin: app scores (deltas made while disconnected never reached firmware); clock authority: firmware (only clock that ran).
- Idle-with-history UX: one-line notice + auto-finalize, no prompt.
- Unknown-session rejoin: adopt firmware-derived scoreboard view silently.
- Auto-reconnect: last-connected device only, service-layer, full handshake per attempt.

### Deferred to Implementation

- Live-match persistence medium (Drift table vs scoped key-value): decide against existing Drift patterns when touching `core/db/`.
- Reconnect backoff curve specifics: tune during implementation/metal.
- Exact split boundaries for `session_screen.dart`: decided during U8 with the final U1–U7 shapes in front of us.

---

## Sources & References

- **Origin document:** [docs/brainstorms/2026-07-06-state-health-quality-cycle-requirements.md](docs/brainstorms/2026-07-06-state-health-quality-cycle-requirements.md)
- Companion plans: `sst-cam-proto` + `sst-cam-firmware`, same date/seq.
- Learnings: see Context & Research above.
