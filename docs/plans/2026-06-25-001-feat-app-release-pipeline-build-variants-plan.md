---
title: "feat: App release pipeline + dev/prod build variants"
type: feat
status: active
date: 2026-06-25
origin: docs/brainstorms/2026-06-25-app-release-pipeline-build-variants-requirements.md
---

# feat: App release pipeline + dev/prod build variants

## Summary

Introduce two real-backend Android build variants — **dev** (tooling compiled in) and **prod** (tooling compiled out) — distinguished by Gradle product flavors (distinct package ID, name, icon), gate dev tooling on the compile-time `APP_ENV`, then rewire the three release workflows to drop the throwaway PR build, publish dev on alpha / dev+prod on beta, and promote prod-only to stable.

---

## Problem Frame

Shipping one app beta runs the APK build three times for one installable artifact (PR throwaway debug build + beta's prod + beta's dev), and the published "developer" APK is built from `lib/main.dart` — which overrides BLE/WiFi with mocks, so it cannot talk to firmware. There is no "real backend + dev tooling" variant, and all builds share one `applicationId`/name/icon so dev and prod cannot coexist or be told apart. Full context and the settled product decisions are in the origin doc (see Sources & References).

---

## Requirements

- R1. Remove the PR-gate APK build job from both release workflows; PR gate is `CI Scripts` + `Analyze & Test` only. *(origin R1)*
- R2. alpha publishes exactly one APK: the dev variant (real backend, tooling in). *(origin R2)*
- R3. beta publishes two APKs: dev (real backend + tooling) and prod (tooling out); both SHA-256 recorded. *(origin R3)*
- R4. main promotes the **prod** APK bytes only, SHA-256 verified, no build. *(origin R4)*
- R5. The mock-backend build is never a published asset — local `just run` / tests only. *(origin R5)*
- R6. Two build-time variants on the real backend: `stage` → dev (tooling in), `prod` → prod (tooling out). *(origin R6)*
- R7. Prod build contains no code path that reveals tooling — build-time, not a runtime toggle. *(origin R7)*
- R8. dev and prod have distinct `applicationId`, app name, and launcher icon; installable side-by-side. *(origin R8)*
- R9. Reuse Flutter + Gradle build caches across jobs; capture before/after timings. *(origin R9)*

**Origin actors:** A1 (maintainer), A2 (CI / GitHub Actions)
**Origin flows:** F1 (ship a release: PR gate → alpha → beta sign-off on dev APK → promote prod)
**Origin acceptance examples:** AE1 (prod hides tooling), AE2 (dev shows tooling + real BLE), AE3 (both coexist, distinct icon/name), AE4 (main promotes prod bytes, no build), AE5 (PR runs no APK build)

---

## Scope Boundaries

- iOS build lane — unchanged / still deferred until a macOS runner exists.
- Firmware and proto pipelines — untouched.
- Version-ladder semantics (counters, tag scheme, branch model, `resolve-version.sh`) — unchanged; only what each rung *builds/promotes* changes.
- Runtime tooling toggle — rejected; tooling is compiled out of prod.
- No new tooling/diagnostics features — this re-gates and re-exposes existing `DebugPage` / `DeveloperSettingsPage`.

### Deferred to Follow-Up Work

- A separate prod-APK smoke-test before promotion (the accepted sign-off-vs-ship delta): not in this plan; add later if desired (see Key Technical Decisions).

---

## Context & Research

### Relevant Code and Patterns

