---
title: "feat: CI/CD & release pipeline (sst-cam-app)"
type: feat
status: active
date: 2026-06-10
origin: docs/brainstorms/ci-cd-release-pipeline-requirements.md
---

# feat: CI/CD & Release Pipeline (sst-cam-app)

**Target repo:** sst-cam-app (Flutter / Dart)

## Summary

Harden the existing Flutter CI as the merge gate, switch proto consumption from a git submodule + local protoc to a **versioned Dart package pinned by proto release tag**, and add a release workflow that builds and signs **two APKs** (production + developer) on each release-please tag, uploading them to the GitHub Release.

---

## Problem Frame

The app already has a working `flutter analyze` + `flutter test` CI, but: it builds only an unsigned debug APK, has no release flow, regenerates proto with `protoc` from a SHA-pinned submodule each build, and release signing is unconfigured (release uses the debug key). There is no automated, versioned production artifact.

> **Origin correction:** the requirements doc described a Kotlin/Java app consuming a Maven SDK. The app is **Flutter/Dart**; proto is consumed as a **Dart package via git tag** (user-confirmed). (see origin: docs/brainstorms/ci-cd-release-pipeline-requirements.md)

---

## Requirements

- R1. PRs to `main` run format + analyze + test; merge blocked until green (1 approval).
- R2. Release-please drives semver tags/releases from conventional commits on `main`.
- R3. On a release tag, build **two APKs**: production (`main_prod.dart`, `APP_ENV=prod`) and developer (`APP_ENV=stage`), both real backend; emulated stays a runtime flag.
- R4. Both APKs are **signed for release** and uploaded as GitHub Release assets.
- R5. App consumes proto via the **Dart package git-tag dependency** — no submodule, no `protoc` in the app build.

**Origin actors:** developers (PRs), release/operator (distributes APKs).

---

## Scope Boundaries

- No emulated APK variant — emulated is a runtime flag (`kAppEnv.isDevBackend` / dev_config), not a build.
- No iOS release (already commented out in CI; out of scope).
- No Play Store / Firebase distribution — GitHub Release assets only.

### Deferred to Follow-Up Work

- Org GitHub App creation: shared prerequisite across the 3 repos (see Risks & Dependencies).
- Proto Dart package itself is produced by `sst-cam-proto` (its plan, U1/U3); this plan only consumes it.

---

## Context & Research

### Relevant Code and Patterns

- `.github/workflows/ci.yml` — existing: `analyze-and-test` (format check, `flutter analyze`, `flutter test --coverage`, Codecov) + `build-android` (debug APK). Reuse and extend; do not rewrite.
- Env scheme: `lib/core/config/env.dart` (`APP_ENV` dart-define, enum dev/stage/prod), `lib/main.dart` (dev, injects MockBle/MockWifi), `lib/main_prod.dart` (prod, real services). `kAppEnv.isDevBackend` gates mocks.
- Build recipes: `justfile` — `build-android-prod` = release APK + `--dart-define=APP_ENV=prod` + `-t lib/main_prod.dart`.
- Proto today: `.gitmodules` (`proto/` submodule), `justfile` `gen-proto` → `protoc --dart_out=lib/models/proto`. Only `BleServiceImpl` imports generated bindings. Output `lib/models/proto/` is gitignored.
- Signing: `android/app/build.gradle.kts` release block uses `signingConfigs.getByName("debug")` with a TODO; no keystore in repo.

### Institutional Learnings

- `docs/solutions/` — none directly on release signing yet; capture one after first signed release.

### External References

- `flutter build apk --release --flavor`-free flavoring via `--dart-define` + `-t <entrypoint>` (matches current justfile approach).
- Android release signing in CI: keystore base64 secret → decode → `key.properties` → gradle `signingConfigs`.

---

## Key Technical Decisions

- **Reuse existing CI job as the gate**, don't replace. The `analyze-and-test` job becomes the `required_status_check`.
- **Two APKs via dart-define + entrypoint**, not Gradle product flavors (the app has none). production = `-t lib/main_prod.dart --dart-define=APP_ENV=prod`; developer = `--dart-define=APP_ENV=stage` (real backend, dev flags).
- **Proto as git-tag Dart dependency**: `pubspec.yaml` git ref `path: gen/dart`, `ref: vX.Y.Z`. Drop the submodule and `gen-proto`. Bump the `ref` to adopt a new protocol version deliberately.
- **Release signing via secrets**: keystore stored as CI secret, materialized at build time; never committed.

