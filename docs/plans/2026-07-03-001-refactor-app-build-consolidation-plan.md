---
title: "refactor: Consolidate app to a single entry + three env-mapped flavors"
type: refactor
status: active
date: 2026-07-03
---

# refactor: Consolidate app to a single entry + three env-mapped flavors

## Summary

Collapse the app's two entry points (`lib/main.dart` mock + `lib/main_prod.dart` real) into a **single `lib/main.dart`** that selects backend + tooling from the compile-time `kAppEnv` const, and give each environment its **own Gradle flavor + launcher icon** (`dev` / `stage` / `prod`). Result: one bootstrap file, three unambiguous, visually-distinct builds — `dev` (debug, mock), `stage` (release, real backend + dev tools), `prod` (release, real backend, shipped) — with the mock code tree-shaken out of the two shipped envs.

---

## Problem Frame

Today three orthogonal axes (build **mode** debug/profile/release, Gradle **flavor** dev/prod, **env** dev/stage/prod via `APP_ENV`) combine ad-hoc, and the backend is chosen by *which entry file* is compiled (`main.dart` = mock, `main_prod.dart` = real) rather than by a flag. This produced real confusion and bugs this session: a `stage` build wears the `dev` flavor's icon (indistinguishable installed), and the mock build silently targets the wrong device path. Maintaining two bootstrap files that must stay in lock-step (logging init, splash, error handling) is wasteful. The env system already models the three environments correctly (`kAppEnv`, `isDevBackend`, `showsDevTooling`, `shippedOverrides`) — the entry points just predate it.

---

## Requirements

- R1. One entry point (`lib/main.dart`); delete `lib/main_prod.dart`. Backend + tooling chosen from `kAppEnv`.
- R2. The mock backend + dev seeding code must be **absent from `stage` and `prod` release binaries** (tree-shaken), preserving today's "mock never ships" guarantee.
- R3. Three Gradle flavors — `dev`, `stage`, `prod` — each with a distinct `applicationId` suffix, app name, and launcher icon, so an installed build is identifiable at a glance.
- R4. Three canonical build recipes in the justfile map 1:1 to the envs: `dev`=debug+`APP_ENV=dev`(mock), `stage`=release+`APP_ENV=stage`(real+tools), `prod`=release+`APP_ENV=prod`(shipped).
- R5. CI (`release-alpha.yml`, `release-beta.yml`, `release.yml`) keeps producing the same **assets by KIND** (`developer`/`production`) and the stable-promotion contract is unbroken.
- R6. The mock-on-physical-phone fixes already landed this session (non-fatal seed report + `kDefaultUserId` base seed) are preserved.
- R7. Docs (`CLAUDE.md`, README build section) describe the single-entry + three-flavor model.

---

## Scope Boundaries

- Not changing the CI **maturity ladder** semantics (alpha→beta→stable, branch-driven versioning) — only the build invocations' entry/flavor.
- Not introducing a `profile`-mode build recipe. `profile` stays an orthogonal, on-demand perf mode; it is **not** an env.
- Not changing `applicationId` for `prod` (`com.sst.sstcam`) — the shipped identity is stable. Only `dev`/`stage` carry suffixes.
- Not redesigning the icons themselves — this plan wires a `stage` icon slot; the actual `stage` 1024px art is an input (a badged variant of the dev icon is acceptable).
- Not touching the firmware or proto.

### Deferred to Follow-Up Work

- Fixing the remaining pre-existing test failures unrelated to seeding (e.g. `video_player` platform `UnimplementedError`, `download_client`): separate cleanup.

---

## Context & Research

### Relevant Code and Patterns

