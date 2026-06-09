---
title: "feat: Overlay pixel-parity and WiFi Direct dynamic credentials"
type: feat
status: completed
date: 2026-06-08
origin_a: docs/brainstorms/2026-06-08-overlay-pixel-parity-app-requirements.md
origin_b: docs/brainstorms/2026-06-08-wifi-direct-dynamic-credentials-app-requirements.md
cross_repo_a: docs/cross-repo/firmware/inbound/2026-06-08-overlay-pixel-parity-contract.md
cross_repo_b: docs/cross-repo/firmware/inbound/2026-06-08-wifi-direct-dynamic-credentials.md
---

# feat: Overlay pixel-parity and WiFi Direct dynamic credentials

## Summary

Two parallel feature tracks fulfilling firmware co-development contracts. **Track A** fixes the Flutter overlay renderer to be pixel-accurate against the camera's Cairo/Pango compositor: bundle Inter Regular + Bold as font assets, switch to uniform `min(sx, sy)` canvas scaling, add `{{param}}` banner substitution, and tighten the `OverlayStyle.fontFamily` type to `String?`. **Track B** replaces the `WifiServiceImpl.connectGroup` stub with a real BLE credential handshake and an Android `WifiP2pManager` platform channel, while guarding iOS with a graceful placeholder. The two tracks share no runtime dependencies and can land in any order.

---

## Problem Frame

The Flutter preview diverges visually from the camera's recorded output (different fonts, non-uniform element scaling, no player-name substitution in banners). The WiFi Direct implementation is a compile-time stub that returns hardcoded mock credentials — real hardware will never connect. Both are contract gaps agreed with the firmware team and documented in the cross-repo response files above.

---

## Requirements

- R1. Inter Regular and Inter Bold are bundled as Flutter font assets; the same TTF files are shared with firmware for Cairo/Pango. *(origin_a §1)*
- R2. `OverlayStyle.fontFamily` is `String?`; null/absent means Inter; a non-empty value names a specific bundled font. *(origin_a §5)*
- R3. The overlay renderer uses uniform `min(sx, sy)` canvas-to-surface scaling so element proportions match firmware. *(origin_a §3)*
- R4. The renderer substitutes `{{param_name}}` tokens in banner `staticText` using `BannerEventCommand.params`. *(origin_a §4)*
- R5. `defaultScoreboardLayout()` sets `fontFamily: 'Inter'` explicitly so the factory produces a fully-specified layout. *(origin_a §2, §5)*
- R6. `WifiServiceImpl.connectGroup` performs a BLE round-trip (`StartWifiDirectCommand` → `WifiDirectGroupResponse`) to obtain dynamic credentials; no compile-time SSID or passphrase. *(origin_b Q1)*
- R7. `WifiHandoffController` fires `connectGroup` automatically on `CameraConnectionState.connected`; no user action needed. *(origin_b Q2 — already implemented; this plan preserves it)*
- R8. On Android, the app joins the P2P group using `WifiP2pManager` with the firmware-delivered credentials. *(origin_b Q3)*
- R9. On iOS, `connectGroup` returns a graceful `WifiDirectException("local preview not supported on iOS")`; the session screen shows a clear placeholder instead of a spinner or crash. *(origin_b Q3)*
- R10. `MockWifiService.connectGroup` delivers dynamic-looking credentials sourced from mock config, not a hardcoded string constant. *(origin_b acceptance criteria)*

---

## Scope Boundaries

- iOS soft-AP mode, `NEHotspotConfiguration`, or Multipeer Connectivity are not implemented.
- Player data (`params` population in `EventSheet`) is not addressed here — wiring `params` to event dispatch is residual finding #21; this plan only makes the renderer capable of consuming them.
- Android 16 / API 36 CI matrix is not added by this plan; the risk is noted and a manual validation step is required before merging Track B.
- No changes to the BLE protocol spec or proto files — `StartWifiDirectCommand` and `WifiDirectGroupResponse` already exist in `proto/bluetooth.proto`.

### Deferred to Follow-Up Work

- iOS WiFi Direct (soft-AP track): new firmware cross-repo request when prioritised.
- `EventSheet` player-data collection and `BannerEventCommand.params` population: separate unit.
- Overlay rendering semantics appendix in the proto repo: requires firmware confirmation of Inter fallback behaviour first.

---

## Context & Research

### Relevant Code and Patterns

