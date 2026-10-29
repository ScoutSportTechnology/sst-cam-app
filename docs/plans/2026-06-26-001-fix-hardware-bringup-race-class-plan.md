---
title: "fix: Hardware bring-up race-bug class (mock-fidelity)"
type: fix
status: active
date: 2026-06-26
origin: docs/brainstorms/2026-06-26-hardware-bringup-race-class-requirements.md
---

# fix: Hardware bring-up race-bug class (mock-fidelity)

## Summary

Fix the class of defect exposed on first real-hardware install: the app was built
against forgiving mocks that replay stream values and skip the transport, so connect,
discovery, telemetry, match state, and WiFi preview all race or fail on device. Ships in
three phases — Layer 0 (a standalone `fix/*` branch that unblocks hardware), then Layer 1
(provider lifecycle), then Layer 2 (contract tests + a fake-transport seam that makes the
divergence structurally impossible and catches the transport-class bugs in CI).

---

## Problem Frame

The four bugs seen on hardware (black icon, discovery race, connect-fails card, blocked
testing) are symptoms of one root cause: mocks implement the `BleService`/`WifiService`
*ports* and replace the entire transport, behaving leniently where real BLE/WiFi does
not. Full root-cause detail with file:line lives in the origin requirements doc (see
Sources & References).

---

## Requirements

- R1. App connects to real firmware and reaches `connected` end-to-end; telemetry, match
  state, discovery, and WiFi preview state render without re-entry/Scan dances.
- R2. No flash of empty/loading/stale state on connect, discovery, preview, or session entry.
- R3. Prod launcher icon renders correctly (yellow bg + SC + red dot).
- R4. Connect failures show the real, actionable error message in an on-brand card with Retry.
- R5. A contract-test suite fails CI if mock and real stream semantics diverge.
- R6. The fake-transport seam reproduces the write-mode class of bug as a failing test
  (GAP1 would have been caught pre-hardware).
- R7. Layer 0 lands as a standalone shippable branch ahead of Layers 1–2.

---

## Scope Boundaries

- Device-id / `sst-cam-0000` provisioning — separate firmware track (see origin:
  `../../../sst-cam-firmware/docs/brainstorms/2026-06-26-device-id-provisioning-requirements.md`).
- Implementing real preview frame/stats streams (intentionally VLC-side today).
- Real overlay-state data (both impls are stubs today).
- No firmware code changes — Layer 0 GAP1 fix is app-side only.

### Deferred to Follow-Up Work

- Full transport-realism mock knobs (typed connect failures, injected timeouts,
  disconnect-mid-command, HTTP 401/410/Range, multi-chunk reorder — GAP5/6/7/10/12):
  modeled minimally where needed for Layer 2 tests; exhaustive coverage is a follow-up
  once the fake-transport seam exists.

---

## Context & Research

### Relevant Code and Patterns

- **Seed-then-subscribe template (the correct in-repo pattern):**
  `lib/features/settings/streaming/streaming_state.dart:30-55` — AsyncNotifier seeds via
  `await get…()`, subscribes the watch stream, `ref.onDispose(sub.cancel)`. No
  first-emission drop. Mirror this for the live device providers.
- **Mock already does replay (real does not):** `lib/mock/emulator/mock_wifi_service.dart:188-202`
  (`Stream.multi` + current-state replay, with a comment describing the exact hazard the
  real impl lacks); `lib/mock/emulator/mock_ble_service.dart:436-441` (async* snapshot).
- **Real impls to fix:** `lib/core/ble/ble_service_impl.dart` (`:48`, `:124-128`,
  `:218-235`, `:265-272`, `:483/489`, `:578`), `lib/core/wifi/wifi_service_impl.dart` (`:227`).
- **Ports:** `lib/core/ble/ble_service.dart`, `lib/core/wifi/wifi_service.dart`.
- **Providers (all non-autoDispose):** `lib/core/ble/ble_providers.dart`,
  `lib/core/wifi/wifi_providers.dart`.