- `.github/workflows/release-alpha.yml` — owns `development`. Has the `build-android` PR job (`flutter build apk --debug`) and the `alpha` push job that builds the developer APK with `flutter build apk --release --dart-define=APP_ENV=stage` (default target = `lib/main.dart` = **mock**).
- `.github/workflows/release-beta.yml` — owns `release/**`. Same `build-android` PR job; the `release-beta` push job builds prod (`-t lib/main_prod.dart --dart-define=APP_ENV=prod`) **and** dev (`--dart-define=APP_ENV=stage`, mock target), records both SHAs, uploads both. Ends with a NOTE about the shared-applicationId problem.
- `.github/workflows/release.yml` — owns `main`. Promote-only (no build). Loops `for kind in production developer`, verifies each beta APK's recorded SHA-256, renames beta→stable, uploads both.
- `android/app/build.gradle.kts` — `namespace`/`applicationId = "com.sst.sstcam"`, **no product flavors**; carries a TODO about adding `applicationIdSuffix ".dev"`. Release signing via `key.properties` (CI secret) with debug-key fallback. Note the `patchGeneratedPluginRegistrant` task keyed on `compile*JavaWithJavac` — flavors must not break its name matching.
- `lib/main.dart` — dev entry: overrides `bleServiceProvider`/`wifiServiceProvider` with mocks **and** populates `devConfigProvider` / `devReseedProvider` / `devNavigationProvider` (DebugPage + DeveloperSettingsPage). The mock backend and the tooling are fused here.
- `lib/main_prod.dart` — prod entry: bare `ProviderContainer()`, real backend, no tooling.
- `lib/core/config/dev_navigation.dart` — `devNavigationProvider` defaults to `const DevNavigation()` (null builders) → "prod builds have no debug surfaces at all"; debug page reached via long-press on About, developer settings as a Settings nav row. **This provider being populated is the tooling on/off switch.**
- `lib/core/config/env.dart` — `kAppEnv` is a compile-time const from `String.fromEnvironment('APP_ENV')` (`dev`/`stage`/`prod`); `isDevBackend` is true only for `dev`. Nothing outside this file branches on `kAppEnv` today.
- `pubspec.yaml` — `flutter_launcher_icons: ^0.14.1` (supports per-flavor configs); current single config points at `launcher/icon-dev-*`.

### Institutional Learnings

- `docs/solutions/` (CI): the three workflows are intentionally split so **main never builds** — keep promotion build-free (R4/AE4). Don't add `flutter build` to `release.yml`.
- Branch rulesets (verified via API): `Build Android APK`, `Analyze & Test (Linux)`, and `CI Scripts (shellcheck + version tests)` are required status checks on **development**, **main**, and **release-branches** rulesets. Removing the job without dropping the required check strands every PR on a check that never reports.
- Job display names are wired as ruleset contexts — renaming `Analyze & Test (Linux)` / `CI Scripts` breaks protection. Only `Build Android APK` is being removed here.

### External References

- `flutter_launcher_icons` flavor mode: per-flavor config files `flutter_launcher_icons-<flavor>.yaml` paired with Android product flavors generate per-flavor mipmaps. (Confirm exact invocation during U1.)

---

## Key Technical Decisions

- **Gradle product flavors (`dev`, `prod`) for variant identity.** Flavors give per-variant `applicationIdSuffix`, `manifestPlaceholders` (app name), and `flutter_launcher_icons` per-flavor icons in one mechanism — cleaner than a build-type `applicationIdSuffix` that would also suffix prod. Trade-off: APK output paths gain a flavor segment (`build/app/outputs/apk/<flavor>/release/`), so the workflows' `cp` paths change.
- **Two axes, always paired: Gradle flavor (identity) + `APP_ENV` Dart define (tooling).** dev APK = `--flavor dev --dart-define=APP_ENV=stage`; prod APK = `--flavor prod --dart-define=APP_ENV=prod`. `APP_ENV` is a compile-time const, so the prod build tree-shakes the tooling branch out entirely (satisfies R7 — no runtime path). Risk: the pairing lives in the build command; a mismatch is possible but the strings are fixed in the workflow.
- **Keep `lib/main.dart` as the local mock entry; gate tooling inside `lib/main_prod.dart`.** The shipped entrypoint (`main_prod.dart`) installs the `devNavigationProvider` override only when `kAppEnv == AppEnv.stage`; real backend always; no mock. Avoids a third entrypoint file. `main.dart` (mock) is never shipped (R5).
- **Promote prod-only.** `release.yml` drops the `developer` copy/verify; stable carries the prod APK alone. The maintainer signs off on the dev APK; the delta to prod is the compiled-out tooling (identical backend/wire). Accepted and documented, not mitigated with a prod smoke-test (deferred).

---

## Open Questions

### Resolved During Planning

- Where does the prod APK come from if beta tests dev? Beta builds both; main promotes the prod bytes (origin decision, R4).
- How is "prod cannot reveal tooling" guaranteed? Compile-time `APP_ENV` const → dead-code elimination of the tooling branch in prod AOT builds.
- Are rulesets affected? Yes — `Build Android APK` is a required check on 3 rulesets; U6 removes it.

