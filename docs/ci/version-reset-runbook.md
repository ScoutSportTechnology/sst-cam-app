# Version reset to the 0.1.0-alpha line (one-time maintainer runbook)

The single `v0.1.0` tag + Release in this repo was **auto-cut by the old
`release.yml`** (push-to-main → build + tag) and corresponds to no real, tested
release. Under the new maturity ladder, `0.1.0` must come from the
`0.1.0-alpha.N → 0.1.0-beta.N → 0.1.0` progression, not a bare auto-cut. This
runbook removes the bogus tag/Release and seeds the clean line.

> **This is a one-time admin operation, not a workflow.** It is executed by hand,
> once, by a repo/org admin (U7 of the
> [CI/CD workflow-standard plan](../plans/2026-06-17-001-feat-cicd-workflow-standard-plan.md)).
> Do it **after** `develop` exists (U0) and `alpha.yml` is landed (U3), so the
> first real alpha can be minted immediately afterward.

## The maturity-ladder target

- `0.1.0-alpha.N` — automated test fidelity (app vs mock + emulator), minted on
  every `develop` merge.
- **`0.1.0-beta.1`** — the immediate target: the **joint firmware + app hardware
  test** (manual integration sign-off against a real firmware device). Coordinate
  its cut timing with the firmware plan; it is not a CI artifact of this plan.
- `1.0.0` — the **eventual first stable**, cut only after the beta line is signed
  off. We are explicitly **not** cutting `1.0.0` as part of this work.

## Precondition

Confirm **no consumer pins `v0.1.0`'s commit** before deleting (proto is
submodule-pinned independently; this is about anyone referencing the *app* tag):

```bash
git tag -l 'v*'                      # inventory existing tags
gh release view v0.1.0               # confirm it is the bogus auto-cut release
```

## Steps

The immutable **"Release Tags" ruleset blocks tag deletion**, so the bypass is
**mandatory, not optional**.

1. **Disable / bypass the tag ruleset (admin, GitHub UI).** Temporarily set the
   "Release Tags" ruleset to *Disabled*, or add yourself to its **Bypass list**.
   Ruleset bypass actors cannot be set reliably via JSON import — use the UI.

2. **Delete the bogus tag + Release:**

   ```bash
   gh release delete v0.1.0 --yes --cleanup-tag
   # equivalently:
   #   gh release delete v0.1.0 --yes
   #   git push origin :refs/tags/v0.1.0
   ```

3. **Verify nothing bogus remains:**

   ```bash
   git fetch --tags --prune
   git tag -l 'v*'        # must show NO v0.1.0 (and no other bogus tags)
   gh release list        # must show no v0.1.0 Release
   ```

4. **Re-enable the "Release Tags" ruleset immediately.** Do not leave the tag
   namespace unprotected.

## Seed the first alpha

With the line clean, mint `v0.1.0-alpha.1` either way:

- **Natural:** the next `feat:`-bearing merge into `develop` triggers `alpha.yml`
  → `resolve-version.sh alpha` bumps from the implicit `v0.0.0` base (no stable
  tag) → `v0.1.0-alpha.1`.
- **Seeded (deterministic):** dispatch `alpha.yml` manually to seed without
  waiting for a qualifying commit:

  ```bash
  gh workflow run alpha.yml -f version=v0.1.0     # → v0.1.0-alpha.1
  # or force the base bump level instead:
  #   gh workflow run alpha.yml -f bump=minor
  ```

  (`resolve-version.sh` carries `IN_VERSION` / `IN_BUMP` overrides precisely so
  the first alpha is deterministic, sidestepping the historical "No releasable
  since v0.0.0" full-history-scan anomaly.)

## Verification

- `git tag -l 'v*'` shows **no** bogus `v0.1.0`.
- The first `develop` alpha is `v0.1.0-alpha.1` (a `--prerelease` Release with
  one developer APK asset).
- The "Release Tags" ruleset is re-enabled.