- **Design system:** `lib/core/theme/tokens.dart`, `lib/core/widgets/wf_card.dart`,
  `lib/core/widgets/wf_button.dart`, theme wiring in `lib/app.dart`.
- **Firmware contract anchor:** command char is `write-without-response` only —
  `../sst-cam-firmware/src/adapters/control/ble/bluez/gatt-application.cpp:77-78`; protocol
  framing/flow-control in `proto/README.md:89-152`, `docs/firmware-spec.md:152-200`.
- **Chunk framing util / existing isolated test:** `lib/core/ble/ble_protocol.dart`,
  `test/ble/chunk_mtu_test.dart`.

### Institutional Learnings

- No `docs/solutions/` entries cover BLE/stream/Riverpod fidelity yet — this plan is a
  strong candidate for a learning doc after Layer 2 (the mock-above-the-port pitfall).

### External References

- None needed; local patterns (streaming_state, mock Stream.multi) are sufficient.
  flutter_blue_plus write-mode semantics confirmed against firmware GATT flags in-repo.

---

## Key Technical Decisions

- **Shared seeded-broadcast primitive, used by both impls.** Introduce one small helper
  in `lib/core/async/` (e.g. a current-value broadcast wrapper: seed a last-value, replay
  it on subscribe, then forward). Both real impls and (where practical) mocks route their
  streams through it so replay semantics cannot diverge again. Rationale: fixing each site
  by hand re-creates the divergence risk; a single primitive + contract tests (U11) makes
  it structural. Hand-roll over adding an rxdart `BehaviorSubject` dependency unless
  research during U4 shows the hand-roll is fragile — the mock already hand-rolls
  `Stream.multi`, so the idiom exists in-repo.
- **Stable per-device controller identity.** Real BLE per-device controllers must be
  created lazily on first stream access (`putIfAbsent`) and reused by `connect()`, not
  recreated inside `connect()`. This is what makes connection/telemetry/match state reach
  the UI. (Origin Class A, critical.)
- **GAP1 fix is app-side `withoutResponse: true`.** Matches the firmware's
  `write-without-response`-only char; the firmware `ChunkAck` notify is the real
  confirmation channel. No firmware rebuild. (Origin Layer 0.)
- **autoDispose + seed for live providers.** Adopt the streaming_state AsyncNotifier shape
  so providers tear down on disconnect/navigation and never serve stale frames, while
  closing the first-emission window via the seed.
- **Fake-transport seam runs the REAL impl logic.** The seam fakes the GATT characteristic
  (carrying declared `write-without-response`/`notify` properties) and the P2P/EventChannel,
  then drives the real `BleServiceImpl`/`WifiServiceImpl` code paths — not a hand-written
  stand-in. This is the only thing that catches GAP1/2/3/8/12. Placement (this repo vs
  `sst-cam-emulator`) resolved in Open Questions.

---

## Open Questions

### Resolved During Planning

- **Seeded-broadcast: dependency vs hand-roll?** → Hand-roll a `core/async` primitive
  first (mock already uses `Stream.multi`); revisit rxdart only if U4 shows fragility.
- **GAP1: fix app or firmware?** → App-side `withoutResponse: true`; no firmware change.
- **Sequencing?** → Layer 0 on its own `fix/*` branch, shippable independently (R7);
  Layers 1–2 on follow-up branch(es).

### Deferred to Implementation

- **Fake-transport seam placement** (U12): new test-only fake in this repo
  (`test/fakes/transport/`) vs a build variant in `sst-cam-emulator`. Lean test-only-in-app
  for CI proximity; coordinate with the emulator build-variant strategy before committing.
  Decide when U12 starts, after seeing how much native-channel surface the fake must cover.
- Exact helper/class names, MTU-budget constants for the fake, and which mock knobs U11/U13
  need are execution-time details.

---

## High-Level Technical Design

> *This illustrates the intended approach and is directional guidance for review, not
> implementation specification. The implementing agent should treat it as context, not
> code to reproduce.*

Class A fix shape — current-value broadcast + stable controller (directional):

