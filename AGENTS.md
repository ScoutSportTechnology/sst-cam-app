# AGENTS.md

Guidance for coding agents working in **sst-cam-app**. For full architecture,
commands, and the contract-first design, read [`CLAUDE.md`](CLAUDE.md) — this
file mirrors its CI/CD contract and adds the rules an agent most often trips on.

## CI/CD & releasing

PR-gated, Conventional-Commit driven, Git Flow (same model in proto, firmware,
app; levels are tags, not branches):

- **alpha** (`vX.Y.Z-alpha.N`) — every releasable `development` merge; mock + emulator tests; developer APK.
- **beta** (`vX.Y.Z-beta.N`) — `release/X.Y.Z`, cut from `development` at feature freeze; fixes only; both APKs.
- **rc** (`vX.Y.Z-rc.N`) — after the hardware test (phone + real firmware on a Jetson): `promote-rc.yml` re-tags the newest beta as `rc.1`; later `release/X.Y.Z` merges mint `rc.N`.
- **stable** (`vX.Y.Z`) — merge `release/X.Y.Z → main`; the last rc's production APK promoted unchanged.

**Two non-negotiables — do not break these:**

1. **Gate-in-PR / build-and-tag-on-merge** — `Analyze & Test (Linux)` + `CI
   Scripts` are the required checks on `development` / `release/*` PRs. The APK is
   **not** built in the PR; it builds only on push (the alpha/beta release jobs),
   so a post-merge build failure lands on `development` / `release/*`, never on
   `main`.
2. **`main` never builds** — `release.yml` only promotes an already-built rc APK.
   Never add a `flutter` / Gradle step to `release.yml`.

Required PR checks (names wired into the rulesets — keep byte-identical):
`CI Scripts (shellcheck + version tests)`, `Analyze & Test (Linux)`.

| Workflow | Owns | PR (`pull_request`) | Push / dispatch |
| -------- | ---- | ------------------- | --------------- |
| `release-alpha.yml` | `development` | the 2 gate checks (incl. proto pin check) | `resolve-version` (alpha) → developer APK → `publish-release` |
| `release-beta.yml` | `release/**` | the 2 gate checks | `resolve-version` (release: beta.N or rc.N) → both APKs → `publish-release` |
| `promote-rc.yml` | `release/X.Y.Z` (dispatch) | — | newest beta → `rc.1`, same commit + APKs |
| `release.yml` | `main` | — | `promote` last rc → `vX.Y.Z`, production APK copied (no build) |

Version math and publishing are the shared actions of
`ScoutSportTechnology/.github` (`resolve-version`, `publish-release`, `promote`,
pinned `@v1.1.0`). Default `GITHUB_TOKEN` only — no PAT/App; do not reintroduce
release-please. Signing falls back to debug when `ANDROID_*` secrets are unset.

### Branch + commit + tag rules

- `development` is the default branch; target `feat/*` / `fix/*` PRs at it. Do not
  target `main`. `release/X.Y.Z` takes `fix/*` PRs only, after the cut.
- One `release/X.Y.Z` open at a time; the same branch names in proto, firmware
  and app (`feat/<slug>` for a cross-repo change: proto first, then re-pin
  `proto/` to the **merged** proto commit).
- `main` is promote-only: no direct push; PR from `release/*` only.
- Tags `v*` are immutable semver (`-alpha.N` < `-beta.N` < `-rc.N` < stable).
- Use Conventional Commits; the squash-merge subjects drive the alpha bump
  (`feat:` → minor, `fix:`/`perf:` → patch, `type(scope)!:`/`BREAKING CHANGE:` →
  major but minor while the major is 0, docs/chore-only → **skip**).

### Operational runbooks (maintainer/admin, not agent-run)

- `docs/ci/rulesets.md` — apply the branch/tag rulesets.
- `docs/ci/version-reset-runbook.md` — reset to the `0.1.0-alpha` line.

## Scope guardrails

- CI/CD + docs changes here do **not** touch Flutter/Dart app code.
- Proto stays a git submodule consumed via `just gen-proto` (no Dart-package
  cutover). CI must keep `submodules: recursive` + the proto-gen steps with
  pinned `protoc_plugin 21.1.2`.