- Font asset declaration follows the Flutter `pubspec.yaml` `fonts:` block convention — no existing `fonts:` section; must be added.
- `lib/core/models/overlay_layout.dart` — `OverlayStyle`, `OverlayElement`, `OverlayLayout`, `defaultScoreboardLayout()`
- `lib/features/match/session/overlay_renderer.dart` — `OverlayLayoutRenderer`, `_buildPositioned`, `_buildElement`, `_resolveBinding`, `_labelToTemplateId`
- `lib/features/match/session/session_state.dart` — `LiveMatchState`, `LiveEvent`
- `lib/core/models/command.dart` — sealed `BleCommand` hierarchy; U4/U5 atomicity rule: adding a new command subclass requires updating `BleProtocol` and `MockBleService` exhaustive switches in the same commit
- `lib/core/ble/ble_protocol.dart` — exhaustive switch over all `BleCommand` subtypes
- `lib/mock/emulator/mock_ble_service.dart` — exhaustive switch over all `BleCommand` subtypes
- `lib/core/wifi/wifi_service.dart` — abstract `WifiService`; `connectGroup(String deviceId)` signature must remain unchanged
- `lib/core/wifi/wifi_service_impl.dart` — stub `connectGroup` returning hardcoded mock
- `lib/core/wifi/wifi_handoff.dart` — `WifiHandoffController` Notifier; auto-fires `wifi.connectGroup(id)` on BLE connected
- `lib/core/wifi/wifi_providers.dart` — `wifiServiceProvider`, `wifiConnectionStateProvider`, `previewDescriptorProvider`
- `lib/core/services/backup_service.dart` — precedent for injecting `BleService` via constructor (`BackupService(this._db, {BleService? ble})`)
- `android/app/src/main/kotlin/com/sst/sstcam/MainActivity.kt` — existing `com.sst.sstcam/media` MethodChannel; naming convention for new `com.sst.sstcam/wifi` channel
- `lib/core/services/gallery_service.dart` — `Platform.isAndroid` guard pattern used in Dart layer
- `lib/mock/emulator/mock_wifi_service.dart` — `_GroupState` per-device map, `pairingDelay`, hardcoded credentials

### Institutional Learnings

- **Core must not import feature layer** (`docs/solutions/logic-errors/core-importing-feature-layer-inversion-2026-05-26.md`): `{{param}}` substitution logic lives in `overlay_renderer.dart` (feature layer), not in `overlay_layout.dart` (core model). `defaultScoreboardLayout()` accepts only plain strings.
- **Android 16 plugin registration abort** (`docs/solutions/integration-issues/ffmpegkit-android16-plugin-registration-abort-2026-05-27.md`): `WifiP2pManager.initialize` in `onAttachedToActivity` can throw `java.lang.Error`; if it does, every plugin registered after it in `GeneratedPluginRegistrant.java` silently breaks. Validate on Android 16 (API 36, x86_64) specifically; check ADB logcat, not Dart exceptions.
- **U4/U5 atomicity rule** (prior plan `docs/plans/2026-06-03-013-feat-overlay-layout-session-ble-wiring-plan.md`): every new `BleCommand` subclass addition must update `BleProtocol` and `MockBleService` exhaustive switches in the same commit.

### External References

- Inter font files: `github.com/rsms/inter/releases` (OFL 1.1 license — bundling permitted in firmware and app)
- Android `WifiP2pManager` API: developer.android.com/reference/android/net/wifi/p2p/WifiP2pManager (minimum API 14; P2P connect requires `CHANGE_WIFI_STATE` + `ACCESS_FINE_LOCATION` or `NEARBY_WIFI_DEVICES` on API 33+)

---

## Key Technical Decisions

- **One combined plan, two independent tracks**: Track A and Track B share no runtime dependencies. Either can land first. Sequence within each track is dependency-ordered; cross-track sequencing is unconstrained.
- **`BleService` injected into `WifiServiceImpl` via constructor**: matches the `BackupService` precedent, keeps `connectGroup(String deviceId)` on the abstract `WifiService` interface unchanged, and avoids requiring a `Ref` inside the implementation. `wifiServiceProvider` passes `ref.watch(bleServiceProvider)`.
- **`WifiDirectGroup` as the BLE response type**: `WifiDirectGroup` (in `wifi.dart`) already has the same fields as the firmware's `WifiDirectGroupResponse` proto message. `BleServiceImpl` maps the proto response to this existing model — no duplicate class in `command.dart`.
- **`{{param}}` via `LiveEvent.params`**: `params: Map<String, String>` is added to `LiveEvent` (defaults to `const {}`). The renderer captures `_activeBannerParams` from `events.first.params` alongside `_activeBannerTemplateId`. `_resolveBinding` accesses `_activeBannerParams` from renderer state to substitute tokens in `OverlayBinding.static` text. This keeps the renderer self-contained without changing its public constructor.
- **Android channel: MethodChannel + EventChannel**: `MethodChannel('com.sst.sstcam/wifi')` for imperative calls (connect, disconnect). `EventChannel('com.sst.sstcam/wifi/state')` for the Dart-facing `connectionStateStream` that replaces `const Stream.empty()`. The Kotlin handler is a separate `WifiDirectChannel` class registered in `MainActivity.configureFlutterEngine`, following the `com.sst.sstcam/<domain>` naming convention.
- **`OverlayStyle.fontFamily: String?`**: removes the empty-string sentinel; renderer checks `!= null` instead of `.isNotEmpty`. `OverlayStyle` constructor default becomes `this.fontFamily`. The `defaultScoreboardLayout()` factory sets `fontFamily: 'Inter'` explicitly on all text elements.
- **iOS guard in `WifiServiceImpl`, not `WifiHandoffController`**: `WifiHandoffController` is policy (when to connect); `WifiServiceImpl` is mechanism (how). The guard belongs in the mechanism layer so `MockWifiService` can also gate it correctly.

---

## High-Level Technical Design

> *This illustrates the intended approach and is directional guidance for review, not implementation specification. The implementing agent should treat it as context, not code to reproduce.*

### Track A — Overlay pixel-parity call chain (after changes)

