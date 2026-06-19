---
title: "feat: Git + CI/CD workflow standard — sst-cam-app"
type: feat
status: active
date: 2026-06-17
origin: docs/brainstorms/2026-06-17-cicd-workflow-standard-requirements.md
---

# feat: Git + CI/CD workflow standard — sst-cam-app

## Summary

Refactor this repo's existing single-`main` pipeline into the org-wide SST branch model (`feat/* → develop → release/X.Y.Z → main`) with a test-fidelity maturity ladder (alpha = automated vs mock+emulator, beta = manual vs real firmware, stable = shipped). Move the failable APK build off `main` so `main` only *promotes* an already-built artifact, add SemVer prerelease tags (`vX.Y.Z-alpha.N` on `develop`, `vX.Y.Z-beta.N` on `release/*`), and reset the bogus `v0.1.0` tag back to the `0.1.0-alpha` line toward a first `0.1.0-beta.1`. This is a CI/CD + governance refactor — no Flutter app code changes.

---

## Problem Frame

`release.yml` auto-cuts a release on every push to `main` and **builds the APKs there** — a failable post-merge job, so `main` can hold code whose release/build broke (violates the new "main never builds" rule). There is no `develop` integration branch and no prerelease ladder: the single `v0.1.0` tag was auto-cut by this flow and corresponds to no real, tested release. (see origin: docs/brainstorms/2026-06-17-cicd-workflow-standard-requirements.md)

---

## Requirements

- R1. Create a long-lived `develop` branch; make it the default target for `feat/*`/`fix/*`.
- R2. Rulesets: `develop` requires PR + green checks; `main` requires PR + green required-status-checks + no direct push (admin/hotfix bypass only); `release/*` requires the release checks.
- R3. `main` runs **no failable build/publish job**; builds/publishes happen on PRs / `develop` / `release/*`.
- R4. Rework `ci.yml` to run on PRs into `develop` (and `release/*`); the app's automated tests run against mock + emulator.
- R5. On merge to `develop`, auto-build + tag `vX.Y.Z-alpha.N` and publish the alpha APK.
- R6. On `release/X.Y.Z`, build the release APK + tag `vX.Y.Z-beta.N`; betas iterate on the branch.
- R7. Replace `release.yml`'s auto-cut-on-push-to-`main` with release-branch→main promotion: tag `vX.Y.Z` + publish the already-built beta APK, no rebuild on `main`.
- R8. Adopt Conventional Commits as the automated bump source (already in use; extend for prereleases).
- R9. Delete the bogus `v0.1.0` tag + release; re-establish the clean scheme at the `0.1.0-alpha` line.
- R10. Consolidate work done under `0.1.0-alpha.N`; immediate target `0.1.0-beta.1` (joint firmware+app hardware test). `1.0.0` = eventual first stable.
- R11. Update `CLAUDE.md`/`AGENTS.md`, `README`, and build/release docs to the new model, ladder, tag/version convention, and flow.

**Origin actors:** A1 Contributor, A2 Maintainer/admin, A3 CI, A4 sst-cam-emulator (backs alpha), A5 firmware device (beta counterpart).
**Origin flows:** F1 Feature→develop (alpha), F2 Cut release candidate (beta), F3 Promote to stable.
**Origin acceptance examples:** AE1 (R1,R4), AE2 (R5,R3), AE3 (R2,R3), AE4 (R7,R3).

---

## Scope Boundaries

- No external-tester cohorts; no nightly builds.
- No maintenance branches / backporting (latest-only-supported).
- Not cutting `1.0.0`.
- No Flutter/Dart application code changes — pipeline, rulesets, and docs only.
- No change to the proto-consumption model (git submodule + `just gen-proto` stays).

### Deferred to Follow-Up Work

- `0.1.0-beta.1` hardware sign-off itself (the manual integration test against a real firmware device): runs hand-in-hand with the firmware plan, not a CI artifact of this plan.
- Android `applicationIdSuffix` so production + developer APKs coexist on one device: pre-existing TODO in `android/app/build.gradle.kts`, out of scope here.
- Release-signing secrets (`ANDROID_*`): keystore provisioning is a maintainer operational task; debug-signing fallback stays the default.

---

## Context & Research

### Relevant Code and Patterns