- `lib/main.dart` — current **dev** entry: `LogService.attach()`+`wireLogging()`, `DevConfig.load`, `AppDatabase`, `applySeedData`, mock BLE/WiFi Riverpod overrides, dev navigation, `UncontrolledProviderScope`.
- `lib/main_prod.dart` — current **shipped** entry: `shippedOverrides(kAppEnv)` only; real backend.
- `lib/core/config/env.dart` — `enum AppEnv {dev,stage,prod}`, `kAppEnv` (compile-time const from `APP_ENV`), `isDevBackend` (== dev), `showsDevTooling` (!= prod). **This is the seam the single entry branches on.**
- `lib/core/config/shipped_overrides.dart` — `shippedOverrides(env)`: empty for prod (tree-shaken), dev-nav for stage/dev. The proven const-guard tree-shaking pattern to mirror for the mock.
- `lib/mock/emulator/{mock_ble_service,mock_wifi_service}.dart`, `lib/mock/internal/mock_data_service.dart` — the mock wiring + `applySeedData` that must sit behind the `isDevBackend` guard so release tree-shakes it.
- `android/app/build.gradle.kts` — `flavorDimensions += "variant"`, `productFlavors { dev {.dev suffix, "SST Cam Dev"}, prod {"SST Cam"} }`.
- `flutter_launcher_icons-dev.yaml`, `flutter_launcher_icons-prod.yaml` — per-flavor icon configs; `just gen-icons` runs `dart run flutter_launcher_icons` into `android/app/src/<flavor>/res`.
- `justfile` — `run`/`build-android` (mock, `main.dart`), `build-android-dev` (`--flavor dev -t main_prod.dart APP_ENV=stage` — the mislabeled "stage" build), `build-android-prod`, `run-phone`/`deploy-phone` (`--flavor prod -t main_prod.dart APP_ENV=prod`), `version_defines`, `gen-icons`.
- `.github/workflows/release-alpha.yml:300`, `release-beta.yml:307/317` — build invocations (flavor + `-t lib/main_prod.dart` + `APP_ENV`); beta `src` path is `app-${FLAVOR}-release.apk`, copied to `sst-cam-app-<tag>-${KIND}.apk`.
- `.github/workflows/release.yml:121-147` — promotes by **KIND** (`developer`/`production`), sha256-verified byte copy. **KIND-keyed, so a flavor rename does not touch it.**

### Institutional Learnings