```
// core/async: seed last value, replay on subscribe, then forward live events.
currentValueStream(seed):
    on listen -> emit current/last value, then forward controller.stream

// real impl: per-device controller is lazy + stable, reused by connect()
connectionStateStream(id):
    return deviceState(id).connController.currentValueStream()   // NOT Stream.value(...)
connect(id):
    ds = _devices.putIfAbsent(id, () => DeviceState())           // reuse, don't recreate
    ds.connController.add(connecting); ... ds.connController.add(connected)
```

Phase dependency graph:

```mermaid
graph TD
  subgraph L0[Layer 0 — unblock fix/* branch]
    U1[U1 icon bg]
    U2[U2 write mode]
    U3[U3 error card]
    U4[U4 BLE stream identity]
    U5[U5 WiFi stream identity]
  end
  subgraph L1[Layer 1 — lifecycle]
    U6[U6 autoDispose+seed]
    U7[U7 loading states]
    U8[U8 match timer]
    U9[U9 ref.listen effects]
    U10[U10 stop loading→[] collapse]
  end
  subgraph L2[Layer 2 — prevention]
    U11[U11 contract tests]
    U12[U12 fake transport seam]
    U13[U13 real-impl-on-fake tests]
  end
  U4 --> U6
  U5 --> U6
  U6 --> U7
  U4 --> U11
  U5 --> U11
  U2 --> U13
  U12 --> U13
  U11 --> U13
```

---

## Implementation Units

### U1. Prod launcher icon background

**Goal:** Prod adaptive icon renders yellow bg + SC + red dot (currently black-on-black).

**Requirements:** R3

**Dependencies:** None

**Files:**
- Modify: `flutter_launcher_icons-prod.yaml`

**Approach:**
- Change `adaptive_icon_background: "#0A0A0A"` → `"#E8FF3C"` to match the legacy prod icon
  (`launcher/icon-prod-1024.png`) and make the black `icon-prod-foreground.png` lettering
  visible. CI regenerates `src/prod/res` via `dart run flutter_launcher_icons`
  (`.github/workflows/release-beta.yml:299`).

**Patterns to follow:**
- `flutter_launcher_icons-dev.yaml` (already yellow bg + black foreground, renders fine).

**Test scenarios:**
- Test expectation: none — config-only. Verify visually via `just gen-icons` output
  (generated `src/prod/res/.../ic_launcher` adaptive background = `#E8FF3C`).

**Verification:**
- After `just gen-icons`, the generated prod adaptive background color is `#E8FF3C`; a
  prod build's launcher icon shows the SC mark, not a lone red dot.

---

### U2. BLE command-write mode (GAP1, the connect blocker)

**Goal:** Command frames write with `withoutResponse: true` so the handshake succeeds
against the firmware's `write-without-response`-only command characteristic.

**Requirements:** R1

**Dependencies:** None

**Files:**
- Modify: `lib/core/ble/ble_service_impl.dart`
- Test: `test/ble/ble_service_impl_test.dart` (or nearest existing BLE service test)

**Approach:**
- Change the two command-frame writes (`:483` single-frame, `:489` multi-frame loop) from
  `withoutResponse: false` to `true`. ACK writes already use `true` (`:578`). The
  multi-frame loop's per-write ATT confirmation is replaced by the firmware's `ChunkAck`
  notify (already awaited via `_pendingAcks`), so flow control is preserved.

**Patterns to follow:**
- The existing ACK write at `lib/core/ble/ble_service_impl.dart:578`.

**Test scenarios:**
- Happy path: a single-frame command issues a write with `withoutResponse == true`.
- Happy path: a multi-frame command issues each frame write with `withoutResponse == true`
  and still gates the next frame on the inbound ChunkAck.
- Integration (with U13 fake transport): a command write against a char declaring only
  `write-without-response` succeeds (today it would be rejected).

**Verification:**
- Connect handshake (`GetDeviceInfo`) completes against a char that exposes only
  `write-without-response`; no write-mode rejection.

---

### U3. On-brand connect error card with real message + Retry