- `.github/workflows/ci.yml` — current CI: triggers on `pull_request: [main]`; `analyze-and-test` (required) + `build-android` (debug, non-required). Reused as the alpha gate, retargeted to `develop`/`release/*`.
- `.github/workflows/release.yml` — current release: `push: [main]` + `workflow_dispatch`; hand-rolled conventional-commit bump in the `Resolve version` bash step → `gh release create` → `build-and-upload` (2 APKs). This is the file that violates R3 (builds on main) and is the core of the refactor.
- The version-resolution bash (`release.yml` lines 44–88) is the proven pattern to extend with prerelease-counter logic.
- `CLAUDE.md` "CI/CD & releasing" section — the documentation surface to rewrite (R11).

### Institutional Learnings

- Bump tool is **hand-rolled bash**, not release-please — release-please was deliberately removed (org disables "Actions create/approve PRs"; `GITHUB_TOKEN` recursion guard). Keep the bash approach; do not reintroduce release-please. (memory: cicd-pipeline-plan)
- Default `GITHUB_TOKEN` only — no PAT/App (GitHub App was abandoned). "Release Tags" ruleset allows compliant tag *creation*, blocks delete/update/force-push, so prerelease tag creation needs no bypass actor. (memory: cicd-pipeline-plan)
- First-release auto-detect anomaly: scanning full history with no baseline tag skipped release ("No releasable since v0.0.0"). Once a baseline tag exists, ranged scans work. Relevant to the post-reset first alpha. (memory: cicd-pipeline-plan)
- Proto stays a git submodule (Dart SDK dropped 2026-06-15); CI must `submodules: recursive` + `just gen-proto`. (memory: cicd-pipeline-plan)

### External References

- SemVer 2.0 prerelease precedence: `-alpha.N` < `-beta.N` < (no suffix). `git tag --sort=-v:refname` orders these correctly for "latest" selection within a base version.

---

## Key Technical Decisions

- **Keep hand-rolled bash bump; extend for prereleases.** Add a reusable `scripts/ci/resolve-version.sh` that, given a mode (`alpha|beta|stable`) and git tag state, emits the next tag. This isolates the one genuinely tricky bit of logic into a unit-testable script instead of inline workflow YAML. Rationale: testability + the three workflows share one source of truth for version math.
- **"main never builds" via artifact hand-off.** The beta APK built on `release/*` is uploaded as an asset on the `vX.Y.Z-beta.N` prerelease GitHub Release. The `main` promotion workflow **downloads that asset and re-uploads it** to the new `vX.Y.Z` stable Release — no Flutter build runs on `main`. Rationale: directly satisfies R3/R7/AE4 with a verifiable artifact identity (same bytes promoted, not rebuilt).
- **Alpha base version = conventional-commit bump from the latest _stable_ tag; alpha counter = increment within that base.** On `develop` merge: compute base `X.Y.Z` from commits since the last non-prerelease tag (v0.0.0 if none), then find the latest `vX.Y.Z-alpha.*` and increment `N` (start at 1). Rationale: alpha line tracks "what the next release will be" while iterating.
- **Beta base = the `release/X.Y.Z` branch name; beta counter increments within it.** The branch name is the authoritative base for betas — removes ambiguity during the stabilization window when `develop` may have moved on.
- **Three workflows, trigger-separated.** `ci.yml` (PR checks incl. required build), `alpha.yml` (push to `develop` → tag+publish alpha), `release-beta.yml` (push to `release/**` → build+tag+publish beta), `promote.yml` (push to `main` → retag+copy asset). Split by trigger keeps each `on:` unambiguous and each job's required/non-required status clean.
- **`main`'s required check is the release branch's check reused on the shared head SHA.** A `release/X.Y.Z → main` PR's head SHA *is* the release-branch tip, which already carries green `ci.yml` (+ beta) check runs from its `release/*` push. GitHub surfaces those runs on the PR, so the `main` ruleset can require them with **no build re-running on `main`** — this is the concrete R3/AE4 mechanism. Caveat to verify at implementation: confirm GitHub surfaces a push-event check run as a PR status on the same SHA; if it does not, add a lightweight `pull_request: [main]` gate that only *asserts the `vX.Y.Z-beta.N` Release/asset exists* (no Flutter build), rather than re-running the build. Resolve this before wiring U6's `main` ruleset.
- **Version reset is a one-time maintainer operation, not a workflow.** Deleting `v0.1.0` + its Release and seeding the `0.1.0-alpha` line is documented as a runbook (operational), executed once by the admin.
- **Operational doc location + AGENTS.md.** CI runbooks live under `docs/ci/` (new, deliberate: keeps operational CI procedure separate from `docs/solutions/` post-mortems). `AGENTS.md` is created only if the sibling repos adopt it; R11's "update AGENTS.md" is conditional on its existence (U8 reflects this).