```
OverlayLayoutRenderer.didUpdateWidget
  → events.first.params captured as _activeBannerParams
  → _activeBannerTemplateId set → Timer started

OverlayLayoutRenderer.build
  s = min(maxWidth/canvasWidth, maxHeight/canvasHeight)   ← uniform scale
  _buildPositioned(el, s)
    Positioned(left: el.x1*s, top: el.y1*s, width: (x2-x1)*s, height: (y2-y1)*s)
    _buildElement(el, s)
      TextStyle(fontSize: el.fontSize * s,
                fontFamily: el.fontFamily)               ← String? — null means system font
      _resolveBinding(el.binding, el.staticText)
        OverlayBinding.static → substitute {{key}} from _activeBannerParams
```

### Track B — WiFi Direct connect sequence (after changes)

```
CameraConnectionState.connected fires
  WifiHandoffController.build
    → wifi.connectGroup(deviceId)

WifiServiceImpl.connectGroup(deviceId)
  Platform.isIOS → throw WifiDirectException("local preview not supported on iOS")

  emit WifiDirectState.starting

  _ble.sendCommand<WifiDirectGroup>(deviceId, StartWifiDirectCommand())
    → BleCommandResponse<WifiDirectGroup>{isOk: true, payload: WifiDirectGroup{ssid,psk,...}}

  MethodChannel('com.sst.sstcam/wifi').invokeMethod('connect', {ssid, psk})
    [Kotlin] WifiP2pManager.connect(config, actionListener)
    [Kotlin] BroadcastReceiver(WIFI_P2P_CONNECTION_CHANGED_ACTION)
      → EventChannel emits WifiDirectState.connected + groupOwnerAddress

  emit WifiDirectState.connected
  return WifiDirectGroup{...}
```

---

## Implementation Units

### U1. Bundle Inter font assets

**Goal:** Make Inter Regular and Inter Bold available as bundled Flutter font assets so `TextStyle(fontFamily: 'Inter')` resolves the bundled TTF files on both Android and iOS.

**Requirements:** R1

**Dependencies:** None

**Files:**
- Create: `assets/fonts/Inter-Regular.ttf`
- Create: `assets/fonts/Inter-Bold.ttf`
- Modify: `pubspec.yaml` (add `fonts:` block under `flutter:`)

**Approach:**
- Download Inter v4 (or the version agreed with firmware) from the official Inter release. Use the static TTF variants (`Inter-Regular.ttf`, `Inter-Bold.ttf`), not the variable font.
- Place files under `assets/fonts/` (directory must be created).
- Add to `pubspec.yaml` under `flutter:`:
  ```yaml
  fonts:
    - family: Inter
      fonts:
        - asset: assets/fonts/Inter-Regular.ttf
        - asset: assets/fonts/Inter-Bold.ttf
          weight: 700
  ```
- Confirm `flutter pub get` resolves the new assets without error.
- Ship the same two TTF files to the firmware team so Cairo/Pango uses identical binary glyph data.

**Patterns to follow:**
- Existing `assets:` block in `pubspec.yaml` under `flutter:` for structure reference.

**Test scenarios:**
- Test expectation: none — font asset declaration is a build-time configuration. Correctness is verified visually (screenshot comparison) and by U3's `TextStyle.fontFamily` assertion test.

**Verification:**
- `flutter pub get` succeeds with no font-asset warnings.
- `flutter build apk --debug` includes the TTF files in `flutter_assets/fonts/`.
- `find assets/fonts -name "*.ttf"` returns both files.

---

### U2. Update OverlayStyle model and OverlayLayout factory

**Goal:** Change `OverlayStyle.fontFamily` from `String` (empty-string sentinel) to `String?` (nullable); update `defaultScoreboardLayout()` to set `fontFamily: 'Inter'` on all text-shape elements; add `params: Map<String, String>` to `LiveEvent` for banner substitution wiring; fix the two proto serialization helpers that assign `fontFamily` directly.

**Requirements:** R2, R4, R5

**Dependencies:** U1 (font assets must exist before specifying 'Inter' is meaningful, though this unit compiles independently)

**Files:**
- Modify: `lib/core/models/overlay_layout.dart`
- Modify: `lib/features/match/session/session_state.dart`
- Modify: `lib/core/ble/ble_protocol.dart` (null-safe `fontFamily` in `_dartElementToProto`)
- Modify: `lib/mock/emulator/mock_ble_service.dart` (null-safe `fontFamily` in `_dartElementToProto`)
- Test: `test/features/match/session/overlay_renderer_test.dart` (update construction calls that use `fontFamily: ''`)

**Approach:**
- In `OverlayStyle`: change `final String fontFamily` with default `= ''` to `final String? fontFamily` with no default (or `= null`). Update the constructor named parameter accordingly.
- In `defaultScoreboardLayout()`: add `fontFamily: 'Inter'` to **all 13 text-shape `OverlayStyle` instances** — 5 persistent text elements (home_name, away_name, score, period, clock) and 8 banner template text elements (goal_text, ycard_text, rcard_text, sub_text in all four templates). The 4 rect/circle elements are not text and do not need `fontFamily`.
- In both `BleProtocol._dartElementToProto` and `MockBleService._dartElementToProto`: change `fontFamily: el.style.fontFamily` to `fontFamily: el.style.fontFamily ?? ''` — the proto `font_family` field is non-nullable `string`, so a null Dart value must be coerced to empty string before serialization. Without this fix the code will not compile after `fontFamily` becomes `String?`.
- In `LiveEvent`: add `final Map<String, String> params` with a default of `const {}`. Ensure existing `LiveEvent` construction sites pass no argument (the default covers them).
- Confirm no `lib/core/` file imports anything from `lib/features/` — the model must stay import-clean.

