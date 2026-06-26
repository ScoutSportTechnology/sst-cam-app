---
date: 2026-06-25
topic: app-release-pipeline-build-variants
---

# App Release Pipeline + Build Variants

## Summary

Cut wasted CI builds in the app release pipeline and replace the broken mock "developer" APK with a real-backend **dev** variant (tooling compiled in) alongside a **prod** variant (tooling compiled out), shipped as two distinguishable, side-by-side-installable apps.

---

## Problem Frame

Shipping one app beta today runs the APK build three times for one installable artifact. The PR gate compiles a throwaway `flutter build apk --debug` (~361s) purely to prove it compiles, then the merge rebuilds from scratch (~568s) — the two share nothing. The merge build also produces **two** release APKs: a `production` (real backend) and a `developer` one — but the developer APK is built from the `lib/main.dart` entrypoint, which overrides the BLE/WiFi providers with **mocks**. So the published "developer" APK cannot talk to real firmware at all; on a real Orin Nano you must install the production APK. The mock APK is a ~411 MB asset nobody installs for hardware work.

The deeper gap: "real backend **with** dev tooling" is not a buildable variant. `lib/core/config/env.dart` gates `isDevBackend` only for the `dev` (mock) env, and nothing in the app branches on `APP_ENV` for tooling — the dev tooling (diagnostics, debug pages, dev navigation, seeding) is coupled to the mock entrypoint. And every build shares one `applicationId` (`com.sst.sstcam`), one label (`SST Cam`), and one launcher icon — `android/app/build.gradle.kts:73` even notes the stage/prod `applicationIdSuffix` was deferred — so two variants cannot coexist on one device or be told apart.

---

## Actors

- A1. Maintainer: cuts releases, signs off betas on real hardware, promotes to stable.
- A2. CI (GitHub Actions): runs the branch-scoped release workflows.

---

## Key Flows

- F1. Ship a release
  - **Trigger:** merge a PR into `development`, then cut/iterate `release/X.Y.Z`, then merge `release/* → main`.
  - **Actors:** A1, A2.
  - **Steps:** PR gate runs analyze + test only (no APK build) → merge to `development` builds the **dev** APK (alpha) → push to `release/*` builds **dev + prod** APKs (beta) → maintainer installs the **dev** APK on the Jetson rig and signs off → merge to `main` promotes the **prod** APK bytes.
  - **Outcome:** stable release carries one prod APK, byte-identical to the beta's prod APK; `main` ran no build.
  - **Covered by:** R1, R2, R3, R4.

Artifact per rung:

```
rung      branch         published APK(s)              tooling   backend
────────  ─────────────  ───────────────────────────  ────────  ───────
alpha     development    dev                           in        real
beta      release/X.Y.Z  dev  +  prod                  in / out  real
stable    main           prod  (promoted bytes)        out       real
(local)   —              mock (just run / tests only)  —         mock
```

---

## Requirements

**CI pipeline**
- R1. Remove the PR-gate APK build job (`build-android`, `flutter build apk --debug`) from `.github/workflows/release-alpha.yml` and `release-beta.yml`. The PR gate is `ci-scripts` + `Analyze & Test` only.
- R2. On push to `development`, the alpha release publishes exactly **one** APK: the **dev** variant (real backend, tooling compiled in).
- R3. On push to `release/*`, the beta release publishes **two** APKs: the **dev** variant and the **prod** variant (both real backend). Each APK's SHA-256 is recorded in the release notes (as today).
- R4. On merge to `main`, the stable release promotes the **prod** APK bytes byte-for-byte (SHA-256 verified) and runs **no** Flutter/Gradle build. Stable carries the prod APK only.
- R5. The mock-backend build is never a published release asset — it exists only for local `just run` and tests.

**App build variants**
- R6. Two build-time variants selected by the `APP_ENV` flag, both on the **real backend** entrypoint: `stage` → **dev** (tooling compiled in); `prod` → **prod** (tooling compiled out).
- R7. Dev tooling (diagnostics, debug pages, dev navigation, seeding) is gated on the build-time flag and decoupled from the mock-backend entrypoint. A **prod** build contains no code path that reveals tooling — it is not a hidden runtime toggle.
- R8. The dev and prod variants have a distinct `applicationId` (dev gets a suffix, e.g. `.dev`), a distinct app name (e.g. `SST Cam Dev`), and a distinct launcher icon, so both install side-by-side on one device and are visually distinguishable.