### Deferred to Implementation

- Exact `flutter_launcher_icons` flavor invocation and whether per-flavor config files or a single keyed config is cleaner on 0.14.1 — settle when running it in U1.
- Whether the `patchGeneratedPluginRegistrant` task's `compile*JavaWithJavac` match needs adjustment once flavors create per-flavor compile tasks — verify during U1.
- Whether `flutter test` needs an `APP_ENV`/entry shim to exercise both tooling states, or the override-builder can be unit-tested directly (preferred) — settle in U2.
- Final Gradle cache action choice (`gradle/actions/setup-gradle` vs `actions/setup-java` cache) and measured savings — U7.

---

## High-Level Technical Design

> *This illustrates the intended approach and is directional guidance for review, not implementation specification. The implementing agent should treat it as context, not code to reproduce.*

Artifact + axis matrix:

```
variant   Gradle flavor   APP_ENV   entrypoint         backend   tooling   applicationId        published on
────────  ──────────────  ────────  ─────────────────  ────────  ────────  ───────────────────  ─────────────
dev       dev             stage     lib/main_prod.dart  real      IN        com.sst.sstcam.dev   alpha, beta
prod      prod            prod      lib/main_prod.dart  real      OUT       com.sst.sstcam       beta → main
(local)   dev (default)   dev       lib/main.dart       mock      n/a       com.sst.sstcam.dev   never (just run/tests)
```

Unit dependency order:

```
U1 (flavors/icons) ─┐
U2 (tooling gate) ──┼─► U3 (alpha wf) ──► U7 (cache)
                    └─► U4 (beta wf) ───► U5 (promote prod-only)
                                          U6 (rulesets) lands with U3+U4 merge
```

---

## Implementation Units

### U1. Android product flavors with distinct ID, name, and icon

**Goal:** Add `dev` and `prod` Gradle product flavors so the two variants get a distinct `applicationId` (dev suffixed `.dev`), distinct app name, and distinct launcher icon, and can coexist on one device.

**Requirements:** R8

**Dependencies:** None

**Files:**
- Modify: `android/app/build.gradle.kts` (add `flavorDimensions` + `productFlavors { dev { applicationIdSuffix=".dev"; manifestPlaceholders["appName"]="SST Cam Dev" } prod { manifestPlaceholders["appName"]="SST Cam" } }`; remove the stale shared-applicationId TODO)
- Modify: `android/app/src/main/AndroidManifest.xml` (`android:label="${appName}"`)
- Modify: `pubspec.yaml` (flutter_launcher_icons flavor config) and add per-flavor icon configs/assets under `launcher/` (dev vs prod icon)
- Create: per-flavor mipmap resources generated by `flutter_launcher_icons` (e.g. `android/app/src/dev/res/...`, `android/app/src/prod/res/...`)

**Approach:**
- Two flavors in one dimension (e.g. `app`). `manifestPlaceholders` carries the label so the manifest stays flavor-agnostic.
- Generate per-flavor icons with `flutter_launcher_icons` flavor mode; the existing `icon-dev-*` assets serve the dev flavor, add a distinct prod icon.
- Confirm `patchGeneratedPluginRegistrant` still binds to the now per-flavor `compile<Flavor>ReleaseJavaWithJavac` tasks (its `startsWith("compile") && endsWith("JavaWithJavac")` match should still hold — verify).

**Patterns to follow:** Standard Flutter Android flavor setup; keep the `key.properties` debug-fallback signing in `buildTypes.release` unchanged.

**Test scenarios:**
- Covers AE3. Happy path: `flutter build apk --flavor dev` and `--flavor prod` each produce an APK; `aapt`/`apkanalyzer` (or gradle output) shows applicationId `com.sst.sstcam.dev` vs `com.sst.sstcam`, labels `SST Cam Dev` vs `SST Cam`, and different launcher icon resources.
- Covers AE3. Integration (manual/device): install both APKs on one device → two distinct launcher entries, neither overwrites the other.
- Edge case: a build with no `--flavor` fails fast (or defaults predictably) — document the expected behavior so local `just run` still works.