**Patterns to follow:**
- `OverlayStyle` immutability convention — `@immutable`, all fields `final`.
- `LiveEvent` existing field style in `lib/features/match/session/session_state.dart`.
- `copyWith` null-preservation if `OverlayStyle` has a `copyWith`; use the sentinel-object pattern if needed for nullable fields (currently `OverlayStyle` has no `copyWith` — do not add one).

**Test scenarios:**
- Happy path: `OverlayStyle()` with no `fontFamily` argument → `fontFamily == null`.
- Happy path: `OverlayStyle(fontFamily: 'Inter')` → `fontFamily == 'Inter'`.
- Happy path: `defaultScoreboardLayout()` — all 13 text-shape elements have `fontFamily == 'Inter'`; all 4 rect/circle elements have `fontFamily == null`.
- Happy path: `LiveEvent(label: 'Goal · 45\'')` with no `params` argument → `params == {}`.
- Happy path: `LiveEvent(label: 'Goal · 45\'', params: {'player': 'Messi'})` → `params['player'] == 'Messi'`.
- Regression: all 11 existing `overlay_renderer_test.dart` tests still pass with updated `OverlayStyle` and `LiveEvent` construction.

**Verification:**
- `flutter analyze` produces no errors in `overlay_layout.dart` or `session_state.dart`.
- All 11 existing renderer tests pass.

---

### U3. Fix overlay renderer — uniform scale, null-safe font, param substitution

**Goal:** Fix three rendering bugs in `OverlayLayoutRenderer`: replace separate `sx`/`sy` with uniform `min(sx, sy)`, use null-safe `OverlayStyle.fontFamily` lookup, and substitute `{{param_name}}` tokens in banner static text from `_activeBannerParams`.

**Requirements:** R3, R4

**Dependencies:** U2

**Files:**
- Modify: `lib/features/match/session/overlay_renderer.dart`

**Approach:**
- **Uniform scale**: In `build()`, replace the two-variable computation with `final s = math.min(constraints.maxWidth / widget.layout.canvasWidth, constraints.maxHeight / widget.layout.canvasHeight)`. Pass `s` instead of `(sx, sy)` to `_buildPositioned` and `_buildElement`. Update both method signatures. All coordinate multiplications (`el.bounds.x1 * s`, etc.) use the single scalar.
- **Null-safe font**: In `_buildElement` for `OverlayShape.text`, replace the `.isNotEmpty` check with `el.style.fontFamily` directly (it is now `String?`; passing `null` to `TextStyle.fontFamily` retains the current system-font behaviour).
- **`_activeBannerParams` state**: Add `Map<String, String> _activeBannerParams = const {}` field. In `didUpdateWidget`, when a new banner fires, set `_activeBannerParams = events.first.params` alongside setting `_activeBannerTemplateId`. In the shrink/reset guard, use `setState(() { _activeBannerTemplateId = null; _activeBannerParams = const {}; })` — both fields must be cleared inside `setState` so the widget rebuilds; clearing them without `setState` will leave substituted text visible after a reset.
- **`{{param}}` substitution**: In `_resolveBinding`, for the `OverlayBinding.static` case, after retrieving `staticText`, replace all `{{key}}` tokens using `_activeBannerParams`. If a key is missing, replace with an empty string (not the literal `{{key}}`).
- Keep `_buildPositioned` and `_buildElement` signatures internal; no public API changes.

**Patterns to follow:**
- `dart:math` `min` — import at top of file.
- Existing `_activeBannerTemplateId` state + `didUpdateWidget` pattern for `_activeBannerParams`.
- `_resolveBinding` pattern: return a `String`, no side effects.

**Test scenarios:**
- Happy path — uniform scale: pump renderer in a `SizedBox(400, 200)` (2:1 aspect) with a 1920×1080 canvas; compute expected `s = min(400/1920, 200/1080) ≈ 0.185`; inspect `tester.widget<Positioned>(find.byType(Positioned).first).left` and verify it equals `el.bounds.x1 * s` (not `el.bounds.x1 * (400/1920)`). Do NOT use `tester.getTopLeft` — that reads screen geometry after layout, not the Positioned parameter values.
- Happy path — font family applied: pump a text element with `OverlayStyle(fontFamily: 'Inter', ...)`; inspect `tester.widget<Text>(find.byType(Text)).style?.fontFamily == 'Inter'`.
- Happy path — null font family: pump a text element with `fontFamily: null`; `TextStyle.fontFamily == null`.
- Happy path — param substitution: create a banner template with `staticText: 'GOAL — {{player}}'`; fire an event with `params: {'player': 'Messi'}`; pump → find `'GOAL — Messi'`.
- Edge case — missing param key: banner static text `'GOAL — {{scorer}}'`; `params: {}`; → rendered text is `'GOAL — '` (key replaced with empty string).
- Edge case — no active params after timer expiry: banner shows substituted text during `durationMs`; after pump past duration, banner is gone (existing timer test extended with param check).
- Edge case — event list shrink (reset): fire a banner event, then set events to `[]`; `_activeBannerParams` is cleared, banner is hidden.
- Regression: all 11 existing overlay renderer tests still pass.