**Build performance**
- R9. Share/reuse Flutter (pub) and Gradle build caches across jobs to reduce build wall-clock; capture before/after timings to confirm the gain.

---

## Acceptance Examples

- AE1. **Covers R6, R7.** Given the prod APK installed, when the maintainer looks for diagnostics / debug pages / dev navigation, none are reachable by any gesture or setting.
- AE2. **Covers R6, R7.** Given the dev APK installed, the tooling (diagnostics / debug pages) is present and reaches the **real** firmware over BLE (not a mock).
- AE3. **Covers R8.** Given both dev and prod APKs installed on one phone, two separate launcher entries appear with distinct icons and names, and installing one does not overwrite the other.
- AE4. **Covers R4.** Given a beta with a recorded prod-APK SHA-256, when `release/* → main` merges, the stable prod asset's SHA-256 equals the beta prod SHA-256 and no Flutter/Gradle build job ran on `main`.
- AE5. **Covers R1.** Given a PR into `release/*`, when CI runs, no APK build job executes — only `ci-scripts` and `Analyze & Test` gate the merge.

---

## Success Criteria

- Shipping a beta no longer runs the throwaway PR build; wall-clock to publish a beta drops by roughly one full APK build plus cache savings, and the drop is measured (R9).
- Only real-backend APKs are ever published; the mock build never reaches a release.
- Dev and prod APKs coexist on one device and are distinguishable at a glance.
- `main` still runs no build and ships SHA-256-verified prod bytes.
- A downstream planner can implement without re-deciding the artifact-per-rung table, the tooling-gate semantics, or the variant-identity requirements.

---

## Scope Boundaries

- iOS build lane — unchanged / still deferred until a macOS runner exists.
- Firmware and proto pipelines — out of scope; they are fine.
- The alpha/beta/stable **version-ladder semantics** (counters, tag scheme, branch model) — unchanged; only what each rung *builds* changes.
- A **runtime** tooling toggle — explicitly rejected in favor of the build-time flag (prod must have zero shippable tooling path).
- Authoring new tooling/diagnostics features — this work re-gates and exposes existing tooling, it does not add new tooling.

---

## Key Decisions

- **Build-time flag over runtime toggle.** Tooling is compiled out of prod, so a prod build has no path to reveal it. Rationale: cleaner security/footprint posture than a hidden runtime toggle that ships dormant tooling in prod. Trade-off: to see tooling you install the separate dev APK.
- **Two binaries, accept the sign-off-vs-ship delta.** The maintainer validates the dev APK on hardware; `main` ships the prod APK. They differ only by the compiled-out tooling (identical real backend and BLE/wire behavior), so the delta is a compile flag, not a code-path fork. Accepted and documented rather than mitigated; a prod-APK smoke-test before promotion can be added later if desired.
- **One published artifact per non-beta rung; mock demoted to local-only.** Removes the ~411 MB mock asset nobody installs and the redundant PR build.

---

## Dependencies / Assumptions

- The real backend already exists behind the `lib/main_prod.dart` entrypoint (no provider mocks); the dev variant must build from the real-backend entrypoint, not `lib/main.dart`.
- `flutter_launcher_icons: ^0.14.1` (already a dependency) supports per-flavor/per-variant launcher icons.
- `APP_ENV` (`stage` vs `prod`) is the gating flag; today nothing branches on it for tooling, so the gating is net-new wiring.
- The beta→stable promotion job currently expects the beta's APK assets; it must be updated to select and verify the **prod** asset specifically.

---

## Outstanding Questions

### Resolve Before Planning

- (none — scope is settled.)

### Deferred to Planning

- [Affects R8][Technical] Mechanism for variant identity: Gradle **product flavors** vs `applicationIdSuffix` + `manifestPlaceholders` for label/icon — pick the lower-friction path that `flutter_launcher_icons` supports.
- [Affects R6, R7][Technical] Whether to keep two Dart entrypoints or build everything from `main_prod.dart` and gate tooling purely on `APP_ENV`; confirm the dev variant uses the real backend (not the `main.dart` mock override).
- [Affects R3, R4][Technical] Update the promotion logic in `release.yml` to select/verify the prod asset (now that beta publishes two real-backend APKs).
- [Affects R9][Needs research] Which caches (Gradle, pub, Flutter SDK) yield the most wall-clock savings on `ubuntu-latest` runners, and whether `subosito/flutter-action` cache plus a Gradle cache action is enough.
- [Affects R5][Technical] Confirm no test or tooling path depends on the mock APK being a published artifact before removing it.
