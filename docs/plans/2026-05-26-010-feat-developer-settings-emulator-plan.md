---
title: "feat: Developer Settings Panel + Camera Emulator Fidelity"
type: feat
status: active
date: 2026-05-26
origin: docs/brainstorms/2026-05-26-developer-settings-requirements.md
---

# feat: Developer Settings Panel + Camera Emulator Fidelity

## Summary

Replaces the compile-time `kUseMockData` dart-define with a runtime `DevConfig` (SharedPreferences) controllable from a new Developer Settings page inside the app. Reorganizes `lib/mock/` into `seed/` and `emulator/` subfolders to make the conceptual split explicit. Wires the BLE and WiFi emulators through the actual Protobuf wire format so the contracts in `proto/bluetooth.proto` and `proto/wifi.proto` are exercised end-to-end and portable to firmware. Excludes all mock code from stage/prod builds via entry-point injection. Migrates the devcontainer to Docker Compose and adds a `mock-camera-wifi` service stub (fully specced in the companion sub-plan `docs/plans/2026-05-26-011-feat-mock-camera-wifi-service-plan.md`).

---

## Problem Frame

The current dev workflow couples data-mode decisions to build time: `--dart-define=kUseMockData=true` must be threaded through every `flutter run` and `flutter build` invocation, making it impractical to hand a dev APK to a tester on an Android phone. The mock modules (`MockBleService`, `MockWifiService`, `MockDataSeeder`) are unconditionally imported in provider files, so their symbols compile into every build flavor including production. The BLE emulator returns bare Dart objects without exercising the Protobuf encoding path, meaning a schema change in `proto/bluetooth.proto` can go undetected until the app talks to real firmware. The WiFi emulator simulates downloads by copying a bundled file locally rather than going through the actual HTTP + RTSP stack, so download and preview code paths are never validated against a real server contract.

---

## Requirements

Carried from `docs/brainstorms/2026-05-26-developer-settings-requirements.md`:

- R1. Developer nav row visible in Settings only when `kAppEnv.isDevBackend`; absent in stage/prod.
- R2. Developer nav row opens a Developer Settings page (design quality consistent with the settings surface).
- R3. Three mutually exclusive data modes: **Full** (seed + camera emulation), **Seed only** (seed, no camera), **Empty** (full DB wipe).
- R4. Mode changes persisted immediately to SharedPreferences; current in-app state unaffected until restart.
- R5. Page shows active (booted) config and staged (pending) config; "Restart to apply" indicator when they differ.
- R6. Camera emulation toggle controls whether the BLE emulator advertises a discoverable mock device.
- R7. Camera emulation state independently persisted; togglable regardless of data mode.
- R8. Default when no prefs exist: `dataMode=full, cameraEmulation=true, serverAddress=localhost`.
- R9. `main()` reads DevConfig before provider init; applies: wipe (empty) → seed (full/seed) → pass flags to services.
- R10. `kUseMockData` dart-define removed; `kAppEnv` remains the only compile-time env var.
- R11. `main()` seeding driven entirely by DevConfig.
- R12. Mock modules (`MockBleService`, `MockWifiService`, `MockDataSeeder`, `DevConfig`, Developer Settings page) excluded from stage/prod at the import level — not just behind a runtime guard.

**Origin flows:** F1 (developer changes data mode), F2 (fresh install first boot)
**Origin acceptance examples:** AE1–AE5 (data mode change shows staged vs active; empty wipes on restart; camera emulation off hides device; fresh install defaults to full; stage build has no dev panel)

---

## Scope Boundaries

- RTMP outbound emulation (camera → YouTube/Twitch): the phone sends a BLE `StreamingControlCommand` and never receives the RTMP stream — no mock server component needed.
- Running any server process inside the Flutter app.
- iOS builds (devcontainer is Linux/Android only).
- `MockWifiService` RTSP/HTTP server implementation: specced in the companion sub-plan (U11 stubs the service; the sub-plan drives the Docker implementation).
- MockBleService behavior improvements beyond proto fidelity (richer telemetry values, timing randomization) — deferred to a future emulator pass.

### Deferred to Follow-Up Work

- Firmware integration of the proto contracts: the proto files and the emulator are the handoff artifact; firmware implements against them in a separate project.
- `BleServiceImpl` chunking reassembly for multi-chunk responses (thumbnails): the chunking envelope is in `bluetooth.proto`; single-chunk flow is validated in this plan; multi-chunk reassembly is a follow-up.

---

## Context & Research

### Relevant Code and Patterns

