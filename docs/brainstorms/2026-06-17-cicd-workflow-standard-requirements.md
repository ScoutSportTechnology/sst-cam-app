---
date: 2026-06-17
topic: cicd-workflow-standard
---

# Git + CI/CD Workflow Standard — sst-cam-app

## Summary

Refactor this repo's branching, CI/CD, versioning, and docs to the org-wide SST workflow standard: `feat/* → develop → release/X.Y.Z → main`, a test-fidelity maturity ladder (alpha = isolated/automated against mock + emulator, beta = integrated against the real firmware device, stable = shipped), SemVer tags built before merge so `main` never runs a failable job, and a clean version reset to the `0.1.0-alpha` line toward a first `0.1.0-beta.1` (firmware+app integration) and an eventual `1.0.0`.

---

## Problem Frame

`main` runs `release.yml` that auto-cuts a release on every push — a failable post-merge job, so `main` can hold code whose release broke. There is no integration branch and no prerelease ladder. The single tag (`v0.1.0`) was auto-cut by the old flow and corresponds to no real, tested release. Features exist; no functional release and no candidate.

---

## Actors

- A1. **Contributor** — `feat/*`/`fix/*` branches, PRs into `develop`.
- A2. **Maintainer/admin** (you) — cuts release branches, manual beta integration sign-off, merges the release gate, manages rulesets/tags.
- A3. **CI** — checks + builds on PRs; tagged APK artifacts.
- A4. **sst-cam-emulator** — backs the app's alpha testing (mock + emulated firmware data).
- A5. **The firmware device (sst-cam-firmware on a Jetson)** — the beta integration counterpart over BLE/WiFi.

---

## The Workflow Standard (shared across all four SST repos)

**Branches**
- `feat/*`, `fix/*` — off `develop`. Free: no CI/CD while working.
- `develop` — always-green integration trunk (enforced by the PR gate).
- `release/X.Y.Z` — short-lived, cut from `develop`, deleted after merge to `main`; lets `develop` keep flowing during stabilization.
- `main` — final released code only; nothing builds here, it promotes the signed-off artifact.
- `hotfix/*` — off the `main` tag for urgent fixes.

**Maturity ladder (by test fidelity)**
- **alpha** — validated in *isolation, automatically*.
- **beta** — validated in *integration, by hand* (maintainer is the tester).
- **stable** — beta signed off and shipped.

**Versions & tags (SemVer 2.0)**
- Semantic version `X.Y.Z[-alpha.N|-beta.N]` (no `v`); git tag = version with a `v` prefix (tag-name convention only).
- `vX.Y.Z-alpha.N` on `develop` (auto) → `vX.Y.Z-beta.N` on `release/X.Y.Z` (gated/manual) → `vX.Y.Z` on `main` (stable). Order: `-alpha.N` < `-beta.N` < stable.
- Pre-1.0 (`0.MINOR.PATCH`): minor = feature, patch = fix, no stability guarantee. `1.0.0` = first real stable. Post-1.0: **major = breaks the proto/wire contract or a user-facing app contract**, minor = backward-compatible capability, patch = fix.

**The two non-negotiable rules**
- **Build-in-PR / tag-on-merge.** The failable build runs before a merge; a merge only tags/promotes already-validated code. `main` never builds.
- **`main`'s checks are gates, not re-runs** — promotion requires the release branch's checks green; they ran upstream.

**Flow**
```
feat/* ─PR: checks (incl. build)─► develop ─auto─► tag vX.Y.Z-alpha.N (alpha APK)
develop ─cut─► release/X.Y.Z ─build APK + tag vX.Y.Z-beta.N─► manual integration sign-off (with real firmware)
release/X.Y.Z ─PR (beta checks green)─► main ─► tag vX.Y.Z + publish beta APK ; delete release branch ; merge back to develop
hotfix: off main tag → fix → vX.Y.(Z+1) → main → back to develop
```

**Release trigger** — automated bump from Conventional Commits + one human gate (maintainer merges the release). Beta→stable sign-off manual for now.

---

## This repo's specifics

- **Artifact:** the application build (APK / app package).
- **alpha** = built + tested **against mock + emulated data** (the `sst-cam-emulator` bridge stands in for a real firmware device). Isolated, automated — no real hardware. This is the rung where most app development is validated.
- **beta** = the app package tested **alongside a real firmware device** (real BLE/WiFi against `sst-cam-firmware` on a Jetson). Manual maintainer sign-off — the firmware↔app contract working end-to-end on hardware.