---

## Open Questions

### Resolved During Planning

- Bump/changelog tool? → Hand-rolled bash, extended (see Key Decisions); release-please stays removed.
- How is the alpha base version derived pre-1.0 with no stable tag? → Bump from `v0.0.0`; a `feat:`-bearing develop merge yields base `0.1.0` → `v0.1.0-alpha.1`.
- Where does the promoted (not rebuilt) APK come from? → The `vX.Y.Z-beta.N` Release asset, downloaded and re-uploaded by `promote.yml`.

### Deferred to Implementation

- Exact bats/shell test harness wiring for `resolve-version.sh` (test runner choice, fixture tag lists) — settle when writing the script.
- Whether `promote.yml` also automates the "merge back to develop" step or leaves it as a documented maintainer action — decide against GitHub ruleset behavior at implementation time.
- How app alpha pins the emulator version it tests against (proto is already submodule-pinned) — surfaces once the emulator CI exists; track with the emulator plan.

---

## High-Level Technical Design

> *This illustrates the intended approach and is directional guidance for review, not implementation specification. The implementing agent should treat it as context, not code to reproduce.*

```
feat/* ──PR──► ci.yml (analyze+test vs mock/emulator, build APK) ──green+review──► develop
                                                                                      │
develop ──push──► alpha.yml ──► resolve-version.sh alpha ──► tag vX.Y.Z-alpha.N ──► build + publish alpha APK (prerelease Release)
                                                                                      │
develop ──cut (maintainer)──► release/X.Y.Z
                                  │
release/** ──push──► release-beta.yml ──► resolve-version.sh beta ──► build APK ──► tag vX.Y.Z-beta.N ──► publish beta APK (prerelease Release asset)
                                  │
                       manual integration sign-off vs real firmware device (A5)
                                  │
release/X.Y.Z ──PR (beta checks green)──► main ──push──► promote.yml ──► tag vX.Y.Z ──► download beta APK asset ──► re-upload to stable Release
                                                                                  (NO build runs on main)
                                  │
                          delete release branch ; merge back to develop
```

Version resolution contract (the testable core):

```
resolve-version.sh alpha            # base = bump(latest stable tag) ; → vBASE-alpha.(maxN+1)
resolve-version.sh beta  X.Y.Z      # base = X.Y.Z (branch name)     ; → vX.Y.Z-beta.(maxN+1)
resolve-version.sh stable X.Y.Z     # → vX.Y.Z  (no suffix)
# precedence for "latest N": git tag -l 'vBASE-alpha.*' --sort=-v:refname | head -1
```

---

## Implementation Units

- U0. **Bootstrap the branch model (prerequisite — do before all other units)**

**Goal:** Create `develop` and make it the default branch so the retargeted workflows and rulesets have a branch to key off. (Without this, every `develop`/`release/*` trigger references a branch that does not exist.)

**Requirements:** R1

**Dependencies:** None — this is the first step; U2, U3, U6, U7 depend on it.

**Files:**
- None (one-time `git` + `gh` operations; documented in `docs/ci/rulesets.md`)

**Approach:**
- Cut `develop` from `main` and push: `git switch -c develop main && git push -u origin develop`.
- Land the new/retargeted workflow files on `develop` first; ensure `main` carries no auto-build job (the old `release.yml` is removed in U5).
- Open one throwaway PR into `develop` so `ci.yml` emits its check runs **once** — capture the exact check names (`Analyze & Test (Linux)`, the Android build job) for U6's `required_status_checks` wiring (avoids the name-mismatch trap).
- Flip the GitHub default branch: `gh api repos/:owner/:repo -X PATCH -f default_branch=develop`.
- Strict ordering: bootstrap → first CI run (capture names) → apply rulesets (U6 last).

**Test scenarios:**
- Test expectation: none (one-time git/gh setup) — verification below.

**Verification:** `develop` exists, is the repo default, and a PR into it triggers `ci.yml`; rulesets are applied only after the first run captured check names.

---

- U1. **Add `scripts/ci/resolve-version.sh` + tests (version math)**

**Goal:** Extract prerelease/stable version resolution into one tested script the workflows call.