- `lib/core/config/env.dart` — `kAppEnv`, `kUseMockData` definitions; `kUseMockData` retired here.
- `lib/main.dart` — `if (kUseMockData)` blocks at lines 20 and 48; replaced by DevConfig read.
- `lib/core/ble/ble_providers.dart` — unconditional `import '../../mock/mock_ble_service.dart'`; this import is removed and the provider defaults to `BleServiceImpl`.
- `lib/core/wifi/wifi_providers.dart` — same pattern for `MockWifiService`.
- `lib/features/discovery/debug_page.dart` — imports `MockDataSeeder`, references `kUseMockData` in `_reset()`; both replaced by `devConfigProvider`.
- `lib/mock/mock_ble_service.dart` — constructor: `MockBleService({scanDeviceAppearDelays, connectionDelay, failureRate, randomSeed})`; scan emits two hardcoded `SstDevice` entries via `Future.delayed`.
- `lib/mock/mock_wifi_service.dart` — constructor has `pairingDelay`, `previewFps`, `downloadDuration`, `downloadFailureRate`; simulates download by copying bundled MP4.
- `lib/core/ble/ble_service_impl.dart` — has TODO comment "When wiring proto encoding, regenerate Dart bindings from `proto/bluetooth.proto`"; proto encoding is **not yet implemented** in the real impl either.
- `lib/core/state/last_camera.dart` — canonical SharedPreferences pattern: `SharedPreferences.getInstance()` in each async method, `AsyncNotifier` for Riverpod integration.
- `lib/features/settings/settings_page.dart` — `_NavRow` / `_RowItem` primitives; `kAppEnv` already imported.
- `proto/bluetooth.proto` — complete BLE control schema: `ChunkedPayload`, `Command`/`CommandResponse` envelopes, all domain messages.
- `proto/wifi.proto` — `WifiDirectGroupResponse`, `PreviewStreamDescriptor`, `PreviewFrame`.
- `just gen-proto` — regenerates `lib/models/proto/` from `proto/*.proto`; bindings are gitignored.
- `.devcontainer/devcontainer.json` — standalone Dockerfile build; no Docker Compose today.

### Institutional Learnings

- **bool.fromEnvironment default tied to APP_ENV** (`docs/solutions/developer-experience/bool-fromEnvironment-default-tied-to-app-env-2026-05-19.md`): no new compile-time bool flags are added in this plan; `kUseMockData` is removed entirely rather than replaced with another dart-define.
- **isDevBackend legitimate uses** (`docs/solutions/conventions/isdevbackend-must-not-bypass-connection-state-guards-2026-05-19.md`): `kAppEnv.isDevBackend` is allowed for service selection and dev-only diagnostic screens. The Developer Settings nav row and DebugPage navigation are both legitimate uses.
- **Drift DB reset in-place** (`docs/solutions/architecture-patterns/riverpod-drift-db-reset-in-place-2026-05-11.md`): wipe in FK dependency order inside a single `db.transaction()`, then `db.seedBaseData()`. Never close the DB. Watch streams re-emit automatically after the transaction.
- **Core → feature layer inversion** (`docs/solutions/logic-errors/core-importing-feature-layer-inversion-2026-05-26.md`): `DevConfig` lives in `lib/core/config/`; the Developer Settings page lives in `lib/features/settings/developer/`. Neither imports from the other's direction.

---

## Key Technical Decisions

- **Entry-point injection over conditional imports for R12**: Dart's `import … if (dart.library.*)` only works with `dart.library.*` conditions, not user constants like `kAppEnv`. True compile-time exclusion requires the mock file to never appear in the import graph of any file that stage/prod entry points reach. Solution: `ble_providers.dart` and `wifi_providers.dart` drop their mock imports and default to real implementations; `main.dart` (dev) imports all mock modules directly and overrides providers at `ProviderContainer` creation; `main_prod.dart` (new) is the stage/prod entry point and never imports any mock file. `settings_page.dart` never imports `debug_page.dart` or `DeveloperSettingsPage` directly — navigation callbacks are injected via a `devNavigationProvider` registered only in `main.dart` (dev).

- **DevConfig loaded before `ProviderContainer` construction**: `SharedPreferences.getInstance()` is awaited at the top of `main()` (before the container is created), so the loaded config can be passed as a provider override. This avoids an async provider that would cause a loading state on every app boot.

- **DevConfig as a plain immutable data class, not a live notifier**: The config that `main()` loads is fixed for the lifetime of the session. The `DeveloperSettingsPage` state notifier holds both `activeConfig` (what booted) and `stagedConfig` (what SharedPreferences says now). Changes write to SharedPreferences immediately but only take effect after restart.

- **Proto round-trip in MockBleService validates schema fitness**: `BleServiceImpl` has proto encoding deferred (see ble_service_impl.dart comment). The emulator implements it first — encoding `BleCommand` → proto `Command` bytes → decoding back, then constructing `CommandResponse` bytes → decoding to `BleCommandResponse<T>`. This makes the emulator the schema reference implementation. `BleServiceImpl` then follows the same pattern in U5, completing the full real-device path.

- **WiFi mock points to configurable external server**: `MockWifiService.connectGroup()` returns a `WifiDirectGroup` whose RTSP URL and HTTP base URL are derived from `DevConfig.serverAddress`. The real preview and download code paths in the app connect to this address. `adb reverse` bridges Android's loopback to the host-running Docker service.