**Verification:**
- `flutter test test/features/match/session/overlay_renderer_test.dart` — all tests pass including new ones.
- `flutter analyze` — zero issues in `overlay_renderer.dart`.

---

### U4. Overlay renderer tests

**Goal:** Add widget tests for the three new renderer behaviours (uniform scale, Inter font family, `{{param}}` substitution) to `overlay_renderer_test.dart`.

**Requirements:** R1, R2, R3, R4

**Dependencies:** U2, U3

**Files:**
- Modify: `test/features/match/session/overlay_renderer_test.dart`

**Approach:**
- Follow the existing `_wrap(child)` helper (`MaterialApp > Scaffold > SizedBox(400×200)`) and `testWidgets` pattern; no `ProviderScope` needed.
- For uniform-scale test: use `tester.widget<Positioned>(find.byType(Positioned).first).left` and compare to `el.bounds.x1 * expectedS` using `closeTo` — do NOT use `tester.getTopLeft` which reads screen geometry not layout parameters.
- For font test: `tester.widget<Text>(find.text('...')).style?.fontFamily`.
- For param substitution: build a minimal `OverlayLayout` with a single-element banner template whose `staticText` is `'Hello {{name}}'`; fire a `LiveEvent` with `params: {'name': 'World'}`; advance one frame; find `'Hello World'`.
- For missing-param: same setup, `params: {}`; find `'Hello '`.
- Extend the existing banner-timer fakeAsync test to verify params are cleared post-dismissal.

**Patterns to follow:**
- Existing `overlay_renderer_test.dart` file structure, `_matchState()` / `_wrap()` helpers.

**Test scenarios:**
- (covered by U3 test scenarios above — this unit is the test file itself)

**Verification:**
- `flutter test test/features/match/session/overlay_renderer_test.dart` — all tests pass.
- Test count ≥ 17 (11 existing + 6 new).

---

### U5. Add StartWifiDirectCommand to sealed BleCommand hierarchy

**Goal:** Add `StartWifiDirectCommand` to `lib/core/models/command.dart` and update the two exhaustive switches in `BleProtocol` and `MockBleService` in the same commit (U4/U5 atomicity rule).

**Requirements:** R6

**Dependencies:** None (Track B entry point; independent of Track A)

**Files:**
- Modify: `lib/core/models/command.dart`
- Modify: `lib/core/ble/ble_protocol.dart`
- Modify: `lib/mock/emulator/mock_ble_service.dart`

**Approach:**
- Add `class StartWifiDirectCommand extends BleCommand {}` to `command.dart` (no fields — the firmware derives the group from the command alone).
- In `BleProtocol` — **two switch sites must be updated**:
  1. `_toProtoCommand` (encode path): add a case for `StartWifiDirectCommand` that sets the proto `Command.startWifiDirect` field (field 53 of the oneof).
  2. `_mapOkResponse` (decode path): add a case for `StartWifiDirectCommand()` that reads `resp.wifiDirectGroup` from the proto response and maps it to `WifiDirectGroup{ssid, psk, groupOwnerIp, previewPort, downloadPort, role}`. Omitting this case causes a non-exhaustive compile error (sealed class exhaustiveness) or a `MatchError` at runtime when the response arrives.
- In `MockBleService` — **three switch sites must be updated**:
  1. `_encodeCommand`: add a case for `StartWifiDirectCommand` (encode to proto for wire send in mock).
  2. `_buildResponse`: add a case for `StartWifiDirectCommand` that returns a `BleCommandResponse<WifiDirectGroup>.ok(WifiDirectGroup{ssid: 'DIRECT-mock-sst-cam', psk: 'dev-psk', groupOwnerIp: '192.168.49.1', previewPort: 8554, downloadPort: 8080, role: 'GO'})`. (Fixed mock creds — U8 makes `MockWifiService` dynamic; mock BLE creds are separate.)
  3. `_mapResponse`: add a case for `StartWifiDirectCommand()` that converts the proto `WifiDirectGroupResponse` back to `WifiDirectGroup`.
- Confirm `flutter analyze` reports no non-exhaustive switch warnings across all five sites.

**Execution note:** Implement all three files together and commit atomically.

**Patterns to follow:**
- Existing sealed BleCommand subclasses in `command.dart` (e.g., `GetDeviceInfoCommand`, `ListRecordingsCommand`).
- Existing `BleProtocol` switch case structure.
- Existing `MockBleService` switch handler pattern.

**Test scenarios:**
- Happy path: `MockBleService.sendCommand<WifiDirectGroup>(deviceId, StartWifiDirectCommand())` returns `BleCommandResponse` with `isOk == true` and non-null `WifiDirectGroup` payload.
- Regression: existing `mock_ble_service_test.dart` tests all pass (the exhaustive switch now has one more case; no existing test should break).

**Verification:**
- `flutter analyze` — zero non-exhaustive switch errors.
- `flutter test test/ble/mock_ble_service_test.dart` — all tests pass.

---

### U6. Implement WifiServiceImpl with BleService injection and BLE round-trip

