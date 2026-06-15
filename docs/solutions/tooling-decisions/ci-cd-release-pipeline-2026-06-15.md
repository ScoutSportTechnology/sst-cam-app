---
title: "CI/CD release pipeline: PR-gated CI + signed-APK auto-release (app)"
date: 2026-06-15
category: tooling-decisions
module: ci-cd
problem_type: tooling_decision
component: tooling
severity: medium
applies_when:
  - "Setting up or changing GitHub Actions CI/CD for the Flutter app"
  - "An org policy blocks Actions from creating/approving PRs"
  - "Building release APKs or wiring Android signing in CI"
tags: [ci-cd, github-actions, release, flutter, apk-signing, conventional-commits, protoc]
related_components: [development_workflow, tooling]
---

# CI/CD release pipeline: PR-gated CI + signed-APK auto-release (app)

## Context

CI/CD for the Flutter app, set up alongside proto + firmware. The cross-cutting design was forced by an org constraint: **"Allow GitHub Actions to create and approve PRs" is disabled org-wide** (changing it needs `admin:org`), so **release-please can't open its release PR**. A GitHub App was attempted and abandoned. Result: default `GITHUB_TOKEN` + conventional-commit tag-on-merge. This doc records the app-specific pipeline + the gotchas that bit during setup.

## Guidance

**Two workflows, default `GITHUB_TOKEN` only:**

- `.github/workflows/ci.yml` — **`pull_request` only**. Required check `Analyze & Test (Linux)`: `dart format` check → generate protos → `flutter analyze` → `flutter test`. Plus a non-required debug-APK smoke build.
- `.github/workflows/release.yml` — **`push: main`** + `workflow_dispatch`. `tag-release` job: conventional-commit bump (`feat:`→minor, `fix:`/`perf:`→patch, `BREAKING`→major, docs/chore→skip) → tag + Release. A gated `build-and-upload` job (runs only when a release was cut) builds **two APKs** and uploads them.

**Two APKs = entry-point + dart-define variants, NOT Gradle flavors:**
- production: `flutter build apk --release -t lib/main_prod.dart --dart-define=APP_ENV=prod`
- developer: `flutter build apk --release --dart-define=APP_ENV=stage`

(`emulated` is an orthogonal runtime flag, not a release build.)

**Three ordering/version gotchas, learned the hard way:**

1. **Generate protos in the analyze/build jobs.** `lib/models/proto/*.dart` is gitignored and generated; the BLE layer imports it. Without a gen step, `flutter analyze`/build fail with `uri_has_not_been_generated`. Add `submodules: recursive` + protoc + `gen-proto` before analyze.
2. **Pin `protoc_plugin` to `21.1.2`.** The latest plugin changes the generated map-field + enum API and breaks `flutter analyze` (`Map` not assignable to `Iterable<MapEntry>`, non-exhaustive switch). The app targets `protobuf ^3.1.0` / `protoc_plugin 21.1.2`.
3. **Run `dart format --set-exit-if-changed` BEFORE generating protos.** Generated bindings under `lib/models/proto/` are not dart-formatted; format-checking after codegen trips on generated code. Format hand-written code first, then generate. Also: the format target must only include dirs that exist (`integration_test/` doesn't) or `dart format` hard-errors.

**Signing falls back to debug when secrets are absent**, so the first release still produces (debug-signed) APKs:

```bash
if [ -z "${ANDROID_KEYSTORE_BASE64:-}" ]; then
  echo "::warning::no keystore secret — debug signing"; exit 0
fi
# else decode keystore + write android/key.properties (build.gradle.kts loads it)
```

## Why This Matters

- The proto-gen + plugin-pin + format-order issues are **invisible locally** (devs have protoc/flutter set up and gitignored protos already generated) but **fail every fresh CI run**. They cost several debug cycles. Bake them into the workflow.
- The app's CI workflow had been **manually disabled** (red since May) — re-enabling surfaced the above. Expect a fresh CI to surface real pre-existing issues; that's the gate working.
- Squash-merge subject must be conventional or `release.yml` cuts no release.

## When to Apply

- Editing `ci.yml` / `release.yml`, the proto codegen steps, or Android signing.
- Adding release-signed APKs: set repo secrets `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`, `ANDROID_STORE_PASSWORD`.
- Bumping the proto contract: it's a git submodule — `cd proto && git checkout vX.Y.Z && cd .. && git add proto && commit`.

## Examples

**Release manually / seed first tag** (the auto-scan skips on an empty tag history; once `v0.1.0` exists it works):

```bash
gh workflow run release.yml -R ScoutSportTechnology/sst-cam-app -f bump=minor
# or -f version=v1.2.3
```

## Related

- `docs/solutions/developer-experience/bool-fromEnvironment-default-tied-to-app-env-2026-05-19.md` — the `--dart-define=APP_ENV` flag pattern the release variants build on.
- Sibling captures: `sst-cam-proto` and `sst-cam-firmware` have repo-specific versions under `docs/solutions/tooling-decisions/`. proto's covers the cross-cutting GITHUB_TOKEN/ruleset rationale.
- `CLAUDE.md` → "CI/CD & releasing" section.