**Goal:** Replace the bare `SnackBar` with a design-system failure surface that shows the
caught exception's `.message` and offers a working Retry.

**Requirements:** R4

**Dependencies:** None

**Files:**
- Modify: `lib/features/discovery/discovery_page.dart`
- Modify: `lib/app.dart` (add `snackBarTheme`)
- Test: `test/features/discovery/discovery_page_test.dart`

**Approach:**
- At the connect call site (`discovery_page.dart:267-276`), bind the caught exception
  (`catch (e)` not `catch (_)`) and surface its `.message` (the impl throws
  `BleConnectionException`/`BleProtocolVersionException` with descriptive messages). Render
  via `WfCard` + `WfButton` (Retry re-invokes connect) using `tokens.dart` (`T.danger`),
  matching the scan handler that already shows `e.message` (`:39-44`).
- Add a `snackBarTheme` to `lib/app.dart` ThemeData so any remaining SnackBars are on-brand.

**Patterns to follow:**
- `lib/features/discovery/discovery_page.dart:39-44` (binds `e`, shows `e.message`).
- `lib/core/widgets/wf_card.dart`, `wf_button.dart`, `lib/core/theme/tokens.dart`.

**Test scenarios:**
- Happy path: connect throws `BleConnectionException('Device info handshake failed: …')`
  → the failure surface displays that message text.
- Edge case: a `BleProtocolVersionException` surfaces its expected/actual message, not a
  generic string.
- Happy path: tapping Retry re-invokes `connect(device.id)`.
- Widget: the failure surface uses `WfCard`/`WfButton` (design tokens), not a default SnackBar.

**Verification:**
- A failed connect shows the actual error reason and a Retry that re-attempts; no
  hardcoded "Connection failed — retry?" with a dropped exception.

---

### U4. BLE real-impl stream identity + replay (Class A)

**Goal:** connection/telemetry/match/discovery streams replay current value on subscribe
and use stable per-device controllers reused across `connect()`.

**Requirements:** R1

**Dependencies:** None (introduces the `core/async` primitive used by U5, U11)

**Files:**
- Create: `lib/core/async/current_value_stream.dart` (seeded-broadcast primitive)
- Modify: `lib/core/ble/ble_service_impl.dart`
- Test: `test/core/async/current_value_stream_test.dart`
- Test: `test/ble/ble_service_impl_test.dart`

**Approach:**
- Add the seeded-broadcast primitive (seed last value, replay on subscribe, forward live).
- `discoveredDevices` (`:48`): route through the primitive seeded with current `_discovered`;
  stop the eager clear/`add([])` race at scan start (clear on first real result or dedupe by id).
- Per-device `_ConnectedDevice`/controllers: create lazily via `putIfAbsent` on first
  `connectionStateStream`/`telemetryStream`/`matchStateStream` access, seed with current
  state, and have `connect()` reuse them instead of `Stream.value(disconnected)` /
  `Stream.empty()` / fresh-controller-in-connect (`:124-128`, `:218-235`, `:265-272`).

**Patterns to follow:**
- Mock replay idioms: `lib/mock/emulator/mock_ble_service.dart:436-441` (snapshot),
  `mock_wifi_service.dart:188-202` (`Stream.multi`).

**Test scenarios:**
- Happy path: subscribing to `connectionStateStream(id)` BEFORE `connect()` then connecting
  delivers `connecting`→`connected` to the existing subscriber.
- Edge case: a late subscriber (after `connect()`) immediately receives the current
  `connected` state (replay).
- Happy path: `telemetryStream`/`matchStateStream` subscribed pre-connect receive ticks
  after connect (no permanent `Stream.empty()` binding).
- Edge case: `discoveredDevices` late subscriber receives the current device list; a second
  page entry does not wipe already-discovered devices.
- Primitive unit: replays last value to N subscribers, forwards subsequent events, completes/cleans up.

**Verification:**
- After connect, every widget reading connection/telemetry/match state updates; discovery
  shows devices on first entry without the re-enter/Scan dance.

---