**Goal:** Wire `WifiServiceImpl.connectGroup` to send `StartWifiDirectCommand` over BLE, receive `WifiDirectGroup` credentials, then invoke the Android platform channel to join the group. Inject `BleService` via constructor following the `BackupService` pattern.

**Requirements:** R6, R7, R8, R9

**Dependencies:** U5

**Files:**
- Modify: `lib/core/wifi/wifi_service_impl.dart`
- Modify: `lib/core/wifi/wifi_providers.dart`
- Create: `lib/core/wifi/wifi_p2p_channel.dart` (Dart-side platform channel wrapper)

**Approach:**
- Add `final BleService _ble` field (non-nullable) to `WifiServiceImpl`, injected via constructor: `WifiServiceImpl({required BleService ble}) : _ble = ble;`. Using non-nullable enforces that BLE is always available at construction time; a missing injection is a wiring bug that should fail loudly, not produce a null dereference mid-connection. (Contrast with `BackupService` where BLE is optional — here it is mandatory.)
- Update `wifiServiceProvider` to pass `bleServiceProvider`: `WifiServiceImpl(ble: ref.watch(bleServiceProvider))`.
- **iOS guard**: At the top of `connectGroup`, check `Platform.isIOS` and throw `WifiDirectException('local preview not supported on iOS')` immediately. Also emit `WifiDirectState.failed` on the state stream.
- **BLE round-trip** (Android path): Use `_ble.sendCommand<WifiDirectGroup>(deviceId, StartWifiDirectCommand())`. On `!response.isOk` or `payload == null`, throw `WifiDirectException('BLE credential fetch failed')`.
- **EventChannel sequencing**: Subscribe to `connectionStateStream(deviceId)` (the `EventChannel` stream) **before** invoking `WifiP2pChannel.connect(...)`. The subscription must be open before the Kotlin `BroadcastReceiver` fires its first state event; if `connect` is called first and the P2P negotiation completes synchronously, the `WifiDirectState.connected` event can arrive before the Dart sink is registered and will be dropped, leaving the provider stuck in `starting` forever.
- **Platform channel invocation**: Call `WifiP2pChannel.connect(ssid: group.ssid, psk: group.psk)`. Await success; on failure throw `WifiDirectException`.
- Update `connectionStateStream(deviceId)` to expose the `EventChannel('com.sst.sstcam/wifi/state')` stream, mapping integer state codes to `WifiDirectState` enum values.
- `WifiP2pChannel` (new file) wraps the `MethodChannel('com.sst.sstcam/wifi')` calls (`connect`, `disconnect`) and the `EventChannel('com.sst.sstcam/wifi/state')` stream. Keeps all channel string literals in one place.

**Patterns to follow:**
- `BackupService(this._db, {BleService? ble})` constructor pattern.
- `GalleryService` MethodChannel call pattern (`lib/core/services/gallery_service.dart`).
- `Platform.isAndroid` guard pattern from `gallery_service.dart`.

**Test scenarios:**
- Happy path: `WifiServiceImpl(ble: mockBle).connectGroup(deviceId)` on Android → `mockBle` receives `StartWifiDirectCommand`, returns `WifiDirectGroup{ssid:'X', psk:'Y', ...}` → `WifiP2pChannel.connect` called with `ssid:'X', psk:'Y'` → returns `WifiDirectGroup`.
- Error path: BLE command returns `isOk: false` → `WifiDirectException` thrown with BLE error message.
- Error path: BLE command returns `isOk: true` but `payload == null` → `WifiDirectException` thrown.
- Error path (iOS): `Platform.isIOS == true` → `WifiDirectException('local preview not supported on iOS')` thrown immediately, no BLE command sent.
- Integration: `wifiConnectionStateProvider(deviceId)` emits `WifiDirectState.starting` → `WifiDirectState.connected` as platform channel events fire.

**Verification:**
- `flutter analyze` — zero issues in new and modified files.
- Unit tests for `WifiServiceImpl` with injected mock BLE service pass (using `MockBleService` override).

---

### U7. Android native WifiP2pManager platform channel

**Goal:** Implement the Kotlin-side `com.sst.sstcam/wifi` MethodChannel and `com.sst.sstcam/wifi/state` EventChannel in `MainActivity.kt` so the Dart layer can initiate a P2P connection and receive state events.

**Requirements:** R8

**Dependencies:** U6

**Files:**
- Create: `android/app/src/main/kotlin/com/sst/sstcam/WifiDirectChannel.kt`
- Modify: `android/app/src/main/kotlin/com/sst/sstcam/MainActivity.kt`
- Modify: `android/app/src/main/AndroidManifest.xml` (permissions)
- Modify: `ios/Runner/AppDelegate.swift` (no-op channel registration to prevent `MissingPluginException`)