- **lib/mock/ kept, split into seed/ and emulator/**: The `seed/` subfolder holds DB-seeding code (phone-side data); `emulator/` holds camera-channel simulation (BLE + WiFi). File names are unchanged; only paths move.

---

## Open Questions

### Resolved During Planning

- **Can Dart conditional imports exclude mock code based on kAppEnv?** No — `import … if` only works with `dart.library.*`. Entry-point injection is the correct approach.
- **Does BleServiceImpl already implement proto encoding?** No — it has a deferred TODO comment. U5 implements it.
- **Is shared_preferences already a dependency?** Yes — `^2.3.3` in pubspec.yaml, used in three existing files.
- **Does the devcontainer use Docker Compose?** No — standalone Dockerfile. U11 migrates it.

### Deferred to Implementation

- **Exact `adb reverse` failure handling when no device is connected**: `adb reverse` fails gracefully if no device is attached. The post-start script should run it conditionally; implementation should test with and without a connected device.
- **How `MockBleService` constructs realistic telemetry values for proto encoding**: the proto `DeviceTelemetry` message has specific field types (uint64 bytes, float percentages). The emulator should produce values that look realistic; exact seed values are an implementation choice.
- **mediamtx vs other RTSP server choice for mock-camera-wifi**: specced in the sub-plan; implementation chooses based on Docker image size and ARM64 support.

---

## High-Level Technical Design

> *This illustrates the intended approach and is directional guidance for review, not implementation specification. The implementing agent should treat it as context, not code to reproduce.*

### Entry-point injection (R12)

```
main.dart (APP_ENV=dev)
  ├── imports: MockBleService, MockWifiService, MockDataSeeder, DevConfig
  │             DeveloperSettingsPage, DebugPage
  ├── loads DevConfig from SharedPreferences
  ├── applies data mode (wipe / seed)
  └── ProviderContainer(overrides: [
          bleServiceProvider  → MockBleService(advertiseDevices: cfg.cameraEmulation)
          wifiServiceProvider → MockWifiService(serverAddress: cfg.serverAddress)
          devConfigProvider   → cfg
          devNavigationProvider → DevNavigation(
              debugPage: () => DebugPage(),
              developerSettings: () => DeveloperSettingsPage()
          )
          devReseedProvider   → () async { MockDataSeeder(db).seed() }
      ])

main_prod.dart (APP_ENV=stage/prod)
  ├── imports: NONE of the above
  └── ProviderContainer()   ← providers use their default real implementations
```

### Proto round-trip in the BLE emulator

```
App calls: sendCommand(deviceId, GetTelemetryCommand())

MockBleService:
  1. Map BleCommand → proto Command {get_telemetry: GetTelemetryCommand{}}
  2. Serialize Command → bytes  (validates field mappings)
  3. Deserialize bytes → Command (validates schema round-trip)
  4. Build proto CommandResponse {telemetry: DeviceTelemetry{...}}
  5. Serialize → bytes
  6. Deserialize → CommandResponse
  7. Map CommandResponse → BleCommandResponse<DeviceTelemetry>

Result: full proto encode/decode path exercised without a real camera
```

### WiFi emulator data flow (with mock-camera-wifi service)

```
DevConfig.serverAddress = "localhost" (adb reverse maps → host:port)

MockWifiService.connectGroup():
  → WifiDirectGroup {
      ssid: "DIRECT-mock-sst-cam",
      psk: "dev-psk",
      groupOwnerIp: serverAddress,
      previewPort: 8554,   ← mediamtx RTSP
      downloadPort: 8080   ← HTTP Range server
    }

App preview player: rtsp://localhost:8554/preview
App download client: GET http://localhost:8080/recordings/{id}
                     Authorization: Bearer <token from BLE emulator>
```

---

## Implementation Units

### U1. Reorganize lib/mock/ into seed/ and emulator/ subfolders

**Goal:** Establish explicit subfolder split reflecting the conceptual distinction between phone-side DB seeding and camera-channel simulation.

**Requirements:** R10 (prerequisite for retiring kUseMockData cleanly); structural prerequisite for all emulator units.

**Dependencies:** None.

**Files:**
- Move: `lib/mock/mock_data_seeder.dart` → `lib/mock/seed/mock_data_seeder.dart`
- Move: `lib/mock/mock_ble_service.dart` → `lib/mock/emulator/mock_ble_service.dart`
- Move: `lib/mock/mock_wifi_service.dart` → `lib/mock/emulator/mock_wifi_service.dart`
- Modify: `lib/main.dart` (import paths)
- Modify: `lib/features/discovery/debug_page.dart` (import path)
- Modify: `lib/core/ble/ble_providers.dart` (import path — temporary; removed in U7)
- Modify: `lib/core/wifi/wifi_providers.dart` (import path — temporary; removed in U7)
- Modify: `test/mock/mock_ble_service_test.dart`, `test/mock/mock_data_seeder_test.dart`, `test/mock/mock_wifi_service_test.dart` (import paths)

**Approach:**
- Pure file move + import path update. No logic changes. All tests must pass after this unit.
- Create `lib/mock/seed/` and `lib/mock/emulator/` directories.

**Patterns to follow:** Existing file layout under `lib/core/ble/`, `lib/core/wifi/`.

**Test scenarios:**
- Happy path: `just test` passes with no changes to test logic — only import paths updated.

**Verification:** `just analyze` and `just test` green; no references to old paths remain (`grep -r 'mock/mock_ble\|mock/mock_wifi\|mock/mock_data'` returns nothing under `lib/`).

---

### U2. DevConfig — data class and Riverpod provider

**Goal:** SharedPreferences-backed runtime configuration for the dev session: data mode, camera emulation, WiFi server address. Loaded once at startup; immutable during the session.

**Requirements:** R3, R4, R7, R8, R9.

**Dependencies:** U1.

**Files:**
- Create: `lib/core/config/dev_config.dart`
- Test: `test/core/config/dev_config_test.dart`

**Approach:**
- `DataMode` enum: `full`, `seed`, `empty`.
- `DevConfig` immutable data class: `dataMode`, `cameraEmulation` (bool), `serverAddress` (String).
- Static `DevConfig.load()` async factory: reads from SharedPreferences, returns config with defaults when keys are absent.
- Static `DevConfig.defaults`: `dataMode=full, cameraEmulation=true, serverAddress='localhost'`.
- `DevConfig.save()`: writes all fields to SharedPreferences.
- `devConfigProvider = Provider<DevConfig>((ref) => DevConfig.defaults)`: a safe non-throwing default so common code can read it without crashing in prod (where the override is never registered). In dev builds, `main.dart` overrides it with the loaded config.
- SharedPreferences key constants follow the `_kLastConnectedDeviceIdKey` naming convention from `lib/core/state/last_camera.dart`.

**Patterns to follow:** `lib/core/state/last_camera.dart` for SharedPreferences read/write pattern.

**Test scenarios:**
- Happy path: `DevConfig.load()` with no prefs returns defaults (`full`, `true`, `'localhost'`).
- Happy path: after `save()`, a subsequent `load()` returns the saved values.
- Edge case: missing individual keys in prefs fall back to their respective defaults, not all-or-nothing.
- Edge case: unknown `dataMode` string in prefs (e.g., from an old app version) falls back to `full`.

**Verification:** `devConfigProvider` reads without throwing in any build flavor; `DevConfig.load()` returns defaults on a clean device.

---

### U3. Retire kUseMockData — remove dart-define and update all call sites

**Goal:** Remove `kUseMockData` from `env.dart` and replace every reference with `DevConfig`-based logic.

**Requirements:** R10, R11.

**Dependencies:** U2.

**Files:**
- Modify: `lib/core/config/env.dart` (remove `kUseMockData` declaration)
- Modify: `lib/main.dart` (replace two `if (kUseMockData)` blocks with DevConfig reads — partial rewrite; U7 does the full `main.dart` restructuring)
- Modify: `lib/features/discovery/debug_page.dart` (replace `if (kUseMockData)` in `_reset()` with `ref.read(devConfigProvider).dataMode != DataMode.empty`)

**Approach:**
- In `env.dart`: delete the `kUseMockData` const and its comment.
- In `debug_page.dart`: the `_reset()` handler currently calls `MockDataSeeder(db).seed()` when `kUseMockData`. Replace with calling the injected `devReseedProvider` callback (a `Provider<Future<void> Function()>` registered in `main.dart` (dev), defaulting to a no-op). This removes the direct `MockDataSeeder` import from `debug_page.dart` — breaking the prod import chain.
- The `main.dart` changes in this unit are minimal stubs; U7 does the full restructuring.

**Patterns to follow:** `devConfigProvider` read pattern established in U2.

**Test scenarios:**
- Happy path: `DebugPage` reset in dev mode re-seeds the DB (integration test verifying rows exist after reset when `dataMode=full`).
- Edge case: `DebugPage` reset in `dataMode=empty` skips seeding — DB stays empty after reset.
- Covers AE2 (empty mode produces empty DB after restart/reset).

**Verification:** `grep -r 'kUseMockData' lib/` returns zero results; `just analyze` green.

---

### U4. MockBleService — advertiseDevices param + proto round-trip fidelity

**Goal:** Add `advertiseDevices` flag to suppress camera discovery; wire the emulator through the actual `bluetooth.proto` encode/decode path so the schema is exercised end-to-end.

**Requirements:** R6, R9; emulator contract fidelity.

**Dependencies:** U1.

**Files:**
- Modify: `lib/mock/emulator/mock_ble_service.dart`
- Modify: `test/mock/mock_ble_service_test.dart`

**Approach:**
- Add `bool advertiseDevices = true` to the constructor. When `false`, `startScan()` completes immediately without emitting any devices.
- Run `just gen-proto` to ensure generated bindings are present before implementing.
- In `sendCommand()`: map the incoming `BleCommand` sealed variant to the corresponding proto `Command` oneof field, serialize to bytes, deserialize (round-trip validation), then construct the appropriate proto `CommandResponse`, serialize, deserialize, and map to `BleCommandResponse<T>`.
- Use the `ChunkedPayload` envelope for the round-trip: wrap/unwrap `Command` and `CommandResponse` bytes in `ChunkedPayload` with `chunk_index=0, total_chunks=1` for single-chunk messages (multi-chunk reassembly is deferred).
- Correlation IDs must be echoed correctly from `Command.correlation_id` into `CommandResponse.correlation_id`.
- `telemetryStream` and `matchStateStream` similarly construct proto messages and deserialize before emitting.

**Execution note:** Implement the proto round-trip test-first. Write a test that calls `sendCommand(GetTelemetryCommand())` and asserts the response contains a valid `DeviceTelemetry` — then implement to make it pass.

**Patterns to follow:** `lib/core/models/command.dart` for the `BleCommand` sealed class hierarchy.

**Test scenarios:**
- Happy path: `startScan()` with `advertiseDevices=true` emits mock devices after delays.
- Happy path: `startScan()` with `advertiseDevices=false` emits an empty list and completes.
- Happy path: `sendCommand(GetTelemetryCommand())` returns `BleCommandResponse<DeviceTelemetry>` with all expected fields populated.
- Happy path: `sendCommand(GetMatchStateCommand())` returns valid `MatchState`.
- Happy path: `sendCommand(MatchConfigCommand(...))` returns `OK` status response.
- Edge case: correlation_id in response matches the command's generated UUID.
- Edge case: proto round-trip is lossless — a `DeviceTelemetry` serialized and deserialized has the same field values.
- Integration: full scan → connect → sendCommand cycle runs without proto deserialization errors.

**Verification:** `just test` green; no `MissingPluginException` or proto parse errors in test output.

---

### U5. BleServiceImpl — proto encoding + receive-path validation

**Goal:** Wire the real BLE implementation through the same proto encode/decode path as the emulator, completing the deferred TODO in `ble_service_impl.dart`.

**Requirements:** Emulator contract fidelity; R12 (real impl and mock impl now share the same proto path).

**Dependencies:** U4 (proto patterns established in emulator first).

**Files:**
- Modify: `lib/core/ble/ble_service_impl.dart`
- Test: `test/ble/ble_service_impl_proto_test.dart` (unit tests for encode/decode logic, not requiring a real device)

**Approach:**
- Encoding (app → camera): map `BleCommand` → proto `Command` → serialize to bytes → wrap in `ChunkedPayload` → write to Command Write GATT characteristic.
- Decoding + validation (camera → app): Command Response notify bytes → unwrap `ChunkedPayload` → deserialize `CommandResponse` → validate `correlation_id` matches pending request → validate `status`  → map to `BleCommandResponse<T>`. Malformed bytes (proto parse error) surface as `BleCommandResponse.error()` with a structured message rather than an uncaught exception.
- Correlation matching: maintain a `Map<String, Completer>` keyed by `correlation_id` to match async responses to their originating command.
- Extract the encode/decode logic into a separate `BleProtocol` helper class (or static methods) that both `BleServiceImpl` and tests can use without needing a real GATT connection.

**Patterns to follow:** Proto round-trip pattern established in U4's `MockBleService`.

**Test scenarios:**
- Happy path: `BleProtocol.encodeCommand(GetTelemetryCommand())` produces non-empty bytes decodable as a valid proto `Command`.
- Happy path: a valid `CommandResponse` proto bytes decodes to the expected `BleCommandResponse<DeviceTelemetry>`.
- Error path: malformed bytes passed to decode produce a `BleCommandResponse` with error status (no exception thrown).
- Error path: `correlation_id` mismatch produces a `BleCommandResponse` with error status.
- Edge case: `ResponseStatus.TIMEOUT` from firmware maps to a `BleCommandResponse` with error (not a Dart exception).

**Verification:** `just test` green; `just analyze` green; the `BleProtocol` helper is importable without a real BLE device.

---

### U6. MockWifiService — wifi.proto-shaped responses + configurable server address

**Goal:** Make `MockWifiService.connectGroup()` return a proper `WifiDirectGroup` whose RTSP and HTTP addresses point to the configured external server (Docker `mock-camera-wifi` service), so the app's real preview and download code paths are exercised.

**Requirements:** R7 (camera emulation toggle); WiFi emulator contract fidelity.

**Dependencies:** U2 (DevConfig for `serverAddress`), U1.

**Files:**
- Modify: `lib/mock/emulator/mock_wifi_service.dart`
- Modify: `test/mock/mock_wifi_service_test.dart`

**Approach:**
- Add `String serverAddress = 'localhost'` constructor parameter (passed from `DevConfig.serverAddress` by `main.dart`).
- `connectGroup()`: return a `WifiDirectGroup` with `groupOwnerIp = serverAddress`, `previewPort = 8554`, `downloadPort = 8080`, `ssid = 'DIRECT-mock-sst-cam'`, `psk = 'dev-psk'`. These match the ports exposed by the `mock-camera-wifi` Docker service.
- `previewDescriptor()`: return a `PreviewStreamDescriptor` with `url = 'rtsp://$serverAddress:8554/preview'`, `codec = PreviewCodec.RTSP_H264`, standard dimensions (640×360), `fps = 15`.
- Download (`downloadRecording()`/`startDownload()`): instead of copying a bundled file, issue a real HTTP GET to `http://$serverAddress:8080/recordings/$uuid` with the Bearer token from the BLE emulator's `requestDownload()` response. Fall back to the bundled file copy when the HTTP request fails (server not running), so dev without the Docker service still works.
- The `WifiDirectGroup` and `PreviewStreamDescriptor` types should match the fields defined in `proto/wifi.proto` (`WifiDirectGroupResponse`, `PreviewStreamDescriptor`).

**Patterns to follow:** `lib/core/wifi/wifi_service.dart` interface; `WifiDirectGroup` model in `lib/core/models/wifi.dart`.

**Test scenarios:**
- Happy path: `connectGroup()` returns a `WifiDirectGroup` with `groupOwnerIp = 'localhost'`.
- Happy path: `connectGroup()` with custom `serverAddress = '192.168.1.100'` uses that IP in the returned group.
- Happy path: `previewDescriptor()` returns RTSP URL matching `rtsp://<serverAddress>:8554/preview`.
- Edge case: download falls back to bundled file when HTTP server is unreachable (connection refused).
- Edge case: `serverAddress` empty string → falls back to `'localhost'`.

**Verification:** `just test` green; the RTSP URL and download URL in the mock match what the `mock-camera-wifi` service exposes (cross-reference with sub-plan `docs/plans/2026-05-26-011-feat-mock-camera-wifi-service-plan.md`).

---

### U7. Entry-point injection — provider restructuring, main_prod.dart, dev-nav provider, justfile

**Goal:** Exclude all mock modules from stage/prod binaries by making `ble_providers.dart` and `wifi_providers.dart` default to real implementations and having `main.dart` (dev) own all mock imports and provider overrides.

**Requirements:** R12.

**Dependencies:** U2, U3, U4, U5, U6.

**Files:**
- Modify: `lib/core/ble/ble_providers.dart` (remove mock import; default to `BleServiceImpl`)
- Modify: `lib/core/wifi/wifi_providers.dart` (remove mock import; default to `WifiServiceImpl`)
- Create: `lib/core/config/dev_navigation.dart` (`DevNavigation` data class + `devNavigationProvider`)
- Create: `lib/core/config/dev_reseeder.dart` (`devReseedProvider` — injectable seeding callback)
- Create: `lib/main_prod.dart` (stage/prod entry point — zero mock imports)
- Modify: `lib/main.dart` (full restructuring: DevConfig load, data-mode apply, provider overrides, dev-nav registration)
- Modify: `lib/features/settings/settings_page.dart` (remove `import debug_page.dart`; read `devNavigationProvider` for long-press callback and Developer nav row callback)
- Modify: `justfile` (stage/prod targets use `--target=lib/main_prod.dart`)

**Approach:**
- `ble_providers.dart` body becomes simply `BleServiceImpl()` with `ref.onDispose(svc.dispose)`. No mock import.
- `wifi_providers.dart` body becomes simply `WifiServiceImpl()`. No mock import.
- `DevNavigation` data class: `final Widget Function()? debugPage; final Widget Function()? developerSettings;`. `devNavigationProvider` defaults to `DevNavigation()` (both null).
- `devReseedProvider`: `Provider<Future<void> Function()>((ref) => () async {})` — no-op default; `main.dart` (dev) overrides with `MockDataSeeder(db).seed`.
- `main.dart` (dev): `await DevConfig.load()` → apply data mode (wipe via `_wipeDb()` or seed via `MockDataSeeder`) → create `ProviderContainer` with all overrides → `runApp`.
- `main_prod.dart`: `WidgetsFlutterBinding.ensureInitialized()` → `FlutterNativeSplash.preserve()` → `ProviderContainer()` (no overrides) → `runApp(SstCamApp())` → `FlutterNativeSplash.remove()`. Zero mock imports.
- `settings_page.dart`: Replace `import debug_page.dart` with `import '../../core/config/dev_navigation.dart'`. Long-press on About fires `devNavigation.debugPage?.call()`. Developer nav row fires `devNavigation.developerSettings?.call()`.
- Justfile: `build-android` and CI commands get a `build-android-prod` variant using `--target=lib/main_prod.dart --dart-define=APP_ENV=prod`. Existing `build-android` stays as-is (dev APK).

**Patterns to follow:** `ProviderContainer` override pattern in `test/` files; `lib/core/state/last_camera.dart` for async SharedPreferences in `main`.

**Test scenarios:**
- Happy path: widget test with `main.dart` dev path seeds the DB (integration: rows exist after boot in `full` mode).
- Happy path: widget test with `empty` mode boots to an empty DB.
- Covers AE4 (fresh install defaults to full mode without `kUseMockData` dart-define).
- Covers AE5 (prod entry point — verify no mock symbol references exist in the source files reachable from `main_prod.dart`).
- Test scaffolding note: widget tests that need a non-null `devNavigationProvider` (e.g., U9 tests showing the Developer nav row) must override it explicitly via `devNavigationProvider.overrideWithValue(DevNavigation(developerSettings: () => const SizedBox()))` — the default is a no-op `DevNavigation()`. Document this pattern in the test file.

**Verification:** `grep -r 'MockBleService\|MockWifiService\|MockDataSeeder\|DevConfig' lib/core/ble/ble_providers.dart lib/core/wifi/wifi_providers.dart lib/main_prod.dart` returns zero results. Do **not** grep the compiled APK binary for symbol names — compiled Dart output is not human-readable; the source-level grep above is the authoritative check.

---

### U8. DeveloperSettingsPage + state notifier

**Goal:** The Developer Settings page — data mode picker, camera emulation toggle, WiFi server address field, staged-vs-active indicator, and close-to-apply button.

**Requirements:** R2, R3, R4, R5, R6, R7.

**Dependencies:** U2.

**Files:**
- Create: `lib/features/settings/developer/developer_settings_state.dart`
- Create: `lib/features/settings/developer/developer_settings_page.dart`
- Test: `test/features/settings/developer_settings_page_test.dart`

**Approach:**
- State notifier (`DeveloperSettingsNotifier extends AutoDisposeNotifier<DeveloperSettingsState>`): holds `activeConfig` (from `devConfigProvider`) and `stagedConfig` (from latest SharedPreferences read). Exposes `setDataMode()`, `setCameraEmulation()`, `setServerAddress()` — each writes to SharedPreferences and updates `stagedConfig`.
- `DeveloperSettingsState`: `{ activeConfig: DevConfig, stagedConfig: DevConfig }`. `bool get hasPendingChanges => stagedConfig != activeConfig`.
- UI: `WfCard` with a three-option segmented control or radio-style chips for data mode (`Full`, `Seed only`, `Empty`). `WfSwitch` for camera emulation. `TextField`/`WfCard`-wrapped text input for server address. Inline `WfChip` or `Container` indicator showing "Restart to apply" when `hasPendingChanges`.
- Close button: `WfButton(label: 'Close & restart', variant: WfButtonVariant.destructive)` → `showDialog` confirmation → `SystemNavigator.pop()`.
- Apply `ce-frontend-design` conventions: dark theme, `T.bg` surface, `T.ink`/`T.ink2` text hierarchy, consistent card padding, `WfSection` headers for grouping.

**Patterns to follow:** `lib/features/settings/users/users_state.dart` for the notifier pattern; `lib/features/settings/settings_page.dart` for `WfCard`/`_NavRow` row structure; `lib/core/widgets/wf_chip.dart` for the restart indicator; `lib/core/widgets/wf_button.dart` for the close button.

**Test scenarios:**
- Happy path: selecting "Empty" mode shows the "Restart to apply" indicator when active mode is "Full".
- Happy path: toggling camera emulation updates `stagedConfig.cameraEmulation`; indicator appears.
- Happy path: when `stagedConfig == activeConfig`, no indicator is shown.
- Happy path: close button shows a confirmation dialog before calling `SystemNavigator.pop()`.
- Edge case: server address field with an empty value falls back to `'localhost'` on save.
- Covers AE1 (data mode change shows staged vs active state).

**Verification:** Widget tests pass; page renders without overflow or layout errors on a standard Android screen size.

---

### U9. Settings page integration — Developer nav row via dev-nav provider

**Goal:** Wire the Developer nav row into Settings and register the dev-nav callbacks (DebugPage + DeveloperSettingsPage) in `main.dart` (dev).

**Requirements:** R1; Covers AE5 (absent in stage/prod).

**Dependencies:** U7, U8.

**Files:**
- Modify: `lib/features/settings/settings_page.dart` (add Developer nav row reading from `devNavigationProvider`)
- Modify: `lib/main.dart` (add `DeveloperSettingsPage` and `DebugPage` imports; register in `devNavigationProvider` override)

**Approach:**
- In `settings_page.dart`: below the "Backup & restore" row, add `if (devNavigation.developerSettings != null)` → `Divider` + `_NavRow(label: 'Developer', leading: Icon(Icons.code), sub: 'Dev tools & data mode', onTap: () => Navigator.push(..., devNavigation.developerSettings!()))`.
- The `kAppEnv.isDevBackend` guard is implicit: in prod, `devNavigation.developerSettings` is always null, so the row is never rendered. In dev, it's set by `main.dart`.
- The existing long-press on "About" → DebugPage wiring is also replaced with `devNavigation.debugPage?.call()`.
- `kAppEnv` import can be removed from `settings_page.dart` once the `kAppEnv != AppEnv.prod` guard on the long-press is replaced.

**Patterns to follow:** Existing `_NavRow` pattern; `devNavigationProvider` from U7.

**Test scenarios:**
- Happy path: widget test with dev-nav provider override containing a non-null `developerSettings` callback shows the Developer nav row.
- Covers AE1 (nav row visible in dev).
- Covers AE5 (nav row absent when `devNavigation.developerSettings == null`).

**Verification:** Settings page renders in prod context (null dev-nav) with no Developer row; renders in dev context with the row.

---

### U10. DebugPage — remove kUseMockData, use devReseedProvider

**Goal:** Update `DebugPage._reset()` to use the injected reseeding callback instead of calling `MockDataSeeder` directly, breaking the last remaining prod import chain.

**Requirements:** R12 (removes `import mock_data_seeder.dart` from `debug_page.dart`).

**Dependencies:** U3, U7.

**Files:**
- Modify: `lib/features/discovery/debug_page.dart`

**Approach:**
- Remove `import '../../mock/seed/mock_data_seeder.dart'` and `import '../../core/config/env.dart'`.
- In `_reset()`: after `db.seedBaseData()`, call `await ref.read(devReseedProvider)()` instead of the `if (kUseMockData)` block. In prod (if debug_page.dart were somehow reachable, which it won't be), the default no-op runs safely.
- `DebugPage` is a `ConsumerStatefulWidget` so `ref.read` is available.

**Patterns to follow:** `devReseedProvider` from U7.

**Test scenarios:**
- Happy path: `_reset()` in dev mode (reseeder registered) results in fixture rows in the DB after reset.
- Edge case: `_reset()` when `devReseedProvider` returns a no-op (empty/prod context) — DB ends up empty after reset (correct for empty mode or prod).

**Verification:** `grep -r 'mock_data_seeder\|kUseMockData' lib/features/discovery/debug_page.dart` returns zero results; `just analyze` green.

---

### U11. Devcontainer — Docker Compose migration + mock-camera-wifi service stub

**Goal:** Migrate the devcontainer from a standalone Dockerfile build to Docker Compose so the `mock-camera-wifi` service can run alongside the Flutter dev environment. Add the service stub (Dockerfile + compose entry) per the sub-plan spec.

**Requirements:** WiFi emulator contract fidelity (infrastructure side).

**Dependencies:** U6 (port contract: 8554 RTSP, 8080 HTTP).

**Files:**
- Create: `.devcontainer/docker-compose.devcontainer.yml`
- Create: `.devcontainer/mock-camera-wifi/Dockerfile` (stub — fully implemented per sub-plan)
- Create: `.devcontainer/mock-camera-wifi/README.md` (pointer to sub-plan)
- Modify: `.devcontainer/devcontainer.json` (switch from `build` to `dockerComposeFile`)
- Modify: `.devcontainer/script/post-start.sh` (add `adb reverse` for ports 8554 + 8080)

**Approach:**
- `docker-compose.devcontainer.yml` defines two services:
  - `app`: the Flutter devcontainer (current Dockerfile build), all existing `runArgs` / envs / mounts translated to compose equivalents; `command: sleep infinity`.
  - `mock-camera-wifi`: built from `.devcontainer/mock-camera-wifi/Dockerfile`; exposes `8554:8554` (RTSP) and `8080:8080` (HTTP); always restarts.
- `devcontainer.json` replaces `build` block with `"dockerComposeFile": [".devcontainer/docker-compose.devcontainer.yml"], "service": "app", "workspaceFolder": "/workspaces/sst-cam-app"`. All other fields (`customizations`, lifecycle scripts, `remoteEnv`, `remoteUser`) are preserved.
- **`runArgs` → compose equivalents** (all three must be carried over or existing behavior breaks):
  - `--platform linux/amd64` → `platform: linux/amd64` on the `app` service.
  - `--add-host=host.docker.internal:host-gateway` → `extra_hosts: ["host.docker.internal:host-gateway"]` on the `app` service. **This is required** — omitting it breaks `ADB_SERVER_SOCKET: tcp:host.docker.internal:5037` and wireless ADB stops working.
  - `--name` is handled by Docker Compose project naming; no direct equivalent needed.
- **Named volume migration**: The current mount uses `source=claude-code-config-${devcontainerId}` — the `${devcontainerId}` token is devcontainer-specific and has no Docker Compose equivalent. The compose config must use a plain named volume (e.g., `claude-code-config`). **Consequence**: existing developers' `/home/vscode/.claude` data (Claude Code config, memory files, credentials) stored in the old `claude-code-config-<id>` volume will not carry over automatically. Document this in a comment in the compose file and in the PR description: developers should manually copy data from the old volume if needed (`docker volume cp` or inspect + copy).
- `post-start.sh`: append `adb reverse tcp:8554 tcp:8554 2>/dev/null || true` and `adb reverse tcp:8080 tcp:8080 2>/dev/null || true` after the existing `adb-bridge.sh` invocation. The `|| true` prevents failures when no Android device is connected.
- The `mock-camera-wifi/Dockerfile` stub: `FROM alpine:3.19` with a `LABEL` pointing to the sub-plan. Actual implementation is driven by `docs/plans/2026-05-26-011-feat-mock-camera-wifi-service-plan.md`.

**Test scenarios:**
- Test expectation: none — devcontainer infrastructure; verified by rebuilding the container and confirming both services start (`docker compose ps`).

**Verification:** `docker compose -f .devcontainer/docker-compose.devcontainer.yml up -d` starts both services; `curl http://localhost:8080/health` (once sub-plan implemented) returns 200; VS Code "Reopen in Container" still works; `just test` still passes inside the container.

---

## System-Wide Impact

- **Import graph**: `ble_providers.dart` and `wifi_providers.dart` no longer import mock modules. `settings_page.dart` no longer imports `debug_page.dart`. The common import graph (reachable from `main_prod.dart`) is clean of all mock symbols.
- **Provider wiring**: `bleServiceProvider` and `wifiServiceProvider` defaults change from mock to real implementations. Any test that currently relies on the provider defaulting to the mock must add an explicit override — tests already do this via `bleServiceProvider.overrideWithValue(MockBleService())` per CLAUDE.md.
- **Proto encoding in BleServiceImpl**: this is a new code path that changes how `BleServiceImpl` writes to and reads from the GATT characteristics. Regression risk for any test using a real BLE device (device-based integration tests, if any). No pure widget tests are affected.
- **Unchanged invariants**: `BleService` and `WifiService` abstract interfaces are unchanged. All provider family signatures (`connectionStateProvider(deviceId)`, `telemetryProvider(deviceId)`, etc.) are unchanged. The `AppDatabase` and all DAO interfaces are unchanged.
- **DevConfig provider fallback**: `devConfigProvider` defaults to `DevConfig.defaults` — common code reading it in prod gets defaults without throwing. No conditional `kAppEnv` check needed at the read site.

---

## Risks & Dependencies

| Risk | Mitigation |
|------|------------|
| Proto binding generation (`just gen-proto`) fails in devcontainer | Confirm `protoc` and Dart plugin are installed in `.devcontainer/Dockerfile`; run `just gen-proto` as first step of U4 |
| `SystemNavigator.pop()` behavior varies by Android version | Test close-to-apply on a physical Android device during U8; document that behavior may differ (acceptable for dev-only tooling) |
| `adb reverse` fails silently when no device is connected | `|| true` in post-start.sh; developer must run `adb reverse` manually after connecting a device mid-session |
| Docker Compose migration breaks existing devcontainer setup | Test "Reopen in Container" before merging U11; keep a `.devcontainer/docker-compose.devcontainer.yml.bak` or a git-branch safety net |
| BleServiceImpl proto encoding breaks real device sessions | Extract encode/decode to a `BleProtocol` helper with unit tests; validate against a real device in a separate branch before merging U5 |
| mock-camera-wifi service not yet implemented when WiFi emulator lands | U6's HTTP fallback (bundled file copy) preserves existing download behavior when the service is unreachable; RTSP preview degrades gracefully |

---

## Sources & References

- **Origin document:** [docs/brainstorms/2026-05-26-developer-settings-requirements.md](docs/brainstorms/2026-05-26-developer-settings-requirements.md)
- **Companion sub-plan:** [docs/plans/2026-05-26-011-feat-mock-camera-wifi-service-plan.md](docs/plans/2026-05-26-011-feat-mock-camera-wifi-service-plan.md)
- Proto contracts: `proto/bluetooth.proto`, `proto/wifi.proto`, `proto/README.md`
- Institutional learnings: `docs/solutions/developer-experience/`, `docs/solutions/conventions/`, `docs/solutions/architecture-patterns/`
- `shared_preferences` usage examples: `lib/core/state/last_camera.dart`, `lib/features/settings/users/users_state.dart`