---

## Open Questions

### Resolved During Planning

- APK variant mapping: prod + stage (user-confirmed).
- Proto consumption: Dart git-tag package (user-confirmed).

### Deferred to Implementation

- Whether `developer` (`APP_ENV=stage`) needs a distinct application ID / suffix so both APKs can coexist on one device — decide when wiring gradle (likely `applicationIdSuffix ".dev"`).
- Keystore provenance (new release keystore vs existing) — operator decision before first signed release.

---

## Implementation Units

### U1. Promote CI to the merge gate

**Goal:** Ensure PR CI (format + analyze + test) is the required status check; trim the debug-APK build from the PR path if redundant.

**Requirements:** R1

**Dependencies:** None

**Files:**
- Modify: `.github/workflows/ci.yml`

**Approach:**
- Keep `analyze-and-test` as-is (it already mirrors `justfile` checks). Confirm trigger covers PRs to `main`. The `build-android` debug job may stay as a smoke build or be dropped once the release workflow exists; keep for now as PR smoke signal.
- Job name `analyze-and-test` → wired as `required_status_checks` in U6.

**Test scenarios:**
- Test expectation: none — CI config; validated by a PR run staying green and a deliberately failing test blocking merge.

**Verification:**
- A PR with a failing `flutter test` cannot merge; format/analyze failures block too.

### U2. Switch proto consumption to git-tag Dart package

**Goal:** Replace submodule + `gen-proto` with a pinned Dart package dependency.

**Requirements:** R5

**Dependencies:** Proto plan U1/U3 (a published `gen/dart` at a tag must exist)

**Files:**
- Modify: `pubspec.yaml` (add `sst_cam_proto` git dependency: url, `ref: vX.Y.Z`, `path: gen/dart`)
- Modify: `.gitmodules` (remove `proto` submodule) + remove `proto/` submodule entry
- Modify: `justfile` (remove/retire `gen-proto`; drop protoc from build path)
- Modify: import sites — `lib/.../ble_service_impl.dart` (and any other proto importers) to import from the `sst_cam_proto` package instead of `lib/models/proto/`
- Modify: `.devcontainer/Dockerfile` (protoc no longer required for app build — optional cleanup)

**Approach:**
- Pin to the first proto release tag. Update imports from the gitignored `lib/models/proto/*.dart` to `package:sst_cam_proto/...`.
- Keep the change behavior-preserving — same messages, same wire.

**Execution note:** Start by confirming the proto package's exported symbols match current usage in `BleServiceImpl`, then swap imports.

**Patterns to follow:**
- Current generated API in `lib/models/proto/` defines the symbol set the package must satisfy.

**Test scenarios:**
- Happy path: app compiles (`flutter analyze`) against `package:sst_cam_proto`; existing BLE serialization tests pass unchanged.
- Integration: a BLE encode/decode round-trip test proves wire compatibility with the package-sourced types.
- Edge case: proto3 optional fields behave identically to the old generated code.

**Verification:**
- No `proto/` submodule, no `gen-proto` invocation, `flutter test` green, app builds.

### U3. Release signing config

**Goal:** Configure real release signing driven by CI secrets.

**Requirements:** R4

**Dependencies:** None

**Files:**
- Modify: `android/app/build.gradle.kts` (release `signingConfig` reads from `key.properties` when present, else falls back to debug for local dev)
- Create: `android/key.properties.example` (documented placeholders; real file gitignored / CI-generated)
- Modify: `.gitignore` (ensure `key.properties` + keystore ignored)

**Approach:**
- Standard pattern: CI decodes a base64 keystore secret + writes `key.properties`; gradle release `signingConfig` loads it. Local builds without the file keep working with debug signing.

**Test scenarios:**
- Happy path: with `key.properties` present, `flutter build apk --release` produces a release-signed APK; `apksigner verify` confirms the release key.
- Edge case: without `key.properties`, local debug build still succeeds (no CI secret needed locally).

**Verification:**
- Release APK is signed with the release key in CI; local dev unaffected.

### U4. Release workflow — build + upload two APKs