**Approach:**
- Create `WifiDirectChannel` implementing `MethodCallHandler` and `EventChannel.StreamHandler`.
- Register in `MainActivity.configureFlutterEngine` following the `com.sst.sstcam/media` channel pattern.
- **MethodChannel** (`com.sst.sstcam/wifi`): handle `connect(ssid, psk)` and `disconnect`. `connect` constructs a `WifiP2pConfig` using `WifiP2pConfig.Builder` (required on API 29+ — the direct constructor form is deprecated; use `.setNetworkName(ssid).setPassphrase(psk).build()`), then calls `WifiP2pManager.connect(channel, config, actionListener)`. `disconnect` calls `WifiP2pManager.removeGroup`. Success/failure delivered via `MethodChannel.Result`.
- **EventChannel** (`com.sst.sstcam/wifi/state`): register a `BroadcastReceiver` on `WIFI_P2P_CONNECTION_CHANGED_ACTION`. On each change, map `WifiP2pInfo` to an integer state code (0=idle, 1=starting, 2=connected, 3=failed, 4=stopping) and push to the event sink. Unregister the receiver and close the sink in `onCancel` / `onDetachedFromEngine` to prevent leaks.
- Initialize `WifiP2pManager` in `onAttachedToActivity` (not in the constructor). Wrap initialization in a try-catch for `Throwable` (not just `Exception`) to prevent the cascade-abort documented for Android 16. If init throws, post `WifiDirectState.failed` to the event sink and log — do not rethrow.
- **Permissions**: Add `CHANGE_WIFI_STATE`, `ACCESS_WIFI_STATE`, `ACCESS_FINE_LOCATION` to `AndroidManifest.xml`. On API 33+, `NEARBY_WIFI_DEVICES` replaces `ACCESS_FINE_LOCATION` for P2P; add both and handle runtime permission request from Dart before calling `connect`.
- **iOS `AppDelegate.swift`**: register a no-op `FlutterMethodChannel` for `com.sst.sstcam/wifi` that returns `FlutterMethodNotImplemented` for all calls. This prevents `MissingPluginException` if any code path on iOS reaches the channel before the iOS guard in `WifiServiceImpl.connectGroup` fires.

**Patterns to follow:**
- Existing `com.sst.sstcam/media` MethodChannel in `MainActivity.kt`.
- Try-catch-Throwable wrap (documented in FFmpegKit Android 16 fix).

**Test scenarios:**
- Test expectation: none for this unit — native Android unit testing is outside the Flutter test suite. Manual validation on Android 16 (API 36, x86_64) is the required verification step per the Android 16 risk. See Risks section.

**Verification:**
- `flutter build apk --debug` succeeds with no Kotlin compile errors.
- On a real Android device: BLE connect → WiFi Direct group negotiation completes → `wifiConnectionStateProvider` emits `connected` → RTSP URL `rtsp://192.168.49.1:<port>/preview` is reachable.
- ADB logcat shows no `Error` thrown during `WifiP2pManager.initialize`.

---

### U8. iOS session placeholder and MockWifiService dynamic credentials

**Goal:** Show a clear "local preview not available on iOS" state in the session screen when `WifiDirectState.failed` carries the iOS reason. Update `MockWifiService.connectGroup` to source credentials from a configurable mock parameter rather than a hardcoded constant.

**Requirements:** R9, R10

**Dependencies:** U6

**Files:**
- Modify: `lib/features/match/session/session_screen.dart`
- Modify: `lib/mock/emulator/mock_wifi_service.dart`

**Approach:**
- **Session screen iOS placeholder**: `WifiServiceImpl.connectGroup` already throws `WifiDirectException('local preview not supported on iOS')` on iOS (U6). `WifiHandoffController` calls this via `unawaited`; the exception is swallowed. The session screen must instead watch `wifiConnectionStateProvider(deviceId)`. When state is `WifiDirectState.failed`, inspect the failure reason if surfaced via the stream, OR check `Platform.isIOS` directly. **Do NOT rely on `Platform.isIOS` in widget tests** — Flutter widget tests on Linux always return false. Instead, drive the placeholder via the provider state: when `wifiConnectionStateProvider` emits `WifiDirectState.failed`, check a `wifiFailureReasonProvider` (or an error string on the stream) to distinguish iOS-platform failure from a connection error, and show the appropriate placeholder. The test overrides `wifiConnectionStateProvider` to `WifiDirectState.failed` with the platform-reason string and asserts the placeholder text is shown — no `Platform.isIOS` check needed in the widget or the test.
- **MockWifiService**: the `_GroupState` in `MockWifiService` currently hardcodes `ssid: 'DIRECT-mock-sst-cam'`. Change the constructor to accept optional `mockSsid` and `mockPsk` parameters with sensible defaults. This satisfies R10 (no compile-time credential constants in production paths) and makes tests parametric.

**Patterns to follow:**
- `ThumbPlaceholder` widget in `session_screen.dart`.
- Dark theme tokens (`T.ink2`, `T.surface2`, etc.) from `lib/core/theme/tokens.dart`.
- Provider-override pattern in widget tests (see existing `session_screen` tests).

**Test scenarios:**
- Happy path (iOS placeholder): override `wifiConnectionStateProvider` to emit `WifiDirectState.failed` (with iOS reason); verify placeholder text "Local preview not available on iOS" is visible; verify no `CircularProgressIndicator` present. Does NOT need `Platform.isIOS` — placeholder is driven by provider state, not a platform check in the widget.
- Happy path (non-iOS failed): override provider to `WifiDirectState.failed` with a generic error reason; verify a "preview unavailable" or error-state placeholder is shown (distinct from the iOS-specific copy).
- Happy path (Android connected): `WifiDirectState.connected` → `LivePreviewView` rendered (existing behaviour, regression check).
- Happy path (MockWifiService custom creds): construct `MockWifiService(mockSsid: 'TEST-NET', mockPsk: 'abc')`, call `connectGroup('any')`; verify returned `WifiDirectGroup.ssid == 'TEST-NET'`.
- Regression: existing integration tests using `MockWifiService` with no constructor arguments still pass (default mock credentials still work).

