# Cross-Repo Coordination

Tracks handoffs and standing context between **sst-cam-app** and the repos it
coordinates with.

## Directory convention

```
docs/cross-repo/<repo>/
├── context.md       # who that repo is, how it relates to us, standing assumptions
├── coordination.md  # what a change on either side forces us to do
├── inbound/         # handoffs that arrived FROM that repo (we act on them)
└── outbound/        # handoffs we authored FOR that repo (they act on them)
```

Direction is **relative to this repo (sst-cam-app)**:

| Folder | Means |
|--------|-------|
| `inbound/` | The handoff originated in the other repo or was triggered by their session. We read it, act on it, and fill its `Response` section when done. |
| `outbound/` | We authored the handoff and sent it to the other repo's session. They act on it. |

`inbound/` and `outbound/` are created when the first handoff appears.

Each handoff doc carries `source_repo:` and `target_repo:` frontmatter so
direction is unambiguous regardless of folder.

## Repos

| Folder | Repo | Relationship |
|--------|------|-------------|
| `firmware/` | SST-Cam firmware (Jetson) | BLE command partner; overlay compositor; WiFi Direct group-owner |
| `proto/` | sst-cam-proto | Shared wire-format submodule; source of truth for all proto types |

## Handoff template

```markdown
---
date: YYYY-MM-DD
source_repo: <this-repo | other-repo>
target_repo: <other-repo | this-repo>
kind: <question | change-request | co-development | interaction-change>
status: <open | responded | closed>
---

## Context

<!-- What triggered this handoff. Link the plan or feature. -->

## Request / Finding

<!-- What we need the other repo to do or answer. Be concrete. -->

## Impact

<!-- What changes on the acting side once this is resolved. -->

## Acceptance criteria

<!-- How we know the handoff is complete. -->

## Response

<!-- Filled in by the acting repo when the handoff is resolved. -->
```
