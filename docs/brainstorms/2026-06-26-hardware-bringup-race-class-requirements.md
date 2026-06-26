# Hardware Bring-Up: Mock-Fidelity Race-Bug Class — Requirements

**Date:** 2026-06-26
**Status:** Ready for planning
**Repo:** sst-cam-app
**Scope:** Standard→Deep (cross-cutting; app-only)

## Problem

First install of the latest app + firmware on real hardware surfaced four user-visible
bugs. Investigation showed they are **not four bugs but four symptoms of one root cause**:
the app was built contract-first against mock/emulator backends that implement the
`BleService`/`WifiService` **ports** and replace the entire transport. The mocks are
**forgiving exactly where real BLE/WiFi is not** — they replay current stream values on
subscribe, never exercise GATT write modes / MTU / ChunkAck flow control / P2P
negotiation, and never fail mid-flight. So a whole class of defect passes emulation and
only appears on hardware.

`grep autoDispose lib/` returns **zero hits** — every stream/future provider lives for
the app's lifetime, which both leaks and masks the races intermittently (stale cached
values).

## Evidence (observed on real hardware)

- Prod launcher icon renders black background, only the red dot visible.
- "Connect Camera" page shows no devices until 2nd/3rd entry + Scan; a screen flashes
  for a split second.
- Connect to a device → off-brand "Connection failed — retry?" card with no error text;
  connect actually fails.
- Could not test anything else — connect is the blocker.

## Root causes (all confirmed from code)

### Class A — stream identity / replay divergence (mock replays, real hands out throwaway)
| Stream | Real-impl defect | Hardware symptom | Sev |
|---|---|---|---|
| `connectionStateStream` | `Stream.value(disconnected)` when device not yet in `_connected`; `connect()` creates a *new* controller the provider never re-subscribes to (`lib/core/ble/ble_service_impl.dart:218-221`, controller born at `:124-128`) | connect "succeeds" but every widget reading connection state stays `disconnected` forever | critical |
| `telemetryStream` | `?? Stream.empty()` if watched pre-connect; poll starts as a subscribe side-effect (`lib/core/ble/ble_service_impl.dart:228-235`) | telemetry never appears | high |
| `matchStateStream` | same shape (`lib/core/ble/ble_service_impl.dart:265-272`) | score/clock never update | high |
| wifi `connectionStateStream` | raw broadcast, no replay (`lib/core/wifi/wifi_service_impl.dart:227`); mock has an explicit `Stream.multi` fix the real lacks (`lib/mock/emulator/mock_wifi_service.dart:188-202`) | preview badge stuck; `LivePreviewView` is a deliberate late subscriber (`lib/core/widgets/live_preview_view.dart:189`) | high |
| `discoveredDevices` | raw broadcast, no replay (`lib/core/ble/ble_service_impl.dart:48`); `startScan()` clears + emits `[]` re-racing appear-timers | scan results race | high |

### Class B — provider lifecycle (no autoDispose anywhere)
- Live-preview first-frame drop + stale-frame flash (`lib/core/widgets/live_preview_view.dart:188-217`).
- Match 1 Hz timer created in `initState`, runs 24/7 inside IndexedStack, no cancel-before-create guard (`lib/features/match/match_page.dart:38-49`).
- main_page telemetry "—" flash + first-tick drop (`lib/features/camera/main_page.dart:30-40`).
- Session controls greyed for a frame; very-fast tap dropped (`lib/features/match/session/session_screen.dart:38-59,1320-1326`).
- Player started as a side-effect inside `build()` (`lib/features/video/playback/video_match_detail_page.dart:177-190`).
- `loading→[]` / `error→[]` collapse hides DB errors + flashes filter chips (`lib/features/video/video_state.dart:162-201`).
- **In-repo correct template:** `lib/features/settings/streaming/streaming_state.dart:38-49` — AsyncNotifier seeds via `await get…()`, watches the Drift stream, `ref.onDispose(sub.cancel)`. No first-emission drop.

### Class C — mock is transport-blind (12 gaps; bug 3a is canonical)
- GAP1 command-write mode: firmware command char declares only `write-without-response` (`/home/rs/Documents/sst/sst-cam-firmware/src/adapters/control/ble/bluez/gatt-application.cpp:77-78`); app writes commands with `withoutResponse: false` (`lib/core/ble/ble_service_impl.dart:483,489`) → first `GetDeviceInfo` handshake write rejected → connect throws. (ACK already uses `withoutResponse: true` at `:578`.)
- GAP2 ChunkAck flow-control / reassembly never exercised (mock single-chunks everything).
- GAP3 MTU never negotiated; GAP4 handshake short-circuited; GAP6 disconnect-mid-command; GAP7 timeouts unreachable; GAP8 WiFi P2P handoff faked (mock invents creds, skips BLE→WiFi handoff + role check + native channel); GAP10 download HTTP 401/410/Range/absent-Content-Length; GAP11 telemetry is push-in-mock vs poll-in-real.
- Root: mocks stand in *above* the port, so transport-layer bugs are invisible until hardware.

