---
date: 2026-05-26
topic: developer-settings-panel
---

# Developer Settings Panel

## Summary

Add a Developer section to the Settings page, visible only in `dev` builds, that lets a developer choose the data mode (full seed + camera / seed only / empty) and toggle camera emulation at runtime — no rebuild required. Settings persist in device storage and take effect after an app restart.

---

## Problem Frame

The dev workflow today requires passing `--dart-define=kUseMockData=true/false` at build time to control whether the app boots with fixture data. Testing different startup states (empty DB, seeded only, seeded + connected camera) requires separate builds. This makes it impractical to hand a dev APK to someone on an Android phone for exploratory testing — they'd need the Flutter toolchain to switch modes.

Additionally, `kUseMockData` as a compile-time variable is unnecessary; the `APP_ENV` flag already identifies a dev build, and data mode is fundamentally a runtime choice for development purposes.

---

## Key Flows

- F1. Developer changes data mode
  - **Trigger:** Developer opens Settings → Developer → changes Data Mode selection
  - **Steps:**
    1. Developer taps the Developer nav row in Settings
    2. Developer Settings page opens, showing current effective mode and camera emulation state
    3. Developer selects a different data mode or toggles camera emulation
    4. Change is staged (UI updates to show pending state); no immediate app effect
    5. Developer restarts the app (kill + reopen)
    6. `main()` reads DevConfig from SharedPreferences, applies data mode (wipe / seed / skip), and passes camera emulation flag to MockBleService
  - **Outcome:** App boots in the newly configured state
  - **Covered by:** R3, R4, R5, R6, R7

- F2. Fresh install, first boot
  - **Trigger:** Dev APK installed, no prior SharedPreferences
  - **Steps:**
    1. `main()` reads DevConfig; finds no stored value
    2. Defaults to `dataMode=full, cameraEmulation=true`
    3. Seeds DB with fixture data, MockBleService emulates a discoverable camera
  - **Outcome:** App behaves identically to how it did before this feature shipped (seed data + camera visible)
  - **Covered by:** R8

---

## Requirements

**Settings entry point**

- R1. The Settings page shows a Developer nav row only when `kAppEnv.isDevBackend` is true (i.e., `APP_ENV=dev`). The row is completely absent in `stage` and `prod` builds.
- R2. The Developer nav row navigates to a full Developer Settings page built with design quality consistent with the rest of the settings surface (`ce-frontend-design` conventions).

**Developer Settings page — data mode**

- R3. The page presents three mutually exclusive data mode options:
  - **Full** — fixture data is seeded into the DB on next boot; camera emulation is active.
  - **Seed only** — fixture data is seeded; no mock camera appears in discovery.
  - **Empty** — DB is fully wiped on next boot (all rows, including manually-entered data); no seeding occurs.
- R4. When data mode is changed, the new mode is persisted immediately to SharedPreferences. The current in-app state is not affected until restart.
- R5. The page displays both the currently active mode (what the running app booted with) and the staged mode (what will apply after the next restart). When they differ, a visible "Restart to apply" indicator is shown.

**Developer Settings page — camera emulation**

- R6. A camera emulation toggle controls whether the MockBleService advertises a virtual SST Cam device during BLE discovery.
  - **On:** a mock `sst-cam-dev` device appears in the discovery list; the user connects manually through the normal discovery flow.
  - **Off:** the mock scan returns no devices; the app behaves as if no cameras are nearby.
- R7. Camera emulation state is independently persisted in SharedPreferences. It can be toggled regardless of data mode (though the "Full" preset implies emulation on as its default suggestion — it does not enforce it).

**Default values and startup behavior**

- R8. When no DevConfig exists in SharedPreferences (fresh install or cleared storage), the effective config defaults to `dataMode=full, cameraEmulation=true`. This preserves current dev behavior.
- R9. `main()` reads DevConfig before any Riverpod provider initialization and applies the config in this order: (1) if `dataMode=empty`, wipe all DB tables; (2) if `dataMode=full` or `dataMode=seed`, run `MockDataSeeder`; (3) pass `cameraEmulation` flag to `MockBleService` construction.

**Retire `kUseMockData` compile-time flag**

- R10. The `kUseMockData` dart-define is removed. All references are replaced by the runtime DevConfig. The only remaining compile-time env variable is `kAppEnv`.
- R11. `main()` no longer reads `kUseMockData`. The seeding decision is fully driven by DevConfig.