**Verification:**
- `flutter test` — all session screen widget tests pass including new iOS placeholder test.
- `flutter analyze` — zero issues.

---

## System-Wide Impact

- **Interaction graph**: `WifiHandoffController` calls `WifiServiceImpl.connectGroup`; adding BleService injection means a BLE command is now sent mid-WiFi-connect flow. Any consumer of `wifiConnectionStateProvider` will see a longer `starting` phase (BLE round-trip latency ~100ms + P2P negotiation ~1-3s).
- **Error propagation**: `WifiDirectException` thrown from `WifiServiceImpl.connectGroup` propagates up through `WifiHandoffController.build()` via the `unawaited` call — errors are silently swallowed unless `WifiHandoffController` catches and emits them. The state stream (via `WifiDirectState.failed`) is the reliable signal; the screen should watch `wifiConnectionStateProvider`, not catch exceptions directly.
- **State lifecycle risks**: The `BroadcastReceiver` in `WifiDirectChannel.kt` must be unregistered in `onDetachedFromEngine` / `onDetachedFromActivity` to prevent leaks. The EventChannel sink must be closed on `onCancel`.
- **API surface parity**: `WifiService.connectGroup(String deviceId)` signature is unchanged — `MockWifiService` and `WifiServiceImpl` both implement it. No downstream callers need updating.
- **Integration coverage**: The full connect flow (BLE cred fetch → platform join → state stream) cannot be verified by unit tests alone; the manual Android device check (U7 Verification) and a future integration test wiring `MockBleService` + `MockWifiService` in the same test harness are required.
- **Unchanged invariants**: `WifiHandoffController` auto-fires on `CameraConnectionState.connected` — timing behaviour is unchanged. The `WifiService` abstract interface is unchanged.

---

## Risks & Dependencies

| Risk | Mitigation |
|------|------------|
| Android 16 (API 36) plugin cascade abort: `WifiP2pManager.initialize` throws `Error` → breaks BLE + storage + all subsequent plugins | Wrap init in try-catch-Throwable per the FFmpegKit learnings doc. Validate on Android 16 x86_64 emulator (ADB logcat, not Dart) before merging Track B. |
| iOS `MissingPluginException` if any code path invokes `com.sst.sstcam/wifi` on iOS | Register a no-op channel in `AppDelegate.swift` returning `FlutterError("unsupported")` for all calls. |
| Firmware `font_family` absent/empty → camera uses a different fallback font → banner text differs | Open question to firmware: confirm empty `font_family` in proto also defaults to Inter. Acceptance test requires screenshot comparison against a real camera frame. |
| `WifiP2pManager` permissions — `NEARBY_WIFI_DEVICES` required on API 33+ but `ACCESS_FINE_LOCATION` still needed on API < 33 | Declare both in `AndroidManifest.xml`; add runtime permission request (using existing `permission_handler` package) before first `connect` call. |
| P2P group negotiation can take 10–30 seconds on some Android devices | `WifiHandoffController` fires `connectGroup` fire-and-forget via `unawaited`; no UI-blocking timeout. `wifiConnectionStateProvider` stays in `starting` until success or failure; the session screen can show a "connecting..." badge. |
| Inter font metric differences between Flutter's text engine and Pango despite identical TTF files | Accepted; exact glyph-level parity requires firmware testing. The semantics table in the cross-repo response doc is the shared contract. |

---

## Sources & References

- **Origin A:** [docs/brainstorms/2026-06-08-overlay-pixel-parity-app-requirements.md](docs/brainstorms/2026-06-08-overlay-pixel-parity-app-requirements.md)
- **Origin B:** [docs/brainstorms/2026-06-08-wifi-direct-dynamic-credentials-app-requirements.md](docs/brainstorms/2026-06-08-wifi-direct-dynamic-credentials-app-requirements.md)
- **Cross-repo A:** [docs/cross-repo/firmware/inbound/2026-06-08-overlay-pixel-parity-contract.md](docs/cross-repo/firmware/inbound/2026-06-08-overlay-pixel-parity-contract.md)
- **Cross-repo B:** [docs/cross-repo/firmware/inbound/2026-06-08-wifi-direct-dynamic-credentials.md](docs/cross-repo/firmware/inbound/2026-06-08-wifi-direct-dynamic-credentials.md)
- Related plan: [docs/plans/2026-06-03-013-feat-overlay-layout-session-ble-wiring-plan.md](docs/plans/2026-06-03-013-feat-overlay-layout-session-ble-wiring-plan.md)
- Solutions: [docs/solutions/logic-errors/core-importing-feature-layer-inversion-2026-05-26.md](docs/solutions/logic-errors/core-importing-feature-layer-inversion-2026-05-26.md)
- Solutions: [docs/solutions/integration-issues/ffmpegkit-android16-plugin-registration-abort-2026-05-27.md](docs/solutions/integration-issues/ffmpegkit-android16-plugin-registration-abort-2026-05-27.md)