**Verification:** Both flavor APKs build; metadata differs as above; both install side-by-side.

---

### U2. Decouple dev tooling from the mock backend; gate on build-time `APP_ENV`

**Goal:** Make the shipped entrypoint install the `devNavigationProvider` tooling override only when `kAppEnv == AppEnv.stage`, on the real backend, with no mock — so the dev APK has tooling + real BLE and the prod APK has neither tooling nor any path to it.

**Requirements:** R6, R7, R5

**Dependencies:** None

**Files:**
- Modify: `lib/main_prod.dart` (conditionally add the `devNavigationProvider` override — `DebugPage` + `DeveloperSettingsPage` — when `kAppEnv == AppEnv.stage`; real backend always; no mock services)
- Modify (optional): `lib/core/config/env.dart` (add an `isDevTooling`/`showDevTooling` getter for a single readable gate, e.g. `this == AppEnv.stage`)
- Create: `test/core/config/entry_tooling_gate_test.dart`
- Possibly modify: a small extractable helper (e.g. `lib/core/config/shipped_overrides.dart`) so the override list is unit-testable without launching `runApp`

**Approach:**
- Extract "build the Riverpod overrides for a shipped build" into a pure function taking an `AppEnv` (or reading `kAppEnv`), returning the overrides list: `stage` → `[devNavigationProvider.overrideWithValue(DevNavigation(debugPage:…, developerSettings:…))]`; `prod` → `[]`. Real BLE/WiFi providers are left at their defaults (the real impls) in both.
- `main_prod.dart` consumes that function. `main.dart` is untouched (mock, local-only).
- Tooling code is referenced only behind the compile-time `kAppEnv` branch → tree-shaken from prod AOT (R7).

**Execution note:** Implement the override-builder test-first — it is the behavioral core of the variant split.

**Patterns to follow:** `lib/main.dart`'s existing `devNavigationProvider.overrideWithValue(DevNavigation(debugPage: …, developerSettings: …))` wiring; reuse the same page builders without the mock/seed overrides.

**Test scenarios:**
- Covers AE2. Happy path: override-builder with `AppEnv.stage` returns a list whose `devNavigationProvider` value has non-null `debugPage` and `developerSettings`, and leaves `bleServiceProvider` at its real default (not a mock type).
- Covers AE1. Happy path: override-builder with `AppEnv.prod` returns no `devNavigationProvider` override → `devNavigationProvider` resolves to the default `const DevNavigation()` (null builders).
- Edge case: `AppEnv.dev` (mock, local) is out of this function's scope — assert the function is only invoked from the shipped entry, or treat `dev` same as `stage` for tooling and document it.

**Verification:** Tests pass; a `--dart-define=APP_ENV=prod` build exposes no debug/developer surfaces; a `stage` build does and reaches real BLE.

---

### U3. release-alpha.yml — drop PR build; alpha builds the dev-flavor real-backend APK

**Goal:** Remove the throwaway PR `build-android` job and make the alpha push job build the dev variant from the real-backend entrypoint + `dev` flavor.

**Requirements:** R1, R2

**Dependencies:** U1, U2

**Files:**
- Modify: `.github/workflows/release-alpha.yml` (delete the `build-android` job; change the alpha build step to `flutter build apk --flavor dev -t lib/main_prod.dart --dart-define=APP_ENV=stage`; update the rename `cp` path to `build/app/outputs/apk/dev/release/app-dev-release.apk`)

**Approach:**
- Keep `version-script` and `analyze-and-test` PR jobs as the gate. Removing `build-android` removes the only PR-time APK build.
- The published asset name stays `sst-cam-app-<tag>-developer.apk` (consumers/promotion naming unchanged), now built from the real backend.

**Patterns to follow:** Existing alpha job steps (proto-gen, keystore materialize) stay; only the build target/flavor/output path change.

**Test scenarios:**
- Test expectation: none (CI workflow config). Covered by `CI Scripts` actionlint/shellcheck in-PR and by the first alpha run post-merge.
- Verification scenario: a PR into `development` shows only `CI Scripts` + `Analyze & Test` — no `Build Android APK` (AE5).

**Verification:** actionlint passes; a `development` push produces one `…-developer.apk` from the real backend.

---