**Code exclusion from non-dev builds**

- R12. All dev-only modules — `MockBleService`, `MockWifiService`, `MockDataSeeder`, `DevConfig`, and the Developer Settings page — must not be compiled into `stage` or `prod` APKs. They must be excluded at the import level (conditional imports or factory pattern gated on `kAppEnv`), not merely hidden behind a runtime guard. The `prod` APK must contain zero mock code.

---

## Acceptance Examples

- AE1. **Covers R3, R4, R5.** Given the app is currently running in Full mode, when the developer opens Developer Settings and selects "Empty," the page shows "Active: Full / Staged: Empty" and a "Restart to apply" chip. The running app is unaffected until killed and reopened.

- AE2. **Covers R9.** Given DevConfig has `dataMode=empty`, when the app restarts, `main()` wipes all DB tables before any provider initializes, and no seeding occurs. The app opens to a completely empty state.

- AE3. **Covers R6.** Given `cameraEmulation=false`, when the user navigates to the Discovery page and initiates a BLE scan, the device list remains empty (MockBleService returns no results). No "sst-cam-dev" device appears.

- AE4. **Covers R8, R10.** Given a freshly installed dev APK with no SharedPreferences, when the app boots, it seeds fixture data and MockBleService emulates a discoverable camera — without any `kUseMockData` dart-define being passed.

- AE5. **Covers R1, R12.** Given a build where `APP_ENV=stage` or `APP_ENV=prod`, the Settings page shows no Developer nav row, the Developer Settings page is not reachable through any navigation path, and no mock module symbols are present in the compiled binary.

---

## Success Criteria

- A developer can install a single dev APK on any Android phone and switch between all three data modes without touching the Flutter CLI or rebuilding.
- The default behavior on fresh install is identical to the current `APP_ENV=dev` experience (seeded DB, mock camera discoverable).
- `kUseMockData` no longer appears anywhere in the codebase as a dart-define or `fromEnvironment` call.
- A `prod` build analyzed with `--analyze-size` or inspected via symbol dump contains no references to `MockBleService`, `MockDataSeeder`, or `DevConfig`.

---

## Scope Boundaries

- Camera emulation does not auto-connect; discovery + manual connect is the expected flow.
- Improving `MockBleService` fidelity (more realistic telemetry, timing, edge cases) is a separate track — this feature does not change what the mock returns, only whether it appears.
- The existing `DebugPage` (raw DB browser, accessible via long-press on About) is unchanged and remains separate from the Developer Settings page.
- No in-app "restart now" button — manual kill + reopen is sufficient and more reliable than programmatic restart on Android.
- The mock modules that already exist (`MockBleService`, `MockWifiService`, `MockDataSeeder`) are not redesigned as part of this feature — only their wiring and instantiation conditions change.
- The Dev panel does not expose individual fixture controls (e.g., "seed only teams, not matches") — the three modes are the full set.

---

## Key Decisions

- **Runtime config over compile-time for data mode:** `kUseMockData` is retired because the data mode decision is inherently a runtime dev preference, not a build artifact property. Only `kAppEnv` (which flavor of APK this is) belongs at compile time.
- **Full wipe for "Empty" mode:** We don't distinguish seeder-injected rows from manually-entered rows. A full wipe is simpler, less error-prone, and matches what a developer actually needs when testing a first-launch flow.
- **Restart to apply:** BLE service wiring happens at app construction via Riverpod. Making camera emulation live would require invalidating and re-creating those providers mid-session, risking race conditions across many watchers. A clean restart is more reliable.
- **Default = Full:** A fresh dev APK defaults to the most useful state (data + camera) so a tester can immediately explore all screens without any setup step.
- **Compile-time exclusion over runtime guard for mock code:** A runtime `if (kAppEnv.isDevBackend)` guard still compiles mock symbols into all builds. R12 requires import-level exclusion (Dart conditional imports or a stub pattern) so the `prod` binary contains no mock code. Planning should verify which pattern fits best given how mock services are currently imported.

---

## Dependencies / Assumptions

- SharedPreferences (already a transitive dependency via `shared_preferences` or equivalent) is available for persisting DevConfig. Verify the package is in `pubspec.yaml` before planning.
- `MockBleService` currently does not accept a `cameraEnabled` constructor parameter — this will need to be added.
- `main()` currently branches on `kUseMockData`; this logic is replaced entirely by the DevConfig read path.
