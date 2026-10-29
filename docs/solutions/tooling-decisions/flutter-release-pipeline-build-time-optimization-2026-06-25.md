---
title: "Cut Flutter release CI time: parallel APK matrix, GH_REPO without checkout, and arm64-only builds"
date: 2026-06-25
category: tooling-decisions
module: ci-cd
problem_type: tooling_decision
component: tooling
severity: medium
applies_when:
  - "A CI job builds multiple independent artifacts (e.g. APK flavors) sequentially in one runner"
  - "A CI job calls `gh` without an actions/checkout step"
  - "Deciding whether a prebuilt toolchain image or more caching would speed up a slow CI build"
  - "A mobile build packages multiple ABIs but the entire target fleet is one architecture"
tags:
  - flutter
  - github-actions
  - ci-cd
  - parallel-matrix
  - abi-restriction
  - apk-build
  - release-pipeline
  - artifact-handoff
---

# Cut Flutter release CI time: parallel APK matrix, GH_REPO without checkout, and arm64-only builds

## Context

The `sst-cam-app` beta release lane (`.github/workflows/release-beta.yml`) built **both** APK flavors — production (`APP_ENV=prod`) and developer (`APP_ENV=stage`) — sequentially in a single runner, ~6 min each, for ~12–16 min of wall-clock per beta. The goal was to make it faster without changing the build toolchain. Three composable moves took it to ~5 min.

## Guidance

### Move 1 — Parallelize per-artifact builds with a job matrix

Split the one sequential job into three jobs with a dependency chain: `version` (resolve the `-beta.N` tag **once**, expose as a job output) → `build` (a `strategy.matrix` cell per flavor, each on its **own runner in parallel**, uploading its APK as a workflow artifact) → `publish` (download both artifacts, record SHA-256, create/refresh the Release).

```yaml
version:
  runs-on: ubuntu-latest
  outputs:
    tag: ${{ steps.ver.outputs.tag }}     # resolved once, shared by all downstream jobs
  steps:
    - uses: actions/checkout@v4
      with: { fetch-depth: 0 }
    - id: ver
      run: ./scripts/ci/resolve-version.sh beta "${GITHUB_REF_NAME#release/}"

build:
  needs: version
  runs-on: ubuntu-latest
  strategy:
    fail-fast: false                       # build both flavors even if one fails
    matrix:
      include:
        - { flavor: prod, app_env: prod,  kind: production }
        - { flavor: dev,  app_env: stage, kind: developer }
  steps:
    # ... checkout, java, gradle, flutter, protoc, signing, icons ...
    - run: flutter build apk --release --flavor ${{ matrix.flavor }} -t lib/main_prod.dart --dart-define=APP_ENV=${{ matrix.app_env }} --target-platform android-arm64
    - name: Stage APK artifact
      env:
        TAG: ${{ needs.version.outputs.tag }}
        FLAVOR: ${{ matrix.flavor }}
        KIND: ${{ matrix.kind }}
      run: |
        mkdir -p dist
        cp "build/app/outputs/apk/${FLAVOR}/release/app-${FLAVOR}-release.apk" \
           "dist/sst-cam-app-${TAG}-${KIND}.apk"
    - uses: actions/upload-artifact@v4
      with:
        name: apk-${{ matrix.kind }}
        path: dist/sst-cam-app-${{ needs.version.outputs.tag }}-${{ matrix.kind }}.apk
        retention-days: 1
        if-no-files-found: error

publish:
  needs: [version, build]
  runs-on: ubuntu-latest
  steps:
    - uses: actions/download-artifact@v4
      with: { path: artifacts }
    # ... flatten, SHA-256, gh release create/edit + upload --clobber ...
```

`needs.version.outputs.tag` is the connective tissue: both matrix cells and `publish` read the same resolved tag, so the `-beta.N` counter is computed exactly once. `fail-fast: false` keeps the prod result visible if the dev cell fails.

### Move 2 — `gh` in a checkout-free job needs `GH_REPO`

The `publish` job consumes only the downloaded artifacts, so it has no `actions/checkout` — and therefore no `.git`. `gh` cannot infer the repo and dies:

```
failed to run git: fatal: not a git repository (or any of the parent directories): .git
```

The naive fix (add `actions/checkout`) pulls the whole tree just to hint `gh`. The right fix is one env line — `github.repository` is always available, no secret, no checkout:

```yaml
- name: Assemble + publish prerelease
  env:
    GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
    GH_REPO: ${{ github.repository }}   # job has no .git → point gh at the repo explicitly
    TAG: ${{ needs.version.outputs.tag }}
  run: |
    gh release create "$TAG" ...        # now works
```