### U4. release-beta.yml — drop PR build; build dev + prod from flavors; record both SHAs

**Goal:** Remove the PR `build-android` job and rebuild the beta push job to produce the dev (flavor `dev`, stage) and prod (flavor `prod`, prod) APKs from the real backend, recording both SHA-256 digests.

**Requirements:** R1, R3

**Dependencies:** U1, U2

**Files:**
- Modify: `.github/workflows/release-beta.yml` (delete `build-android` job; production step → `flutter build apk --flavor prod -t lib/main_prod.dart --dart-define=APP_ENV=prod`; developer step → `flutter build apk --flavor dev -t lib/main_prod.dart --dart-define=APP_ENV=stage`; update both `cp` paths to the flavored output dirs; remove the trailing shared-applicationId NOTE comment now that U1 solves it)

**Approach:**
- Keep the SHA-256 recording block and the contractual notes line format (`sha256: <64hex>  sst-cam-app-<tag>-<kind>.apk`) — `release.yml` still parses it for the prod asset.
- Asset names unchanged (`-production.apk`, `-developer.apk`).

**Patterns to follow:** Existing beta SHA-record + `gh release create` block; only build invocations and `cp` paths change.

**Test scenarios:**
- Test expectation: none (CI workflow config). Covered by `CI Scripts` and the first beta run.
- Verification scenario: a `release/*` push publishes two real-backend APKs; the dev one shows tooling on-device, the prod one does not (AE1/AE2).

**Verification:** actionlint passes; beta release carries both APKs with recorded SHAs.

---

### U5. release.yml — promote the prod APK only

**Goal:** Stop copying the developer APK to stable; promote and verify the prod APK alone, keeping main build-free.

**Requirements:** R4

**Dependencies:** U4

**Files:**
- Modify: `.github/workflows/release.yml` (change the `for kind in production developer` loop to `production` only; upload only `sst-cam-app-<tag>-production.apk`; update the summary text)

**Approach:**
- Keep the fail-closed SHA-256 verification against the beta notes for the prod asset. Stable Release carries the prod APK only (dev tooling never ships to stable).
- No `flutter build` added — the no-build-on-main guarantee is preserved (AE4).

**Patterns to follow:** Existing verify-then-`mv`-then-`gh release upload` flow; just collapse to one asset.

**Test scenarios:**
- Test expectation: none (CI workflow config).
- Covers AE4. Verification scenario: on `release/* → main` merge, the stable prod asset's SHA-256 equals the beta prod SHA-256 and no build job ran; no `…-developer.apk` appears on the stable Release.
- Error path (manual reasoning): if the beta prod asset or its recorded digest is missing, promotion fails closed (existing behavior retained).

**Verification:** A promotion run publishes only the prod APK, byte-verified, with no build step.

---

### U6. Drop `Build Android APK` from the branch rulesets

**Goal:** Remove the now-deleted `Build Android APK` required status check from the development, main, and release-branches rulesets so PRs don't hang waiting on a job that no longer runs.

**Requirements:** R1

**Dependencies:** U3, U4 (land together so the required check is removed as the job disappears)

**Files:**
- No repo files — GitHub ruleset config via `gh api` (PATCH `repos/ScoutSportTechnology/sst-cam-app/rulesets/<id>` for ids 17877167 development, 17877168 main, 17877170 release-branches), removing the `Build Android APK` context while keeping `Analyze & Test (Linux)` and `CI Scripts (shellcheck + version tests)`.
- Update: `docs/ci/rulesets.md` (reflect the new required-check set)

**Approach:**
- A maintainer/admin action (org admin). Sequence it with the U3/U4 merge: a PR opened before the ruleset update would wait on the missing check.
- Verify post-change that the three rulesets list exactly the two remaining contexts.

**Test scenarios:**
- Test expectation: none (infra config). Verification only.

**Verification:** `gh api .../rulesets/<id>` for all three shows required checks = {`Analyze & Test (Linux)`, `CI Scripts (shellcheck + version tests)`}; a fresh PR is mergeable once those two pass.

---

### U7. Build-cache tuning on the release build jobs

**Goal:** Reduce build wall-clock by reusing Flutter SDK/pub and Gradle caches in the alpha and beta build jobs, and record the before/after timing.

