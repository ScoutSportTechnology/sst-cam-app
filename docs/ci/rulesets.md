# GitHub rulesets — sst-cam-app (maintainer runbook)

> **APPLIED 2026-06-18.** These rulesets are **live**: `Release Tags` (tag),
> `development`, `main`, and `release-branches` (branch), all `enforcement: active`,
> with an **OrgAdmin bypass** actor. `development` requires `CI Scripts (shellcheck +
> version tests)` and `Analyze & Test (Linux)`; `main`'s required checks are
> **deferred** (see the open caveat below). Commands below are retained for
> reference / re-creation.
>
> **UPDATED 2026-06-25 (build-variant change):** the `Build Android APK` PR-gate
> job was removed (the APK now builds only on push — the alpha/beta release jobs),
> so it is **no longer a required check** on any ruleset. The required set is now
> `CI Scripts (shellcheck + version tests)` + `Analyze & Test (Linux)`.

Operational runbook for applying the branch + tag rulesets that enforce the
SST workflow standard. **This is a one-time maintainer/admin task** (U6 of the
[CI/CD workflow-standard plan](../plans/2026-06-17-001-feat-cicd-workflow-standard-plan.md));
the workflow YAML is already in the repo, but the rulesets that *require* its
checks are applied here, by hand, with `gh`.

> **Strict ordering.** Bootstrap `development` (U0) → land the workflows → let CI run
> **once** so the exact check-run names exist → only then wire
> `required_status_checks`. Wiring a required check before it has ever reported
> silently fails to enforce it (the name-mismatch trap from prior CI work).

## Intent

| Branch      | Rule                                                                                                                  |
| ----------- | ------------------------------------------------------------------------------------------------------------------- |
| `development`   | Default branch. PR required + green required checks (`CI Scripts (shellcheck + version tests)`, `Analyze & Test (Linux)`). No direct push. |
| `release/*` | PR required + the same beta checks (`CI Scripts (shellcheck + version tests)`, `Analyze & Test (Linux)`) reported on `release/*` PRs.       |
| `main`      | PR required + green required checks + **no direct push / force-push / delete** (admin/hotfix bypass only).           |
| `v*` tags   | Existing immutable "Release Tags" ruleset — allows compliant semver tag *creation*, blocks delete/update/force-push. |

The two non-negotiables this enforces:

1. **Gate-in-PR / build-and-tag-on-merge** — `Analyze & Test (Linux)` +
   `CI Scripts` are the required PR checks. The APK is **not** built in the PR
   (that throwaway job was removed); it builds only on push to
   `development`/`release/*` (the alpha/beta release jobs). A post-merge build
   failure lands on `development`/`release/*`, never on `main`, and is
   recoverable via re-dispatch.
2. **`main` never builds** — `release.yml` only copies an already-built beta
   asset; no `flutter build` runs on `main` (verify by inspection of the file).

## Required check names (capture from the first run)

Required-status-check contexts are the **job `name:` values**, not the job ids.
The PR gate jobs are folded into `release-alpha.yml` (`development`) and
`release-beta.yml` (`release/**`), gated to `pull_request`:

- `CI Scripts (shellcheck + version tests)` — `version-script` job.
- `Analyze & Test (Linux)` — `analyze-and-test` job.

(The `build-android` / `Build Android APK` PR job was removed in the
build-variant change — the APK builds only on push, so there is no PR-gate
APK check to require.)

> **Docs-only PRs show `Analyze & Test (Linux)` as _skipped_ — this is intended,
> not a misconfiguration.** A `changes` job (`dorny/paths-filter`) gates
> `analyze-and-test` on whether the PR touches build-relevant paths (`lib/`,
> `test/`, `android/`, `pubspec.*`, `.github/workflows/`, …). A docs/markdown-only
> PR skips the ~2-3 min job, and **a job skipped by its `if:` counts as SUCCESS
> for a required status check** (only a never-reported / perpetually-pending check
> blocks a merge), so the required `Analyze & Test (Linux)` context stays green
> without running. `CI Scripts (…)` is cheap and stays always-on. The push-side
> `paths-ignore` skips the post-merge APK build on docs commits. This mirrors
> `sst-cam-firmware`'s release workflows. **Do not "fix" a skipped Analyze & Test
> on a docs PR by removing the gate — that re-introduces the 2-3 min waste.**

Confirm the exact strings against a real run before wiring:

```bash
# After the first PR into development has run release-alpha.yml once:
gh api repos/:owner/:repo/commits/<head-sha>/check-runs \
  --jq '.check_runs[].name'
```

## Apply the rulesets

Run as a repo admin. Replace `OWNER/REPO` if `:owner/:repo` does not resolve.