**Requirements:** R5, R6, R7, R8

**Dependencies:** None

**Files:**
- Create: `scripts/ci/resolve-version.sh`
- Create: `test/ci/resolve_version_test.sh` (or `scripts/ci/resolve-version.bats` — runner chosen at impl time)
- Modify: none yet

**Approach:**
- Modes `alpha|beta|stable`. Reads existing tags via `git tag -l --sort=-v:refname`.
- `alpha`: bump base from latest non-prerelease tag using the existing conventional-commit logic (port from `release.yml`), then `-alpha.(maxN+1)` for that base.
- `beta`: base from `$2` (branch-derived `X.Y.Z`), `-beta.(maxN+1)`.
- `stable`: emit `vX.Y.Z` from `$2`.
- Carry forward `release.yml`'s `IN_VERSION`/`IN_BUMP` override inputs (force an exact version or bump level) so the **first** alpha can be seeded deterministically without depending on a full-history conventional-commit scan — this sidesteps the documented "No releasable since v0.0.0" first-release anomaly (Context & Research). With no tags and no override, `alpha` bumps from an implicit `v0.0.0`.
- Emits `tag=` and `released=` on stdout/`$GITHUB_OUTPUT` style for workflow consumption.

**Execution note:** Implement test-first — the version math is the highest-risk logic in the plan and is pure/deterministic given a tag list.

**Patterns to follow:** `release.yml` lines 44–88 (existing bump bash).

**Test scenarios:**
- Happy path: no tags + `feat:` commit, mode `alpha` → `v0.1.0-alpha.1`. Covers AE2.
- Happy path: tags `[v0.1.0-alpha.1]`, another develop merge, mode `alpha` → `v0.1.0-alpha.2`.
- Happy path: mode `beta v0.1.0`, no beta tags → `v0.1.0-beta.1`. Covers F2.
- Happy path: tags `[v0.1.0-beta.1]`, mode `beta v0.1.0` → `v0.1.0-beta.2`.
- Happy path: mode `stable v0.1.0` → `v0.1.0`.
- Edge case: `fix:`-only since last stable, mode `alpha` → patch bump base.
- Edge case: `BREAKING CHANGE`/`type!:` → major bump base.
- Edge case: docs/chore-only since last stable, mode `alpha` → `released=false` (skip), no tag.
- Edge case: SemVer precedence — `--sort=-v:refname` returns `-alpha.10` after `-alpha.9` (numeric, not lexical) — assert N=11 not N=2.
- Happy path: forced `IN_VERSION`/`IN_BUMP` override (seeding) → emits exactly that version regardless of tag/commit scan (deterministic first-alpha seed).
- Error path: invalid mode or malformed base arg → non-zero exit with a clear message.

**Verification:** The test suite passes locally and the script prints the expected tag for each fixture tag-list.

---

- U2. **Retarget `ci.yml` to `develop`/`release/*` and make the build a required check**

**Goal:** PR gate runs on the new branches; the APK build becomes part of the gate (build-in-PR).

**Requirements:** R3, R4

**Dependencies:** U0

**Files:**
- Modify: `.github/workflows/ci.yml`