**Requirements:** R9

**Dependencies:** U3, U4

**Files:**
- Modify: `.github/workflows/release-alpha.yml`, `.github/workflows/release-beta.yml` (add Gradle caching — e.g. `gradle/actions/setup-gradle` or `actions/setup-java` `cache: gradle` — alongside the existing `subosito/flutter-action` `cache: true`)

**Approach:**
- `flutter-action` already caches the SDK; add Gradle dependency/build caching, the largest Android build cost. Capture one cold run and one warm run to quantify (origin R9 asks for the measurement, not a target).
- Pure CI performance change — no artifact contents change.

**Test scenarios:**
- Test expectation: none (CI config + measurement).
- Verification scenario: a second consecutive build job logs Gradle cache hits and a reduced build-step duration vs the cold run; record both numbers.

**Verification:** Cache hits appear in the job log; warm-run build time is recorded lower than the cold run.

---

## System-Wide Impact

- **Interaction graph:** The three release workflows form a chain (alpha/beta build → main promotes). U4's asset set feeds U5's promotion; U3/U4's job removal feeds U6's ruleset change. Changing one without the others breaks the chain (e.g. drop the job but not the required check → PRs hang).
- **Error propagation:** Promotion (U5) must stay fail-closed on a missing/mismatched prod digest. Beta build failure (U4) leaves `release/*` without a tag — recoverable via re-dispatch; never reaches main.
- **State lifecycle risks:** The flavor change (U1) alters APK output paths — every `cp` in U3/U4 must move in lockstep or the release upload fails on a missing file.
- **API surface parity:** Asset *names* (`-developer.apk`, `-production.apk`) are an implicit contract between beta (U4) and promote (U5); keep them stable even as the build inputs change.
- **Unchanged invariants:** `resolve-version.sh` and the alpha/beta/stable tag ladder are untouched; `main` still runs no build (R4/AE4); `lib/main.dart` mock entry and the `key.properties` signing fallback are unchanged.

---

## Risks & Dependencies

| Risk | Mitigation |
|------|------------|
| Drop `build-android` job but leave the required check → all PRs hang | U6 removes the check from all 3 rulesets, sequenced with the U3/U4 merge; verify post-change. |
| Flavor output-path change missed in a workflow `cp` → release upload fails | U1 lands first; U3/U4 update every `cp` to the flavored path; actionlint + first run catch it. |
| dev/prod axis mismatch (`--flavor` vs `APP_ENV`) ships tooling in prod | Pairing fixed in workflow strings; U2 gate is compile-time so prod tree-shakes tooling regardless of flavor; AE1 verifies on-device. |
| `flutter_launcher_icons` flavor mode behaves differently on 0.14.1 than assumed | Treated as a deferred-to-implementation detail in U1; fall back to manual per-flavor mipmap dirs if needed. |
| Sign-off (dev) ≠ shipped (prod) binary | Accepted, documented; optional prod smoke-test deferred to follow-up. |
| `patchGeneratedPluginRegistrant` task name match breaks under flavored compile tasks | U1 verifies the task still binds; adjust the matcher if flavors rename the compile tasks. |

---

## Documentation / Operational Notes

- Update `docs/ci/rulesets.md` (U6) and any CLAUDE.md / AGENTS.md lines describing the "developer APK = mock" and "two APKs from one flavor" model — they now describe real-backend variants from two Gradle flavors with prod-only promotion.
- Operational sequencing: land U1+U2 (app) → U3+U4 (workflows) → U6 (rulesets, with the merge) → U5 (promote) → U7 (cache). U5 can land with U4; U6 is the one human/admin step.

---

## Sources & References

- **Origin document:** [docs/brainstorms/2026-06-25-app-release-pipeline-build-variants-requirements.md](docs/brainstorms/2026-06-25-app-release-pipeline-build-variants-requirements.md)
- Related code: `.github/workflows/release-alpha.yml`, `.github/workflows/release-beta.yml`, `.github/workflows/release.yml`, `android/app/build.gradle.kts`, `lib/main.dart`, `lib/main_prod.dart`, `lib/core/config/env.dart`, `lib/core/config/dev_navigation.dart`
- Branch rulesets: development `17877167`, main `17877168`, release-branches `17877170`