### development — PR + green checks, default branch

```bash
# (Default-branch flip itself is U0:)
#   gh api repos/:owner/:repo -X PATCH -f default_branch=development

gh api repos/:owner/:repo/rulesets -X POST --input - <<'JSON'
{
  "name": "development protection",
  "target": "branch",
  "enforcement": "active",
  "conditions": { "ref_name": { "include": ["refs/heads/development"], "exclude": [] } },
  "rules": [
    { "type": "deletion" },
    { "type": "non_fast_forward" },
    { "type": "pull_request",
      "parameters": {
        "required_approving_review_count": 1,
        "dismiss_stale_reviews_on_push": false,
        "require_code_owner_review": false,
        "require_last_push_approval": false,
        "required_review_thread_resolution": false
      } },
    { "type": "required_status_checks",
      "parameters": {
        "strict_required_status_checks_policy": false,
        "required_status_checks": [
          { "context": "CI Scripts (shellcheck + version tests)" },
          { "context": "Analyze & Test (Linux)" }
        ]
      } }
  ]
}
JSON
```

### release/* — PR + the same beta checks

```bash
gh api repos/:owner/:repo/rulesets -X POST --input - <<'JSON'
{
  "name": "release branches protection",
  "target": "branch",
  "enforcement": "active",
  "conditions": { "ref_name": { "include": ["refs/heads/release/**"], "exclude": [] } },
  "rules": [
    { "type": "deletion" },
    { "type": "non_fast_forward" },
    { "type": "pull_request",
      "parameters": {
        "required_approving_review_count": 1,
        "dismiss_stale_reviews_on_push": false,
        "require_code_owner_review": false,
        "require_last_push_approval": false,
        "required_review_thread_resolution": false
      } },
    { "type": "required_status_checks",
      "parameters": {
        "strict_required_status_checks_policy": false,
        "required_status_checks": [
          { "context": "CI Scripts (shellcheck + version tests)" },
          { "context": "Analyze & Test (Linux)" }
        ]
      } }
  ]
}
JSON
```

### main — PR + green checks + block direct push

```bash
gh api repos/:owner/:repo/rulesets -X POST --input - <<'JSON'
{
  "name": "main protection",
  "target": "branch",
  "enforcement": "active",
  "conditions": { "ref_name": { "include": ["refs/heads/main"], "exclude": [] } },
  "rules": [
    { "type": "deletion" },
    { "type": "non_fast_forward" },
    { "type": "pull_request",
      "parameters": {
        "required_approving_review_count": 1,
        "dismiss_stale_reviews_on_push": false,
        "require_code_owner_review": false,
        "require_last_push_approval": false,
        "required_review_thread_resolution": false
      } },
    { "type": "required_status_checks",
      "parameters": {
        "strict_required_status_checks_policy": false,
        "required_status_checks": [
          { "context": "Analyze & Test (Linux)" }
        ]
      } }
  ]
}
JSON
```

> Admin/hotfix bypass: add bypass actors via the ruleset's **Bypass list** in the
> GitHub UI (bypass actors cannot be set reliably via JSON import — same caveat
> as the version-reset runbook).

### Tags — keep the existing "Release Tags" ruleset

No change. Confirm it still permits creating `vX.Y.Z-alpha.N`,
`vX.Y.Z-beta.N`, and `vX.Y.Z` names while blocking delete/update/force-push:

```bash
gh api repos/:owner/:repo/rulesets --jq '.[] | select(.target=="tag") | {id,name,enforcement}'
```

## OPEN CAVEAT — main's required check (verify before wiring main)

A `release/X.Y.Z → main` PR's head SHA **is** the release-branch tip, which
already carries a green `Analyze & Test (Linux)` check run from its `release/*`
PR. The intent is for the `main` ruleset to require that **already-green** run
on the PR — **no build re-runs on `main`**.

**Caveat to verify at implementation:** confirm GitHub surfaces the
release-head SHA's *push-event* check-run as a *status on the main PR* (same
SHA). If it does **not**, do **not** re-run the build on `main`; instead add a
lightweight `pull_request: [main]` no-build assertion gate that only asserts the
`vX.Y.Z-beta.N` Release/asset exists (a `gh release view` check, zero
`flutter build`), and require *that* context on `main` instead.

This caveat is **unresolved and deliberately left open** — resolve it against
live GitHub behavior before wiring `main`'s `required_status_checks`.

## Verification

- A direct push to `main` is rejected.
- A `release/* → main` PR with red checks is blocked (AE3).
- `development` is the repo default and rejects unreviewed pushes.
- `release.yml` contains no `flutter build` / Gradle step (grep the file).