### Icon (bug 1, confirmed)
- Prod foreground `launcher/icon-prod-foreground.png` = black "SC" on transparent; `flutter_launcher_icons-prod.yaml` sets `adaptive_icon_background: "#0A0A0A"` → black-on-black, only red dot survives. Legacy prod icon `launcher/icon-prod-1024.png` is yellow `#E8FF3C` = intended bg. CI auto-generates `src/prod/res` via bare `dart run flutter_launcher_icons` (`.github/workflows/release-beta.yml:299`).

## Decision: full prevention ladder

Chosen scope = **L0 + L1 + contract tests + fake-transport seam** (device-id is a
separate firmware track, see `../../../sst-cam-firmware/docs/brainstorms/2026-06-26-device-id-provisioning-requirements.md`).

### Layer 0 — Unblock (non-negotiable)
- Bug 1: `flutter_launcher_icons-prod.yaml` → `adaptive_icon_background: "#E8FF3C"`.
- Bug 3a (GAP1): command-frame writes → `withoutResponse: true` (contract-consistent; firmware ChunkAck notify is the real confirmation channel).
- Bug 3b: connect error card binds the caught exception, renders its `.message`, and uses the design system (`WfCard`/`WfButton`/tokens) instead of a bare `SnackBar`; add a real Retry action. Add `snackBarTheme` to `lib/app.dart` so stray SnackBars are on-brand too.
- Class A stream-identity fixes: connection/telemetry/match/wifi/discovery real impls must replay current value on subscribe and keep stable per-device controller identity across the connect lifecycle (lazy `putIfAbsent`-style controller seeded with current state; `connect()` reuses it). Without this, connect still *looks* broken after the write fix.

### Layer 1 — Lifecycle (Class B)
- Make live device providers `autoDispose` and seed-then-subscribe (copy the `streaming_state.dart` AsyncNotifier template); tear down on disconnect/navigation; no stale cached frames.
- Replace `.valueOrNull ?? default` rendering with explicit loading states (`.when` / `AsyncValue.unwrapPrevious`) on main_page, live_preview_view, session_screen so flashes stop.
- Bind the match timer to "match is live" (state transition / `ref.listen`), with cancel-before-create.
- Move `build()`-time side-effects (player start, scan start) to `ref.listen`-driven effects that fire on the transition.
- Stop the `loading→[]` / `error→[]` collapse from hiding DB errors.

### Layer 2 — Make divergence structurally impossible
- **Contract tests:** one suite run against BOTH mock and real impls asserting the shared stream contract — replay-on-subscribe, stable controller identity, autoDispose teardown. Divergence becomes red CI, not a hardware surprise.
- **Fake-transport seam:** a fake GATT characteristic (carrying declared `write-without-response`/`notify` properties) + a fake P2P/EventChannel, with the **real** `BleServiceImpl`/`WifiServiceImpl` logic running against it. This is the only thing that catches GAP1/2/3/8/12 — the write-mode bug becomes a failing unit test. Aligns with the `sst-cam-emulator` build-variant strategy.

## Success criteria
- App connects to real firmware and reaches `connected` end-to-end; telemetry, match
  state, discovery, and WiFi preview state all render without re-entry/Scan dances.
- No flash of empty/loading/stale state on connect, discovery, preview, or session entry.
- Prod launcher icon renders correctly (yellow bg + SC + red dot).
- Connect failures show the real, actionable error message in an on-brand card with Retry.
- A contract-test suite fails CI if mock and real stream semantics diverge.
- The fake-transport seam reproduces the write-mode class of bug as a failing test
  (i.e. GAP1 would have been caught pre-hardware).

## Non-goals / out of scope
- Device-id provisioning (separate firmware track).
- Implementing real preview frames/stats streams (intentionally VLC-side today; GAP6/7).
- Overlay-state real data (both impls are stubs today).

## Open questions for planning
- Where the shared stream-contract helper lives (core/ble + core/wifi shared util vs a
  small `core/async` primitive) and whether to adopt a BehaviorSubject-style dependency
  or hand-roll `Stream.multi`+seed.
- Whether the fake-transport seam is a new build variant in this repo or lands in
  `sst-cam-emulator`; coordinate with the emulator strategy.
- Sequencing: Layer 0 should land first on its own `fix/*` branch to unblock hardware
  testing before the larger Layer 1/2 work.

## Dependencies / assumptions
- Firmware command char stays `write-without-response` only; app adapts (no firmware
  rebuild needed for Layer 0).
- `release/0.1.0` is the current base in sst-cam-app; fixes land on `fix/*` branches per
  the repo branch model.
