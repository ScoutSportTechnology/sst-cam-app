# GitHub rulesets — sst-cam-app (maintainer runbook)

Operational runbook for applying the branch + tag rulesets that enforce the
SST workflow standard. **This is a one-time maintainer/admin task** (U6 of the
[CI/CD workflow-standard plan](../plans/2026-06-17-001-feat-cicd-workflow-standard-plan.md));
the workflow YAML is already in the repo, but the rulesets that *require* its
checks are applied here, by hand, with `gh`.

> **Strict ordering.** Bootstrap `develop` (U0) → land the workflows → let CI run
> **once** so the exact check-run names exist → only then wire
> `required_status_checks`. Wiring a required check before it has ever reported
> silently fails to enforce it (the name-mismatch trap from prior CI work).

## Intent

| Branch      | Rule                                                                                                                  |
| ----------- | ------------------------------------------------------------------------------------------------------------------- |
| `develop`   | Default branch. PR required + green required checks (`Analyze & Test (Linux)`, `Build Android APK`). No direct push. |
| `release/*` | PR required + the same beta checks (`Analyze & Test (Linux)`, `Build Android APK`) reported on `release/*` pushes.   |
| `main`      | PR required + green required checks + **no direct push / force-push / delete** (admin/hotfix bypass only).           |
| `v*` tags   | Existing immutable "Release Tags" ruleset — allows compliant semver tag *creation*, blocks delete/update/force-push. |

The two non-negotiables this enforces:

1. **Build-in-PR / tag-on-merge** — the APK build is a required check on
   `develop`/`release/*` PRs, so a broken build blocks the merge.
2. **`main` never builds** — `promote.yml` only copies an already-built beta
   asset; no `flutter build` runs on `main` (verify by inspection of the file).

## Required check names (capture from the first run)

Required-status-check contexts are the **job `name:` values**, not the job ids:

- `Analyze & Test (Linux)` — `analyze-and-test` job in `ci.yml`.
- `Build Android APK` — `build-android` job in `ci.yml`.

Confirm the exact strings against a real run before wiring:

```bash
# After the first throwaway PR into develop has run ci.yml once:
gh api repos/:owner/:repo/commits/<head-sha>/check-runs \
  --jq '.check_runs[].name'
```

## Apply the rulesets

Run as a repo admin. Replace `OWNER/REPO` if `:owner/:repo` does not resolve.

### develop — PR + green checks, default branch

```bash
# (Default-branch flip itself is U0:)
#   gh api repos/:owner/:repo -X PATCH -f default_branch=develop

gh api repos/:owner/:repo/rulesets -X POST --input - <<'JSON'
{
  "name": "develop protection",
  "target": "branch",
  "enforcement": "active",
  "conditions": { "ref_name": { "include": ["refs/heads/develop"], "exclude": [] } },
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
          { "context": "Analyze & Test (Linux)" },
          { "context": "Build Android APK" }
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
          { "context": "Analyze & Test (Linux)" },
          { "context": "Build Android APK" }
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
          { "context": "Analyze & Test (Linux)" },
          { "context": "Build Android APK" }
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
already carries green `Analyze & Test (Linux)` + `Build Android APK` check runs
from its `release/*` push. The intent is for the `main` ruleset to require those
**already-green** runs on the PR — **no build re-runs on `main`**.

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
- `develop` is the repo default and rejects unreviewed pushes.
- `promote.yml` contains no `flutter build` / Gradle step (grep the file).