**Goal:** On a release-please tag, build signed production + developer APKs and attach to the Release.

**Requirements:** R2, R3, R4

**Dependencies:** U1, U2, U3, U5

**Files:**
- Create: `.github/workflows/release.yml`

**Approach:**
- Trigger on the release-please-created tag/release (or as a follow-on job after U5's release-please job — see Risks re: App token so the tag triggers this).
- Materialize keystore from secrets → `key.properties`.
- Build two APKs:
  - production: `flutter build apk --release -t lib/main_prod.dart --dart-define=APP_ENV=prod`
  - developer: `flutter build apk --release --dart-define=APP_ENV=stage`
- Upload both `build/app/outputs/apk/release/*.apk` (renamed `sst-cam-app-<ver>-prod.apk` / `-developer.apk`) as Release assets.

**Test scenarios:**
- Test expectation: none — release automation; validated by a tagged dry run producing two signed, distinctly-named APKs on the Release.

**Verification:**
- A release tag yields a GitHub Release carrying exactly two signed APKs (prod + developer), each launchable and pointed at the right backend.

### U5. release-please config

**Goal:** Conventional-commit-driven semver releases for the app.

**Requirements:** R2

**Dependencies:** None

**Files:**
- Create: `release-please-config.json` (release-type `dart` or `simple`; can bump `pubspec.yaml` app version)
- Create: `.release-please-manifest.json`
- Create: `.github/workflows/release-please.yml`

**Approach:**
- release-please maintains the release PR; merging tags `vX.Y.Z` and cuts the Release that U4 builds against. Auth via the **org GitHub App** token so the tag fires U4.

**Test scenarios:**
- Test expectation: none — validated by a dry-run release PR producing the expected version bump.

**Verification:**
- Merging a `feat:` release PR tags and releases; U4 fires on that tag.

### U6. Branch & tag governance

**Goal:** Apply shared rulesets; wire CI as required check and App as bypass actor.

**Requirements:** R1

**Dependencies:** U1

**Files:**
- Reference (repo settings, not committed): branch ruleset on `main`, tag ruleset `v*`.

**Approach:**
- Branch ruleset: PR required, 1 approval, dismiss stale, thread resolution, block force-push/delete; `required_status_checks` = `analyze-and-test`.
- Tag ruleset: semver regex, immutable; bypass = `OrganizationAdmin` + org GitHub App, added via UI (not JSON).

**Test scenarios:**
- Test expectation: none — repo settings; validated by a blocked direct push and blocked non-semver tag.

**Verification:**
- Direct push to `main` rejected; CI required before merge; only App/admin push `v*`.

---

## System-Wide Impact

- **Interaction graph:** dropping the submodule changes the build graph; `BleServiceImpl` is the only known proto importer — verify no other importers via search before merge.
- **State lifecycle risks:** `lib/models/proto/` (gitignored generated dir) becomes dead — remove references so stale generated files can't shadow the package.
- **API surface parity:** production vs developer APKs must differ only by backend/env, not behavior; emulated remains runtime-toggled.
- **Unchanged invariants:** wire protocol, BLE/Wifi service interfaces, Riverpod mock-injection mechanism for local dev.

---

## Risks & Dependencies

| Risk | Mitigation |
|------|------------|
| Proto Dart package not yet released | Sequence after proto plan U3; pin app to the first proto tag. Until then, keep submodule on a feature branch. |
| `GITHUB_TOKEN` tag won't trigger U4 | Use the org GitHub App token in release-please (U5), or chain U4 within the release-please job. |
| Two APKs collide on one device (same applicationId) | Give developer build an `applicationIdSuffix` (deferred decision, U-level note in Open Questions). |
| Keystore mismanagement | Store as CI secret only; `key.properties` + keystore gitignored; document in `key.properties.example`. |
| Org GitHub App not created | Shared prerequisite; block U5 wiring until org admin provisions it. |

---

## Sources & References

- **Origin document:** docs/brainstorms/ci-cd-release-pipeline-requirements.md
- Related code: `.github/workflows/ci.yml`, `lib/core/config/env.dart`, `lib/main_prod.dart`, `justfile`, `android/app/build.gradle.kts`, `.gitmodules`
- Cross-repo: `sst-cam-proto/docs/plans/2026-06-10-001-feat-ci-cd-release-pipeline-plan.md`
