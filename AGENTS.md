# AGENTS.md

Guidance for coding agents working in **sst-cam-app**. For full architecture,
commands, and the contract-first design, read [`CLAUDE.md`](CLAUDE.md) — this
file mirrors its CI/CD contract and adds the rules an agent most often trips on.

## CI/CD & releasing

PR-gated, Conventional-Commit driven, on the SST branch model
`feat/* → development → release/X.Y.Z → main` with a test-fidelity **maturity
ladder**:

- **alpha** (`vX.Y.Z-alpha.N`) — automated tests vs **mock + emulator**; minted on every `development` merge.
- **beta** (`vX.Y.Z-beta.N`) — release candidate, manually validated vs **real firmware**; built on `release/*`.
- **stable** (`vX.Y.Z`) — shipped; the promoted beta artifact (same bytes), cut on merge to `main`.

**Two non-negotiables — do not break these:**

1. **Gate-in-PR / build-and-tag-on-merge** — `Analyze & Test (Linux)` + `CI
   Scripts` are the required checks on `development` / `release/*` PRs. The APK is
   **not** built in the PR; it builds only on push (the alpha/beta release jobs),
   so a post-merge build failure lands on `development` / `release/*`, never on
   `main`.
2. **`main` never builds** — `release.yml` only copies an already-built beta APK.
   Never add a `flutter` / Gradle step to `release.yml`.

Three branch-scoped workflows — each owns one branch class and folds its PR gate
in (gated to `pull_request`); there is no standalone `ci.yml`. Required PR checks:
`CI Scripts (shellcheck + version tests)`, `Analyze & Test (Linux)`. (The
`Build Android APK` PR-gate job was removed — the APK builds only on push.)

| Workflow | Owns | PR (`pull_request`) | Push |
| -------- | ---- | ------------------- | ---- |
| `release-alpha.yml` | `development` | the 2 gate checks | `resolve-version.sh alpha` → developer APK → `--prerelease` |
| `release-beta.yml` | `release/**` | the 2 gate checks | base = branch `X.Y.Z` → both APKs → `-beta.N` `--prerelease` |
| `release.yml` | `main` | — | tag `vX.Y.Z`, copy beta APK assets (no build) |

Version math is `scripts/ci/resolve-version.sh` (single source for both release
workflows; tested by `scripts/ci/resolve-version-test.sh` — run it after editing
the script). Default `GITHUB_TOKEN` only — no PAT/App; do not reintroduce
release-please. Signing falls back to debug when `ANDROID_*` secrets are unset.

### Branch + commit + tag rules

- `development` is the default branch; target `feat/*` / `fix/*` PRs at it. Do not
  target `main`.
- `main` is promote-only: no direct push; PR from `release/*` only.
- Tags `v*` are immutable semver (`-alpha.N` < `-beta.N` < stable).
- Use Conventional Commits; the subjects since the last stable tag drive the
  alpha base bump (`feat:` → minor, `fix:`/`perf:` → patch, `BREAKING`/`type!:` →
  major, docs/chore-only → **skip**).

### Operational runbooks (maintainer/admin, not agent-run)

- `docs/ci/rulesets.md` — apply the branch/tag rulesets.
- `docs/ci/version-reset-runbook.md` — reset to the `0.1.0-alpha` line.

## Scope guardrails

- CI/CD + docs changes here do **not** touch Flutter/Dart app code.
- Proto stays a git submodule consumed via `just gen-proto` (no Dart-package
  cutover). CI must keep `submodules: recursive` + the proto-gen steps with
  pinned `protoc_plugin 21.1.2`.
