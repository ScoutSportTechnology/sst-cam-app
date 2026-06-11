# CI/CD & Release Pipeline — Requirements (sst-cam-app)

> **Correction (2026-06-10, planning):** the app is **Flutter/Dart**, not native Kotlin/Android. Env control is `--dart-define=APP_ENV` + entry points (`main.dart` / `main_prod.dart`), not Gradle flavors. Proto is consumed as a **Dart package via git tag** (not GitHub Packages Maven). APK variants: production = `main_prod.dart` + `APP_ENV=prod`; developer = `APP_ENV=stage`. Kotlin/Maven references below are superseded. See `docs/plans/2026-06-10-001-feat-ci-cd-release-pipeline-plan.md`.

**Date:** 2026-06-10
**Status:** Ready for planning
**Type:** Standard — infrastructure / DevOps
**Cross-repo note:** Part of a shared CI/CD effort across sst-cam-app, sst-cam-firmware, sst-cam-proto. This doc covers the **app** slice; governance below is duplicated in each repo because it applies to each.

## Problem

No automated CI or release flow. `main` unprotected, releases hand-cut, APKs built manually. Need lint → test → release automation with protected `main` and semver releases.

## Goals

- `main` default, PR-gated, immutable semver tags.
- PR runs **lint + test**; merge blocked until green.
- Automated semver releases (no hand-cut tags).
- Release artifacts = `production` + `developer` APKs on GitHub Releases.
- Consume proto as a versioned **SDK** (drop submodule).

## Non-Goals (now)

- Emulated APK release variant — emulated is a runtime flag, not a build.
- Staging/deploy targets beyond producing the APK artifact.

---

## Branch & Tag Governance (shared, applies here)

### Branch ruleset (`main`)
- `main` = default; feature branches unrestricted, per-developer.
- Require PR; **1 approval**; dismiss stale reviews on push; require thread resolution.
- Block force-push (`non_fast_forward`) + deletion.
- **Add `required_status_checks`** = this repo's lint+test jobs, once workflows exist. Makes CI gate merges.

### Tag ruleset (`v*`)
- Semver regex: `^v\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$`.
- Immutable: block `update`, `deletion`, `non_fast_forward`.
- **Bypass actors:** `OrganizationAdmin` + the org **GitHub App** (added via GitHub UI, not JSON — UI resolves the App name to its numeric `actor_id`; a string id fails import with "invalid actor").

### Release mechanism (shared)
- **release-please** (PR-based): conventional commits on `main` → release PR → merge bumps semver, tags, cuts GitHub Release.
- **Identity:** one org-owned **GitHub App**, installed on all 3 repos; its token pushes tags and is the tag-ruleset bypass actor. Chosen over `GITHUB_TOKEN` because the default token's recursion guard means its tag push would **not** trigger the release-build workflow.
- Requires conventional-commit discipline on `main`.

---

## App-Specific Requirements

- **PR CI:** lint + unit tests.
- **Release (on release-please tag):** build **two** APK flavors:
  - `production` — buildtime variant, real backend/flags.
  - `developer` — buildtime variant (distinct flags/backend). **Not** emulated; emulated is an orthogonal runtime flag.
- Both APKs → **GitHub Release assets**.

### Proto consumption — via SDK (not submodule)
- Drop the proto **git submodule**; stop running protoc/codegen in the app build.
- Depend on the published proto SDK: `implementation "com.sst:cam-proto:<semver>"` from **GitHub Packages (Maven)**.
- SDK version = proto repo's release-please semver tag. App pins a semver, not a SHA.
- App build (Gradle/Android) must authenticate to GitHub Packages.
- (SDK is produced by sst-cam-proto — see that repo's doc for publish details.)

| Dimension | Submodule (today) | SDK (target) |
|---|---|---|
| protoc/toolchain in app | required | not required |
| version identity | git SHA | semver |
| build speed | codegen every build | prebuilt, cached |
| coupling | tight (source) | loose (artifact) |

## Success Criteria

- PR to `main` can't merge until lint + test pass and 1 review approves.
- Tags only exist if semver; releases immutable.
- Merging release-please PR cuts a Release with `production` + `developer` APKs, no manual tagging.
- App builds against `com.sst:cam-proto:<semver>` — no submodule, no local codegen.

## Dependencies / Assumptions

- CI = GitHub Actions.
- Org GitHub App created + installed + added as bypass actor (org-admin task).
- Conventional commits on `main`.
- App can authenticate to GitHub Packages from Gradle.

## Open Questions (for planning)

- release-please config (independent per-repo versioning assumed).
- Maven `groupId`/`artifactId` the app depends on (coordinate with proto).
- APK signing config for release builds.