- `docs/solutions/` has no doc on this; capture one at execution end (single-entry + tree-shake guarantee is reusable knowledge).
- Session learning (this refactor's origin): mock seeding is emulator-shaped and FK-fragile on a fresh DB — the base-user seed + non-fatal report fixes (R6) must ride along.

---

## Key Technical Decisions

- **Branch on `kAppEnv.isDevBackend`, not on a separate `BACKEND` flag.** The env const already encodes exactly the dev/stage/prod split and is compile-time; reusing it avoids a second source of truth and inherits the existing tree-shaking guarantee.
- **Tree-shaking is the "mock never ships" mechanism.** `if (kAppEnv.isDevBackend) { await _bootstrapDev(...); }` with mock/seed wiring only reachable inside that branch → a `stage`/`prod` build (const-false) drops the branch and its exclusive imports. Mirrors `shippedOverrides` / `showsDevTooling` (already relied on for tooling). Verified in U5, not assumed.
- **Mode is orthogonal to env/flavor.** The three recipes pick a mode (dev→debug, stage/prod→release) but `debug`/`profile`/`release` remain available for any env when needed (e.g. profiling stage). Documented, not enforced in code.
- **`stage` needs a real Gradle flavor** (not just `APP_ENV=stage`) because a distinct launcher icon is per-flavor on Android (`src/<flavor>/res`). This is the sole reason `dev`≠`stage` at the flavor layer.
- **CI developer APK moves from `dev` flavor to `stage` flavor.** Asset name stays `…-developer.apk` (KIND-keyed), so `release.yml` promotion is unaffected; only the beta matrix's flavor/app_env mapping + the `src` path (auto-follows `${FLAVOR}`) change.

---

## Open Questions

### Resolved During Planning

- Does a single entry keep mock out of release? Yes — compile-time const branch + Dart tree-shaking, same mechanism `shippedOverrides` already uses. Confirmed by reading `env.dart`/`shipped_overrides.dart`.
- Does renaming the developer flavor break stable promotion? No — `release.yml` copies by KIND, not flavor.

### Deferred to Implementation

- Exact structure of the dev-bootstrap helper (one `_bootstrapDev()` vs inline) — decide when editing, keeping all mock/seed references inside the guarded branch.
- Whether `applicationIdSuffix` for stage is `.stage` (recommended) — confirm no collision with any store listing.
- The `stage` icon art file name/path under `launcher/` — supply or badge from dev at execution.

---

## Implementation Units

### U1. Single entry point — branch on `kAppEnv`

**Goal:** One `lib/main.dart` that boots any env; delete `lib/main_prod.dart`.

**Requirements:** R1, R2, R6

**Dependencies:** None

**Files:**
- Modify: `lib/main.dart` (becomes the sole entry; add env branch)
- Delete: `lib/main_prod.dart`
- Modify (imports/guarding only, if needed): `lib/core/config/shipped_overrides.dart`
- Test: `test/app_bootstrap_test.dart` (new — env-branch selection)

**Approach:**
- `main()`: always `WidgetsFlutterBinding.ensureInitialized()`, splash preserve, `LogService.attach()`+`wireLogging()`, startup `Logger('App').info(...)`.
- Build the `ProviderContainer` overrides by env:
  - `kAppEnv.isDevBackend` (dev): run the dev bootstrap — `DevConfig.load` (fallback on failure), `AppDatabase`, `applySeedData`, mock BLE/WiFi overrides, dev-navigation override. All mock/seed symbols referenced **only** here.
  - else (stage/prod): `shippedOverrides(kAppEnv)` (real backend; dev-nav only for stage).
- Keep the R6 fixes: `applySeedData` failure is a non-fatal `debugPrint`; `MockDataSeeder.seed()` seeds `kDefaultUserId` first.
- `FlutterNativeSplash.remove()` at the end for all envs.

**Execution note:** Characterization-first — before deleting `main_prod.dart`, confirm the stage/prod branch produces the same override set `main_prod.dart` did (`shippedOverrides`).

**Patterns to follow:** `shippedOverrides()` const-guard; existing `main.dart` dev wiring.

**Test scenarios:**
- Happy path: with `APP_ENV=dev`, the container installs mock BLE/WiFi overrides + dev nav.
- Happy path: with `APP_ENV=stage`, overrides equal `shippedOverrides(AppEnv.stage)` (dev nav, real backend — no mock override present).
- Happy path: with `APP_ENV=prod`, overrides are empty (real backend, no tooling).
- Edge case: `DevConfig.load` throws → dev bootstrap still completes with defaults (no crash).
- Error path: a seed failure logs and does not throw (R6 regression guard).

**Verification:** App boots in all three envs; `grep` shows no `lib/main_prod.dart` references remain; the dev-only imports appear only inside the guarded branch.

### U2. Add `stage` Gradle flavor + launcher icon

**Goal:** Three flavors (`dev`/`stage`/`prod`), each with its own id-suffix, name, and icon.

**Requirements:** R3

**Dependencies:** None

**Files:**
- Modify: `android/app/build.gradle.kts` (add `stage` product flavor)
- Create: `flutter_launcher_icons-stage.yaml`
- Create: `launcher/icon-stage-1024.png` (stage art — badged dev variant acceptable)
- Modify: `justfile` (`gen-icons` generates all three flavors)

**Approach:**
- `productFlavors { create("stage") { dimension = "variant"; applicationIdSuffix = ".stage"; manifestPlaceholders["appName"] = "SST Cam Stage" } }`.
- `flutter_launcher_icons-stage.yaml` mirrors the dev config with `image_path: "launcher/icon-stage-1024.png"` generating into `android/app/src/stage/res`.
- `gen-icons` runs the generator for all three flavor configs.

**Patterns to follow:** existing `dev` flavor block + `flutter_launcher_icons-dev.yaml`.

**Test scenarios:** `Test expectation: none — build-config + assets, no runtime behavior.` (Verified by building each flavor in U5.)

**Verification:** `just gen-icons` emits `src/{dev,stage,prod}/res`; a `stage` APK installs as `com.sst.sstcam.stage`, name "SST Cam Stage", distinct icon.

### U3. Justfile — three canonical build recipes on the single entry

**Goal:** `dev`/`stage`/`prod` recipes map to (mode, flavor, `APP_ENV`); all pass `version_defines`; all target `lib/main.dart`.

**Requirements:** R4

**Dependencies:** U1, U2

**Files:**
- Modify: `justfile` (`run`, `build-android*`, `run-phone`, `deploy-phone`, `gen-icons`)

**Approach:**
- `dev`: debug, `--flavor dev`, `--dart-define=APP_ENV=dev`, `lib/main.dart` (mock). (`run`, `build-android`.)
- `stage`: release, `--flavor stage`, `--dart-define=APP_ENV=stage` (real backend + tools). (New `build-android-stage`; `run-phone`/`deploy-phone` default here since on-device dev testing wants tools.)
- `prod`: release, `--flavor prod`, `--dart-define=APP_ENV=prod` (shipped). (`build-android-prod`.)
- Drop all `-t lib/main_prod.dart` (single entry is the default target). Keep `{{version_defines}}` on every build/run recipe (fixes the earlier missing-version issue).

**Patterns to follow:** existing recipe shapes + `version_defines`.

**Test scenarios:** `Test expectation: none — build tooling.` (Exercised by U5 building each recipe.)

**Verification:** `just build-android` → mock dev APK; `just build-android-stage` → real+tools stage APK; `just build-android-prod` → shipped prod APK; each shows the right icon/name and, on device, the right backend.

### U4. CI workflows — single entry + `stage` flavor for the developer APK

**Goal:** alpha/beta build the developer APK as `--flavor stage --dart-define=APP_ENV=stage` on `lib/main.dart`; stable promotion unchanged.

**Requirements:** R5

**Dependencies:** U1, U2

**Files:**
- Modify: `.github/workflows/release-alpha.yml` (developer build step)
- Modify: `.github/workflows/release-beta.yml` (matrix: `developer`→`{flavor: stage, app_env: stage}`, `production`→`{flavor: prod, app_env: prod}`; drop `-t lib/main_prod.dart`; `src` path auto-follows `${FLAVOR}`)
- Verify (no change expected): `.github/workflows/release.yml` (KIND-keyed promotion)

**Approach:**
- Replace `--flavor dev -t lib/main_prod.dart --dart-define=APP_ENV=stage` with `--flavor stage --dart-define=APP_ENV=stage` (target defaults to `lib/main.dart`).
- Ensure `gen-icons` (or the generator step) runs for `stage` before the flavored build so `src/stage/res` exists.
- Confirm the beta `src="…/apk/${FLAVOR}/release/app-${FLAVOR}-release.apk"` resolves for `stage`, and the asset name stays `sst-cam-app-<tag>-developer.apk`.

**Approach — verification of `release.yml`:** read the copy step; confirm it references `developer`/`production` KIND strings (not `dev`/`prod` flavor), so no edit is required.

**Test scenarios:**
- Integration (CI dry-run on a branch): pushing a `feat:` to a throwaway `development`-like branch produces a `…-developer.apk` from the `stage` flavor with `APP_ENV=stage`.
- Integration: a beta build emits both `…-developer.apk` (stage) and `…-production.apk` (prod); `release.yml` promotion finds both by KIND.

**Verification:** alpha/beta workflows green on a test branch; produced developer APK is `com.sst.sstcam.stage`; promotion path unbroken.

### U5. Verify the mock is tree-shaken from stage/prod

**Goal:** Prove no mock/seed code ships in the release stage/prod binaries.

**Requirements:** R2

**Dependencies:** U1, U3

**Files:**
- Create: `test/env_gating_test.dart` (compile-time gating assertions)
- (Manual/CI check, no source file) release-APK symbol scan

**Approach:**
- Unit: assert `AppEnv.prod.isDevBackend == false` and `AppEnv.prod.showsDevTooling == false`, and that the single-entry override builder returns an empty/real-only set for prod (the guard that gates the mock).
- Build-artifact check: build the `prod` release APK and scan for mock symbols — e.g. `MockBleService`, `MockDataSeeder` — expecting **absent**. Compare `dev` (present) vs `prod` (absent) to prove the shake. Document the command/result in the execution notes (not a committed shell recipe).

**Test scenarios:**
- Happy path: `prod` env gating flags are both false (backend real, tooling off).
- Integration: `prod` release APK contains no `Mock*`/seed symbols; `dev` debug APK does. (Manual/CI artifact scan.)

**Verification:** prod APK symbol scan finds no mock; env gating test green.

### U6. Docs — single-entry + three-flavor model

**Goal:** `CLAUDE.md` and README reflect the new build model so the confusion this refactor resolves does not recur.

**Requirements:** R7

**Dependencies:** U1–U4

**Files:**
- Modify: `CLAUDE.md` ("Entry points & backends", commands, the mode×env×flavor explanation)
- Modify: `README.md` (build section, if it lists entries/flavors)

**Approach:**
- Replace the two-entry description with the single-entry `kAppEnv` branch; state the three canonical builds table (mode/flavor/env/backend/tools); note mode is orthogonal (profile available on demand); reaffirm mock-never-ships via tree-shaking.

**Test scenarios:** `Test expectation: none — documentation.`

**Verification:** Docs describe one entry + three flavors; no stale `main_prod.dart` references.

---

## System-Wide Impact

- **Interaction graph:** the entry `main()` is the root; changing it touches every launch path. Riverpod override assembly moves from two files into one env-branch.
- **Error propagation:** the dev bootstrap's seed failure stays non-fatal (R6); stage/prod have no seed path.
- **State lifecycle risks:** none new — DB/seed only runs in dev; stage/prod untouched.
- **API surface parity:** the `APP_ENV` dart-define is now consumed by the single entry for backend selection (previously only tooling). Every build must set `APP_ENV` (default `dev` → mock) — justfile + CI updated to always pass it.
- **Integration coverage:** the CI flavor rename (dev→stage for developer APK) is the cross-system seam; U4's branch dry-run proves it before merge.
- **Unchanged invariants:** `prod` `applicationId` (`com.sst.sstcam`), the alpha/beta/stable ladder + versioning math, KIND-keyed stable promotion, `shippedOverrides` behavior.

---

## Risks & Dependencies

| Risk | Mitigation |
|------|------------|
| Mock code not tree-shaken → ships in stage/prod (R2 breach) | Guard all mock/seed refs inside the `isDevBackend` const branch; U5 scans the prod APK for `Mock*` symbols before trusting it |
| CI flavor rename breaks beta build or stable promotion | Promotion is KIND-keyed (unaffected); beta `src` auto-follows `${FLAVOR}`; U4 dry-runs alpha+beta on a throwaway branch before merging |
| `stage` icon assets missing → flavored build fails | `gen-icons` runs for all three flavors in justfile + CI before the build; supply `icon-stage-1024.png` (badged dev art) in U2 |
| Existing `dev`-flavor installs diverge from new `stage` package id | Accept — reinstall; only affects local/dev testers, not shipped `prod` |
| Single entry regresses a shipped path silently | U1 characterization test asserts stage/prod override sets match the old `main_prod.dart` output |

---

## Documentation / Operational Notes

- After merge, capture a `docs/solutions/` note: "single Flutter entry with compile-time env branch keeps mock out of release via tree-shaking" — reusable pattern.
- Testers must reinstall the developer build once (package id `com.sst.sstcam.dev` → `com.sst.sstcam.stage`).

---

## Sources & References

- Entry/env seam: `lib/core/config/env.dart`, `lib/core/config/shipped_overrides.dart`, `lib/main.dart`, `lib/main_prod.dart`
- Flavors/icons: `android/app/build.gradle.kts`, `flutter_launcher_icons-{dev,prod}.yaml`, `justfile` (`gen-icons`)
- CI: `.github/workflows/release-alpha.yml`, `release-beta.yml`, `release.yml`
- Session origin: mock-on-phone fixes (commit `cecb140`), build-axis confusion thread