### U5. WiFi real-impl stream identity + replay (Class A)

**Goal:** WiFi `connectionStateStream` replays current state on subscribe (matches the
mock's `Stream.multi` fix the real impl lacks).

**Requirements:** R1, R2

**Dependencies:** U4 (reuse `core/async` primitive)

**Files:**
- Modify: `lib/core/wifi/wifi_service_impl.dart`
- Test: `test/wifi/wifi_service_impl_test.dart`

**Approach:**
- Route `connectionStateStream` (`:227`) through the seeded primitive (or mirror the mock's
  `Stream.multi` + current-state replay at `mock_wifi_service.dart:188-202`), seeding the
  per-device state controller so `LivePreviewView` (a deliberate late subscriber,
  `lib/core/widgets/live_preview_view.dart:189`) sees the current `connected` state.

**Patterns to follow:**
- `lib/mock/emulator/mock_wifi_service.dart:188-202`.

**Test scenarios:**
- Happy path: a subscriber attaching after `connectGroup` reaches `connected` immediately
  receives `connected` (not stuck on null/connecting).
- Edge case: state transitions emitted during `connectGroup` are not lost to a late subscriber.

**Verification:**
- Toggling live preview after the group is up shows a correct WiFi state badge without a
  state change being required to "unstick" it.

---

### U6. autoDispose + seed-then-subscribe for live device providers

**Goal:** Live device providers tear down on disconnect/navigation and never serve stale
frames, while closing the first-emission window via a seed.

**Requirements:** R1, R2

**Dependencies:** U4, U5

**Files:**
- Modify: `lib/core/ble/ble_providers.dart`
- Modify: `lib/core/wifi/wifi_providers.dart`
- Test: `test/core/ble/ble_providers_test.dart`
- Test: `test/core/wifi/wifi_providers_test.dart`

**Approach:**
- Convert the live device providers (discovered devices, connection/telemetry/match state,
  wifi state) to `autoDispose` and adopt the AsyncNotifier seed-then-watch shape from
  `streaming_state.dart` where they hold derived state. Keep providers that must outlive a
  single page (e.g. active-camera identity) non-autoDispose deliberately and document why.
- Ensure teardown cancels subscriptions (`ref.onDispose`).

**Patterns to follow:**
- `lib/features/settings/streaming/streaming_state.dart:30-55`.

**Test scenarios:**
- Happy path: provider seeds initial value then updates from the stream.
- Edge case: provider disposes when no longer watched; re-watch re-seeds (no stale cached frame).
- Integration: disconnect tears down telemetry/match providers (no leak, no stale data).

**Verification:**
- No stale telemetry/frame after disconnect; providers rebuild cleanly on re-entry.

---

### U7. Replace `.valueOrNull` flashes with explicit loading states

**Goal:** Stop the empty/loading/stale flash on connect, preview, and session entry.

**Requirements:** R2

**Dependencies:** U6

**Files:**
- Modify: `lib/features/camera/main_page.dart`
- Modify: `lib/core/widgets/live_preview_view.dart`
- Modify: `lib/features/match/session/session_screen.dart`
- Test: `test/features/camera/main_page_test.dart`
- Test: `test/features/match/session/session_screen_test.dart`

**Approach:**
- Replace `.valueOrNull ?? default` reads (main_page telemetry grid `:30-40`,
  live_preview_view `:188-217`, session_screen `:38-59`) with `.when` /
  `AsyncValue.unwrapPrevious` so loading and data are visually distinct and the first frame
  isn't a misleading empty/disabled state. Guard session command callbacks so a tap during
  the loading frame isn't silently dropped.

**Patterns to follow:**
- Existing `.when(loading: …)` branch in `lib/features/video/video_page.dart:40`.

**Test scenarios:**
- Happy path: main_page shows a loading affordance (not "—") until first telemetry tick.
- Edge case: live preview shows a distinct connecting state, not a stale prior-session frame.
- Edge case: session controls reflect loading vs disconnected distinctly; a command tapped
  before `connected` resolves is not silently no-op'd.

**Verification:**
- No visible flash of empty/stale/disabled UI in the first frame of connect/preview/session.

---

### U8. Bind match timer to match-live state

**Goal:** The 1 Hz match tick runs only while a match is live, with cancel-before-create.

**Requirements:** R2

**Dependencies:** None

**Files:**
- Modify: `lib/features/match/match_page.dart`
- Modify: `lib/features/match/session/session_state.dart` (if the timer moves into state)
- Test: `test/features/match/session/session_state_test.dart`

**Approach:**
- Move the `Timer.periodic` out of `MatchPage.initState` (`:38-49`, where IndexedStack keeps
  it running 24/7) and drive it from `liveMatchProvider` phase transitions (start on
  period+running, stop otherwise), with a cancel-before-create guard.

**Patterns to follow:**
- `lib/features/match/session/overlay_renderer.dart:66,87` (timer cancel-before-create + dispose).

**Test scenarios:**
- Happy path: timer ticks only when match phase is period+running.
- Edge case: leaving/pausing the match stops the timer (no background ticks).
- Edge case: re-entering does not double-start (cancel-before-create).

**Verification:**
- No background ticks when no match is live; no double-tick after re-entry.

---

### U9. Move build()-time side-effects to `ref.listen`

**Goal:** Fire scan-start and player-start on the state transition, not from a
possibly-missed first build / post-frame.

**Requirements:** R1, R2

**Dependencies:** U6

**Files:**
- Modify: `lib/features/discovery/discovery_page.dart`
- Modify: `lib/features/video/playback/video_match_detail_page.dart`
- Test: `test/features/discovery/discovery_page_test.dart`
- Test: `test/features/video/playback/video_match_detail_page_test.dart`

**Approach:**
- Discovery: replace the `initState` post-frame `startScan` (`:25-29`) with a
  `ref.listen`-driven or lifecycle-correct trigger that can't race the provider subscription.
- Video detail: replace the in-`build()` `_startPlayer()` behind a bool guard (`:177-190`)
  with a `ref.listen(isOnDeviceProvider, …)` effect that starts playback on transition.

**Patterns to follow:**
- `lib/features/camera/raw_capture_state.dart:55-69` (uses `ref.listen` for a connection effect).

**Test scenarios:**
- Happy path: opening discovery starts a scan exactly once and results appear without re-entry.
- Edge case: scan-start does not race the first subscription (no dropped first emission).
- Happy path: video detail starts the player when `isOnDevice` flips true, exactly once.

**Verification:**
- Discovery shows results on first open; player starts reliably without the blank-surface beat.

---

### U10. Stop `loading→[]` / `error→[]` collapse

**Goal:** Loading and DB errors are distinguishable from "empty list" in the video/match
library providers.

**Requirements:** R2

**Dependencies:** None

**Files:**
- Modify: `lib/features/video/video_state.dart`
- Modify: `lib/features/match/match_state.dart` (if it shares the collapse)
- Test: `test/features/video/video_state_test.dart`

**Approach:**
- In `filteredLibraryMatchesProvider` and the derived sport/team providers
  (`video_state.dart:162-201,204,217`), stop mapping `loading`/`error` to `const []`.
  Preserve `AsyncValue` so the UI can show loading and surface DB errors instead of
  rendering "no videos".

**Test scenarios:**
- Happy path: data state yields the filtered list.
- Edge case: loading state is not collapsed into an empty list (filter chips don't flash empty).
- Error path: a DB stream error surfaces as an error, not silently "no videos".

**Verification:**
- Library shows loading vs empty vs error distinctly; DB failures are visible.

---

### U11. Stream-contract test suite (mock vs real)

**Goal:** One suite asserting the shared stream contract, run against BOTH the mock and
real impls, so divergence fails CI.

**Requirements:** R5

**Dependencies:** U4, U5

**Files:**
- Create: `test/contract/stream_contract_test.dart`
- Create: `test/contract/ble_service_contract_test.dart`
- Create: `test/contract/wifi_service_contract_test.dart`

**Approach:**
- Parameterize a shared contract test over an impl factory, running it for both
  mock and real (real driven via the U12 fake transport where a transport is required;
  pure-stream assertions can run without it). Assert: replay-on-subscribe, stable
  controller identity across connect, autoDispose teardown behavior, no first-emission drop.

**Patterns to follow:**
- Existing service tests under `test/ble/`, `test/wifi/`; parameterized `group` over impls.

**Test scenarios:**
- Contract: late subscriber receives current value for connection/telemetry/match/wifi/discovery.
- Contract: pre-connect subscriber receives post-connect transitions.
- Contract: same assertions pass for mock AND real — a divergence (e.g. removing replay)
  turns the real-impl run red.
- Covers R5: the suite fails if real-impl replay semantics regress.

**Verification:**
- The suite passes for both impls; deliberately reverting a U4 replay change makes the
  real-impl run fail.

---

### U12. Fake-transport seam (fake GATT + fake P2P)

**Goal:** A test seam that lets the REAL `BleServiceImpl`/`WifiServiceImpl` run against a
fake GATT characteristic (declared properties) and fake P2P/EventChannel.

**Requirements:** R6

**Dependencies:** None (placement decision per Open Questions)

**Files:**
- Create: `test/fakes/transport/fake_gatt_characteristic.dart`
- Create: `test/fakes/transport/fake_ble_peripheral.dart`
- Create: `test/fakes/transport/fake_p2p_channel.dart`
- Create: `test/fakes/transport/README.md` (placement note + emulator-strategy link)

**Approach:**
- Model a fake characteristic carrying declared `properties` (command =
  `write-without-response` only; response = `notify`) that rejects a write whose mode
  contradicts its declared properties — the behavior that makes GAP1 catchable. Model a
  minimal fake P2P channel/EventChannel for WiFi connect-state transitions and role.
- Drive the real impls' actual `_writeFrames` / `_startResponseListener` /
  `_connectGroupInternal` against these fakes. Keep transport-realism knobs minimal (only
  what U13 asserts); broader knobs are Deferred to Follow-Up Work.
- Resolve placement (in-app `test/fakes/` vs `sst-cam-emulator`) at unit start; default
  in-app for CI proximity, coordinate with the emulator build-variant strategy.

**Patterns to follow:**
- `lib/core/ble/ble_protocol.dart` framing; `test/ble/chunk_mtu_test.dart` for frame-level setup.
- Firmware GATT flags as the contract source:
  `../sst-cam-firmware/src/adapters/control/ble/bluez/gatt-application.cpp:77-78,111-113`.

**Test scenarios:**
- Unit: fake characteristic accepts a `withoutResponse: true` write and rejects a
  `withoutResponse: false` write when declared `write-without-response`-only.
- Unit: fake P2P channel emits a `starting→connected` sequence and a `starting→failed` sequence.

**Verification:**
- The real impls can be constructed and exercised against the fakes in a unit test without
  hardware or platform channels.

---

### U13. Real-impl-on-fake-transport tests (GAP1 + transport class)

**Goal:** Turn the write-mode bug class (and adjacent transport gaps the seam now reaches)
into failing-then-passing tests.

**Requirements:** R6

**Dependencies:** U2, U11, U12

**Files:**
- Create: `test/transport/ble_real_impl_transport_test.dart`
- Create: `test/transport/wifi_real_impl_transport_test.dart`

**Approach:**
- Using U12 fakes, assert the real `BleServiceImpl` connect handshake succeeds only with
  `withoutResponse: true` (GAP1) — a test that would have failed against the pre-U2 code.
- Add focused tests for the transport behaviors the seam now exposes that are cheap to
  cover here (e.g. multi-chunk reassembly through the real listener, WiFi role-mismatch /
  connect-failure surfacing). Exhaustive GAP5/6/7/10/12 coverage stays in Follow-Up.

**Test scenarios:**
- Covers R6: connect through the fake GATT succeeds with command writes in
  `write-without-response` mode and fails if the impl regresses to write-with-response.
- Integration: a multi-chunk response reassembles correctly through the real
  `_startResponseListener`.
- Error path: WiFi connect against a non-GO role / failed P2P surfaces `WifiDirectException`.

**Verification:**
- The GAP1 regression test fails on pre-U2 code and passes after; transport tests run in CI
  without hardware.

---

## System-Wide Impact

- **Interaction graph:** Class A/U6 changes touch every widget reading connection,
  telemetry, match, wifi, and discovery providers (main_page, discovery_page,
  session_screen, live_preview_view, settings, setup_screen). Verify each still renders.
- **Error propagation:** U3 surfaces impl exceptions to UI; U10 surfaces DB errors instead
  of swallowing to `[]`. Ensure error states are handled, not just shown.
- **State lifecycle risks:** U6 autoDispose must not tear down providers that legitimately
  outlive a page (active-camera identity, wifi handoff controller at app_shell root) —
  audit before converting.
- **API surface parity:** The seeded-broadcast primitive should be applied to ALL Class A
  streams, not a subset, or divergence persists (U11 enforces this).
- **Integration coverage:** U11/U13 are exactly the cross-layer coverage unit tests alone
  missed — keep them green in CI.
- **Unchanged invariants:** `BleService`/`WifiService` port interfaces stay the same (only
  impl/stream semantics change); firmware contract unchanged (GAP1 fixed app-side).

---

## Risks & Dependencies

| Risk | Mitigation |
|------|------------|
| Converting providers to autoDispose tears down ones that must persist | U6 audits each; persist active-camera/handoff deliberately with a documented reason |
| `withoutResponse: true` removes ATT confirmation the multi-frame loop relied on | ChunkAck notify is the real flow-control and is already awaited; U2/U13 test multi-frame gating |
| Seeded-broadcast applied unevenly re-introduces divergence | Single `core/async` primitive + U11 contract suite over all Class A streams |
| Fake-transport placement churn (app vs emulator repo) | Decide at U12 start; default in-app for CI, coordinate emulator strategy before committing |
| Layer 0 regressions block hardware testing | Layer 0 is its own `fix/*` branch, shippable and verifiable on device before Layers 1–2 |

---

## Documentation / Operational Notes

- After Layer 2, capture a `docs/solutions/` learning: "mocks above the port hide
  transport-class bugs; use a seeded-broadcast primitive + contract tests run against both
  impls + a fake-transport seam." Strong compounding candidate.
- Keep `docs/firmware-spec.md` in sync if any app↔firmware expectation shifts (none expected
  here — GAP1 is app-side adaptation to the existing contract).

---

## Phased Delivery

### Phase 1 — Layer 0 (own `fix/*` branch, ship first) — U1, U2, U3, U4, U5
Unblocks hardware: icon, connect, error visibility, and the Class A stream-identity fixes
that make connect actually reach the UI. Verifiable on device independently (R7).

### Phase 2 — Layer 1 (follow-up branch) — U6, U7, U8, U9, U10
Provider lifecycle + flash/leak removal. Builds on Class A.

### Phase 3 — Layer 2 (follow-up branch) — U11, U12, U13
Contract tests + fake-transport seam. Makes the divergence structurally impossible and
catches the transport class in CI.

---

## Sources & References

- **Origin document:** [docs/brainstorms/2026-06-26-hardware-bringup-race-class-requirements.md](docs/brainstorms/2026-06-26-hardware-bringup-race-class-requirements.md)
- Seed pattern: `lib/features/settings/streaming/streaming_state.dart:30-55`
- Real impls: `lib/core/ble/ble_service_impl.dart`, `lib/core/wifi/wifi_service_impl.dart`
- Mock replay idioms: `lib/mock/emulator/mock_ble_service.dart:436-441`, `mock_wifi_service.dart:188-202`
- Firmware contract: `../sst-cam-firmware/src/adapters/control/ble/bluez/gatt-application.cpp:77-78`
- Separate firmware track: `../../../sst-cam-firmware/docs/brainstorms/2026-06-26-device-id-provisioning-requirements.md`