---

## Key Flows

- F1. **Feature → develop (alpha).** PR `feat/x → develop` → checks (incl. build + tests against mock/emulator) → green + review → merge → tag `vX.Y.Z-alpha.N` + publish alpha APK. Covers: R1, R4, R5.
- F2. **Cut release candidate (beta).** Maintainer cuts `release/X.Y.Z`; CI builds the APK + tags `vX.Y.Z-beta.N`; maintainer tests it against the real firmware device; fixes → `-beta.2`… until sign-off. Covers: R3, R6, R9.
- F3. **Promote to stable.** PR `release/X.Y.Z → main` (beta checks green) → tag `vX.Y.Z` + publish the already-built APK; delete release branch; merge back to develop. Covers: R3, R7.

---

## Requirements

**Branch model & protection**
- R1. Create a long-lived `develop` branch; default target for `feat/*`/`fix/*`.
- R2. Rulesets: `develop` requires PR + green checks; `main` requires PR + green required-status-checks + no direct push (admin/hotfix bypass only); `release/*` requires the release checks.
- R3. `main` runs **no failable build/publish job**; builds/publishes happen on PRs / `develop` / `release/*`.

**CI/CD pipelines**
- R4. Rework `ci.yml` to run on PRs into `develop` (and `release/*`); the app's automated tests run against mock + emulator.
- R5. On merge to `develop`, auto-build + tag `vX.Y.Z-alpha.N` and publish the alpha APK (build-in-PR; merge tags already-validated code).
- R6. On `release/X.Y.Z`, build the release APK + tag `vX.Y.Z-beta.N`; betas iterate on the branch.
- R7. Replace `release.yml`'s auto-cut-on-push-to-`main` with the release-branch→main promotion: tag `vX.Y.Z` + publish the already-built beta APK, no rebuild on `main`.
- R8. Adopt Conventional Commits as the automated bump source.

**Versioning reset**
- R9. Delete the bogus `v0.1.0` tag + release; re-establish the clean scheme at the `0.1.0-alpha` line.
- R10. Consolidate work done under `0.1.0-alpha.N`; immediate target `0.1.0-beta.1` (joint firmware+app hardware test). `1.0.0` = eventual first stable.

**Documentation**
- R11. Update `CLAUDE.md`/`AGENTS.md`, `README`, and any build/release docs to the new model, ladder, tag/version convention, and flow.

---

## Acceptance Examples

- AE1. *When a PR is opened into `develop`*, the app's checks (build + tests against mock/emulator) run and must be green before merge. Covers: R1, R4.
- AE2. *When a commit merges to `develop`*, CI tags `vX.Y.Z-alpha.N` and publishes the alpha APK. Covers: R5, R3.
- AE3. *When a `release/X.Y.Z → main` PR has red beta checks*, the merge is blocked. Covers: R2, R3.
- AE4. *When the release PR merges to `main`*, `vX.Y.Z` is tagged and the already-built APK is published — no build runs on `main`. Covers: R7, R3.

---

## Success Criteria

- `main` has zero failable build/publish jobs.
- alpha development is fully exercisable against the emulator without hardware; beta requires a real device.
- Clean SemVer tags/releases; `0.1.0-beta.1` cut and tested against the real firmware.
- Same branch/ladder/tag model as firmware, proto, emulator.

---

## Scope Boundaries

- No external-tester cohorts; no nightly.
- No maintenance branches / backporting (latest-only-supported).
- Not cutting `1.0.0`.
- Implementation specifics (workflow YAML, ruleset JSON, bump-tool config) → plan.

---

## Key Decisions

- Build-in-PR / tag-on-merge; `main` never builds.
- Short-lived `release/X.Y.Z` branch so `develop` keeps flowing.
- alpha = against mock+emulator; beta = against real firmware (test-fidelity ladder).
- SemVer version `X.Y.Z`; git tag `vX.Y.Z`.
- Reset existing tags/releases; start at `0.1.0-alpha`.

---

## Dependencies / Cross-repo Coordination

- **proto** is the contract; a proto major forces a major here.
- **emulator** backs the app's alpha testing — alpha quality depends on the emulator being current with the contract.
- **firmware** is the beta counterpart — `0.1.0-beta.1` is a joint firmware+app hardware test; the app and firmware plans likely run **hand-in-hand / simultaneously**.

---

## Outstanding Questions

- Bump/changelog automation tool — chosen at plan time.
- How app alpha pins the emulator/proto versions it tests against.