### Move 3 — Measure setup vs. build before reaching for an image

The instinct for a slow CI build is "bake a prebuilt toolchain image." Per-step timing said otherwise:

| Step | Duration |
|------|----------|
| `subosito/flutter-action` (cache hit) | ~14 s |
| `gradle/actions/setup-gradle` (cache hit) | ~1 s |
| `dart pub global activate protoc_plugin` (cache hit) | ~1 s |
| **Total setup** | **~30 s** |
| `flutter build apk` | **~5.5 min** |

Setup was already ~30 s on warm caches — an image would recover seconds at real maintenance cost. The bottleneck was the build itself. The lever was dropping unused ABIs: the Jetson and all device-test phones are 64-bit ARM, but the default `flutter build apk` also compiles `armeabi-v7a` (32-bit) and `x86_64` (emulator).

```bash
# before — arm64-v8a + armeabi-v7a + x86_64 → ~5.5 min, ~411 MB
flutter build apk --release --flavor prod -t lib/main_prod.dart --dart-define=APP_ENV=prod

# after — arm64-v8a only → ~4.3 min (~22% faster), ~355 MB (~14% smaller)
flutter build apk --release --flavor prod -t lib/main_prod.dart --dart-define=APP_ENV=prod \
  --target-platform android-arm64
```

The same flag is added to `release-alpha.yml`'s developer build. `release.yml` (stable) does **not** build — it promotes the beta bytes — so arm64-only flows to stable automatically, making this a **distribution** decision, not just a build one.

## Why This Matters

- The matrix turns **sum-of-builds into max-of-builds** on wall-clock: two ~5.5-min sequential builds + publish (~12–16 min) becomes one ~5.5-min build (the slower parallel cell) + a ~20 s publish. Net pipeline ~12–16 → ~5 min.
- The artifact hand-off is also what preserves the **SHA-256 promotion contract**: `publish` records each APK's digest in the Release notes and `release.yml` verifies those exact bytes before re-uploading to stable. Parallelizing didn't weaken the contract — it forced making the build→publish boundary explicit.
- **Measuring first** prevented wasted effort. With setup already ~30 s on warm caches, a custom image was the wrong tool; the win was in the build step (ABIs), found only by reading per-step timing.

### Tradeoffs (accepted)

- **Runner-minutes go up.** Both cells re-do checkout/Java/Gradle-restore/Flutter-restore/protoc/proto-gen (~1.5 min each, even warm) + ~800 MB artifact round-trip. More billed minutes for less wall-clock — the intended trade.
- **arm64-only drops ABIs.** No `armeabi-v7a` (32-bit phones) and no `x86_64` (Android emulator). Fine for a Jetson-paired accessory app tested on physical 64-bit phones; **wrong** for general Play Store distribution (use an AAB / `--split-per-abi` and let the store split). Because stable promotes beta bytes, this commitment reaches production.
- Each parallel leg materializes the keystore independently — keep the **warn-and-continue** guard identical in every leg (see related keystore doc); hardening one leg silently breaks that flavor only.

## When to Apply

- **Matrix pattern:** any CI job producing multiple independent artifacts from the same toolchain (different flavors/targets/params) where outputs can cross job boundaries as files.
- **`GH_REPO`:** any CI job that calls `gh` without a checkout (collector/publisher jobs that only need downloaded artifacts).
- **Measure setup vs. build:** before building a prebuilt toolchain image or tuning caches — if warm-cache setup is already under a minute and the compile dominates, the image won't help; look at what the build does (extra ABIs, debug symbols, redundant TUs).
- **`--target-platform android-arm64`:** only when the entire fleet (devices + CI test devices) is confirmed 64-bit ARM and you're shipping a fat APK (not a Play Store AAB).

## Examples

Net effect, measured on `sst-cam-app` (PRs #27 parallelize, #28 GH_REPO fix, #29 arm64-only):

| | Before | After |
|---|--------|-------|
| Beta build topology | one job, 2 builds serial | `version` → `build` matrix ∥ → `publish` |
| Prod build step | 5m32s (all ABIs) | 4m18s (arm64) |
| Prod APK size | 411 MB | 355 MB |
| Pipeline wall-clock | ~12–16 min | ~5 min |

## Related

- `docs/solutions/tooling-decisions/ci-cd-release-pipeline-2026-06-15.md` — foundational pipeline doc this optimization extends; its proto-gen-ordering and `protoc_plugin` pin gotchas still apply inside each parallel matrix leg.
- `docs/solutions/tooling-decisions/beta-keystore-fail-closed-trap-2026-06-25.md` — the keystore warn-and-continue rule must hold identically in each parallel leg; don't harden one flavor's leg.