**Approach:**
- Change `on.pull_request.branches` from `[main]` to `[develop, release/**]`.
- Keep `analyze-and-test` (vs mock/emulator — the app's tests already run against the mock backend) and `build-android`; the build moving into the gate is what enforces "main never builds" upstream.
- Keep `submodules: recursive` + `just gen-proto`/protoc steps and pinned `protoc_plugin 21.1.2`.

**Patterns to follow:** existing `ci.yml` job structure.

**Test scenarios:**
- Happy path: open PR `feat/x → develop` → `Analyze & Test (Linux)` + Android build run and gate the merge. Covers AE1.
- Happy path: open PR into `release/0.1.0` → same checks run.
- Edge case: PR into `main` no longer triggers `ci.yml` (only promotion path reaches main) — confirm trigger scoping.
- Integration: a red analyze/test blocks merge into `develop`.

**Verification:** PRs into `develop` and `release/*` show the required checks; a PR into `main` from `release/*` does not re-run the full build gate here.

---

- U3. **Add `alpha.yml` — tag + publish alpha APK on push to `develop`**

**Goal:** Every merge to `develop` auto-tags `vX.Y.Z-alpha.N` and publishes the alpha APK as a prerelease Release.

**Requirements:** R5, R3, R8

**Dependencies:** U0, U1

**Files:**
- Create: `.github/workflows/alpha.yml`

**Approach:**
- `on.push.branches: [develop]` + `workflow_dispatch`.
- Call `scripts/ci/resolve-version.sh alpha`; if `released=true`, `gh release create vX.Y.Z-alpha.N --prerelease --generate-notes`, build the developer APK (`--dart-define=APP_ENV=stage`), upload as a Release asset.
- `permissions: contents: write`, default `GITHUB_TOKEN`.
- Reuse the proto-gen + Flutter setup steps from `release.yml`'s build job.
- Accepted deviation from "build-in-PR": this builds *post-merge* on `develop`. The PR gate (U2) already built the same tree, so a non-flake failure is unexpected; if a real failure occurs the merge has already landed — recovery is re-dispatch via `workflow_dispatch` (the develop code stays). This relocates the only build-can-fail-after-merge risk to `develop`, never `main` (R3 intact). Artifact-reuse from the PR build is the deferred optimization (Scope Boundaries).

**Patterns to follow:** `release.yml` `tag-release` + `build-and-upload` jobs; mark prerelease.

**Test scenarios:**
- Happy path: merge a `feat:` PR to `develop` → `v0.1.0-alpha.1` prerelease created with the alpha APK attached. Covers AE2.
- Edge case: docs/chore-only merge → no tag, no release (skip), workflow exits green.
- Edge case: second `feat:` merge before any release cut → `v0.1.0-alpha.2`.
- Integration: the build runs here (not on main) — confirms R3 holds while still publishing alphas.

**Verification:** A `feat:` merge to `develop` yields a `-alpha.N` prerelease with one APK asset; non-releasable merges produce none.

---

- U4. **Add `release-beta.yml` — build + tag + publish beta APK on `release/*`**

**Goal:** Pushes to a `release/X.Y.Z` branch build the release APK, tag `vX.Y.Z-beta.N`, and publish it as a prerelease Release asset (the artifact `main` will later promote).

**Requirements:** R6, R3

**Dependencies:** U1

**Files:**
- Create: `.github/workflows/release-beta.yml`

**Approach:**
- `on.push.branches: [release/**]` + `workflow_dispatch`.
- Derive base `X.Y.Z` from the branch name (`${GITHUB_REF_NAME#release/}`), call `resolve-version.sh beta X.Y.Z`.
- Build both APKs (production + developer) `--release` as `release.yml` does today, `gh release create vX.Y.Z-beta.N --prerelease`, upload both APKs as assets.
- Betas iterate: each push that warrants it bumps `-beta.N`.

**Patterns to follow:** `release.yml` `build-and-upload` job (signing fallback, APK rename, upload).

**Test scenarios:**
- Happy path: push to `release/0.1.0` → `v0.1.0-beta.1` prerelease with production + developer APKs. Covers F2.
- Happy path: a fix pushed to the same branch → `v0.1.0-beta.2`.
- Edge case: branch name not matching `release/X.Y.Z` → fail fast with a clear error.
- Integration: the beta APK asset is retrievable by tag (the promote step depends on it).

**Verification:** A `release/0.1.0` push produces a `v0.1.0-beta.N` prerelease carrying the built APKs.

---

- U5. **Add `promote.yml` — tag stable + copy beta APK on push to `main` (no build)**

**Goal:** Merging `release/X.Y.Z → main` tags `vX.Y.Z` and publishes the **already-built** beta APK by copying the asset — zero build on `main`.

**Requirements:** R7, R3

**Dependencies:** U4

**Files:**
- Create: `.github/workflows/promote.yml`
- Delete: `.github/workflows/release.yml` (its responsibilities are now split across alpha/beta/promote)

**Approach:**
- `on.push.branches: [main]` + `workflow_dispatch`.
- Derive `X.Y.Z` from the merged `release/X.Y.Z` branch name (the merge commit's source), then select the source beta tag explicitly: `git tag -l "vX.Y.Z-beta.*" --sort=-v:refname | head -1` (the highest `-beta.N`). `resolve-version.sh stable X.Y.Z` for the stable tag.
- `gh release create vX.Y.Z --generate-notes`; `gh release download <beta-tag> --dir dist`; **rename** each asset `sst-cam-app-<beta-tag>-{production,developer}.apk` → `sst-cam-app-vX.Y.Z-{production,developer}.apk` (bytes preserved — re-upload is a new asset, not a tag mutation); `gh release upload vX.Y.Z dist/*.apk`. **No Flutter/Gradle build step exists in this workflow** — this is the structural guarantee for R3/AE4.
- Optionally verify integrity before re-upload: compare the downloaded asset's SHA-256 against a digest recorded by `release-beta.yml` (defends against an asset being clobbered between beta publish and promote).
- Document (or automate) deleting the `release/X.Y.Z` branch and merging back to `develop`; if not automated, `promote.yml` emits a run-summary reminder so `develop` never silently diverges below `main`.

**Patterns to follow:** `gh release create` from `release.yml`; asset copy via `gh release download` + `gh release upload`.

**Test scenarios:**
- Happy path: merge `release/0.1.0 → main` → `v0.1.0` tagged, the `v0.1.0-beta.N` APKs appear on the stable Release. Covers AE4.
- Edge case: no matching beta Release for the version → fail fast (promotion must never silently rebuild).
- Edge case: workflow contains no build step — assert by inspection/CI lint that no `flutter build` runs on `main`. Covers R3.
- Integration: the promoted APK bytes equal the beta APK bytes (same artifact, not a rebuild).

**Verification:** `main` has zero failable build jobs; the stable Release reuses the beta artifact (same bytes, renamed); `.github/workflows/release.yml` no longer exists in the repo.

---

- U6. **Branch + tag rulesets for `develop`, `main`, `release/*`**

**Goal:** Enforce the branch model and required checks via GitHub rulesets.

**Requirements:** R1, R2, R3

**Dependencies:** U0, U2, U3, U4, U5 (required-check names must exist first)

**Files:**
- Create: `docs/ci/rulesets.md` (documented intent + the `gh api` commands / JSON used to apply them)

**Approach:**
- `develop`: PR required + green required checks (`Analyze & Test (Linux)`, Android build). (Default-branch flip happens in U0.)
- `main`: PR required + green required checks + block direct push/force-push/delete; admin/hotfix bypass only. The required check on the `main` PR is the release-branch head SHA's already-green check (see the Key Technical Decision on `main`'s required check) — **not** a re-run; verify GitHub surfaces it, else add the lightweight no-build assertion gate.
- `release/*`: require the beta checks (the same `Analyze & Test (Linux)` + Android build suite as `develop`, reported on `release/*` pushes).
- Tags: keep the existing immutable "Release Tags" ruleset; confirm it permits creating `-alpha.N`/`-beta.N`/stable names.
- Apply via `gh api` (per the established workflow); wire `required_status_checks` only after U2–U5 have run once and exact check names are known (per the first-run learning).

**Execution note:** Required-status-check names must be captured from a real CI run before wiring (avoids the name-mismatch trap noted in prior CI work).

**Test scenarios:**
- Test expectation: none (GitHub configuration) — verification is operational below.

**Verification:** A direct push to `main` is rejected; a `release/* → main` PR with red checks is blocked (AE3); `develop` is the default branch and rejects unreviewed pushes.

---

- U7. **Version reset to the `0.1.0-alpha` line (runbook)**

**Goal:** Remove the bogus `v0.1.0` tag + Release and seed the clean `0.1.0-alpha` line toward `0.1.0-beta.1`.

**Requirements:** R9, R10

**Dependencies:** U0, U3 (alpha workflow must exist to produce the first real alpha)

**Files:**
- Create: `docs/ci/version-reset-runbook.md`

**Approach:**
- One-time maintainer steps (admin only). The "Release Tags" ruleset blocks tag deletion, so the bypass is **mandatory, not "if needed"**: (1) org/repo admin temporarily disables the "Release Tags" ruleset (or adds self to its bypass list) via the GitHub UI — ruleset bypass actors can't be set reliably via JSON import; (2) `gh release delete v0.1.0 --yes --cleanup-tag` (or `gh release delete v0.1.0 --yes && git push origin :refs/tags/v0.1.0`); (3) verify `git tag -l 'v*'` shows no `v0.1.0` and no other bogus tags; (4) **re-enable the ruleset immediately**. Then let the first `feat:`-bearing `develop` merge mint `v0.1.0-alpha.1` (or seed via `alpha.yml` `workflow_dispatch` — see the seeding note in U1/U3).
- Precondition: confirm no consumer currently pins `v0.1.0`'s commit before deleting.
- Document the immediate target `0.1.0-beta.1` (joint firmware+app hardware test) and that `1.0.0` is the eventual first stable.

**Test scenarios:**
- Test expectation: none (operational runbook) — verification below.

**Verification:** `git tag -l` shows no bogus `v0.1.0`; the first develop alpha is `v0.1.0-alpha.1`.

---

- U8. **Docs: rewrite CI/CD section in `CLAUDE.md`, `AGENTS.md`, `README`**

**Goal:** Documentation matches the new branch model, ladder, tag/version convention, and flow.

**Requirements:** R11

**Dependencies:** U2, U3, U4, U5, U6

**Files:**
- Modify: `CLAUDE.md` ("CI/CD & releasing", "Branch + commit + tag rules", "Releasing")
- Modify: `AGENTS.md` (if present; create the CI/CD section if it mirrors CLAUDE.md)
- Modify: `README.md`

**Approach:**
- Replace the two-workflow description with the four-workflow model; document the maturity ladder (alpha vs mock+emulator, beta vs real firmware, stable shipped), the `vX.Y.Z[-alpha.N|-beta.N]` scheme, and the `feat/* → develop → release/X.Y.Z → main` flow.
- State the two non-negotiables: build-in-PR/tag-on-merge; main never builds.

**Test scenarios:**
- Test expectation: none (documentation) — verification below.

**Verification:** Docs describe four workflows, the ladder, and the tag scheme with no remaining references to "push to main auto-cuts a release."

---

## System-Wide Impact

- **Interaction graph:** `ci.yml` trigger retarget affects which PRs gate; `release.yml` deletion removes the only main-build job; new workflows key off `develop`/`release/**`/`main` pushes. The emulator (A4) backs alpha tests; the firmware device (A5) is the beta counterpart — cross-repo, coordinated via the sibling plans.
- **Error propagation:** A failed alpha build fails on `develop` (post-merge) but never on `main`; a failed beta build fails on `release/*`; promotion fails loudly if the beta asset is missing (never silently rebuilds).
- **State lifecycle risks:** Asset hand-off must promote the exact beta artifact; guard against re-tagging an existing version (tag immutability covers this). Version-counter races if two `develop` merges land near-simultaneously — accept (maintainer-paced) and note.
- **API surface parity:** Same branch/ladder/tag model must match firmware, proto, emulator (the other three plans).
- **Unchanged invariants:** Proto consumption (submodule + `just gen-proto`), the two-APK build recipe, debug-signing fallback, and all Flutter app code are unchanged.

---

## Risks & Dependencies

| Risk | Mitigation |
|------|------------|
| Required-status-check names wired before the check runs once → silent non-enforcement | Wire `required_status_checks` only after U0/U2–U5 run once; capture exact names (prior-CI learning). |
| `main`'s required check unrealizable — `ci.yml` not on `main` PRs so a `release/*→main` PR has no checks (AE3/AE4) | Require the release-head SHA's already-green check on the PR (Key Decision); verify GitHub surfaces it, else add a no-build assertion gate. |
| `develop` not created → every `develop`/`release/*` trigger references a missing branch | U0 bootstraps `develop` + default flip before any retarget. |
| Prerelease counter math wrong (lexical vs numeric N) | U1 tests assert numeric precedence (`-alpha.10` > `-alpha.9`). |
| `promote.yml` accidentally rebuilds on main | Structural: no build step in the workflow; U5 test asserts no `flutter build` present. |
| First post-reset alpha skipped (no baseline tag anomaly) | U7 seeds the line; `resolve-version.sh` handles the `v0.0.0` base explicitly. |
| Cross-repo drift (app ladder ≠ firmware/proto/emulator) | Plans authored together; same version contract documented in each. |

---

## Documentation / Operational Notes

- Two one-time operational runbooks: version reset (U7) and ruleset application (U6) — both maintainer/admin actions using `gh`.
- `0.1.0-beta.1` is a joint firmware+app hardware test; coordinate cut timing with the firmware plan.

---

## Sources & References

- **Origin document:** [docs/brainstorms/2026-06-17-cicd-workflow-standard-requirements.md](docs/brainstorms/2026-06-17-cicd-workflow-standard-requirements.md)
- Related code: `.github/workflows/ci.yml`, `.github/workflows/release.yml`
- Prior CI/CD work: memory `cicd-pipeline-plan`; `docs/plans/2026-06-10-001-feat-ci-cd-release-pipeline-plan.md`
