# GitHub rulesets — sst-cam-app

The development, release-branches, and main rulesets require the `lint`,
`compile`, and `test` jobs in `.github/workflows/ci.yml`. All three jobs report
on PRs to `development`, `release/**`, and `main`. `lint` always runs; `compile`
and `test` skip docs-only PRs and PRs to `main` (a skipped job satisfies the
required check). No release APK is built in a PR; `compile` produces a debug
APK only. Run `just ci` locally before opening a PR.

`release.yml` handles pushes to `development` (alpha), `release/**` (beta/rc),
and `main` (promote the last rc without rebuilding). A release-branch dispatch
with `to: rc` promotes the latest beta after hardware sign-off. It calls
`publish.yml` to build and publish prereleases. Stable promotion copies only
the production APK, with SHA-256 verification. Only workflows mint tags.

`development` and `release/**` accept changes through PRs. `main` requires
Raul's approval before merge and never builds a release APK. The Release Tags
ruleset protects `v*` tags from update or deletion. Do not change rulesets as
part of an app PR.

To inspect check names and existing rulesets without changing settings:

```bash
gh api repos/:owner/:repo/commits/<head-sha>/check-runs --jq '.check_runs[].name'
gh api repos/:owner/:repo/rulesets --jq '.[] | {id,name,enforcement}'
```
