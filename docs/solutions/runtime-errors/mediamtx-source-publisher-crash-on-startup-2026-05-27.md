---
title: "mediamtx silently crashes on startup when source: publisher is set in paths config"
date: 2026-05-27
category: runtime-errors
module: mock-camera-wifi
problem_type: runtime_error
component: development_workflow
severity: high
symptoms:
  - RTSP port 8554 returns connection refused while port 8080 on the same container responds 200
  - supervisord restarts mediamtx continuously with no visible error output
  - ffmpeg cannot publish its stream and RTSP clients immediately get connection refused
  - Removing the service or restarting the container does not help — crash is on every start
root_cause: config_error
resolution_type: config_change
tags:
  - mediamtx
  - rtsp
  - docker
  - devcontainer
  - mock-camera-wifi
  - supervisord
related_components:
  - tooling
---

# mediamtx silently crashes on startup when source: publisher is set in paths config

## Problem

mediamtx v1.18.2 crashes silently on startup when its YAML config includes `source: publisher` under a path entry. In the mock-camera-wifi devcontainer service, this caused the RTSP port (8554) to be unreachable while the co-located HTTP download server continued serving on port 8080, making the failure look like a Docker networking or port-mapping issue.

## Symptoms

- RTSP port 8554 returns connection refused while port 8080 on the same container responds 200
- supervisord restarts mediamtx continuously with no visible error output
- ffmpeg cannot publish its stream; RTSP clients immediately get connection refused
- Removing the service or restarting the container does not help — crash is on every start

## What Didn't Work

- **Checking Docker port mappings** — the host-to-container port bindings were correct; the port was genuinely not listening, not just unmapped
- **Checking whether the container was running** — the container was up (8080 responded), so `docker ps` and health checks gave false confidence that the service was healthy
- **Restarting the service** — supervisord was already restarting mediamtx continuously; a manual restart changed nothing because mediamtx crashed again on the same config
- **Adding explicit auth config to mediamtx.yml** — the problem was the `source:` directive, not authentication; adding auth configuration did not prevent the crash
- **Assuming the bug was in Docker Compose networking** — the networking between containers was fine; only the mediamtx process was broken

## Solution

Remove the `source: publisher` line from the `paths` block in `mediamtx.yml`.

**Before (crashes mediamtx v1.18.2):**

```yaml
rtspAddress: :8554
paths:
  preview:
    source: publisher
```

**After (minimal working config):**

```yaml
rtspAddress: :8554
paths:
  preview:
```

By default, mediamtx v1.18.2 accepts any publisher and any reader without credentials (`authInternalUsers` defaults to `[{user: any, pass: any}]`), so no additional configuration is needed for an unauthenticated local dev stream.

## Why This Works

In mediamtx v1.18.2 the `source` field under a path accepts either a URL (for pull-mode streams) or one of a set of recognized sentinel values. The value `publisher` is not a valid `source` value in this version — it was either removed, renamed, or never valid. When mediamtx encounters the unrecognized value it fails during config parsing/initialization and exits immediately with a non-zero status code. supervisord catches the exit and schedules a restart — but since the config never changes, the process crashes on every attempt, producing a silent restart loop. Because supervisord itself stays up and the other managed processes (ffmpeg, download_server.py) are unaffected, the container appears healthy from the outside.

Removing the directive causes mediamtx to apply its built-in default for that path (accept any publisher), which is exactly the intended behavior for a no-auth local mock.

## Prevention

**Keep mediamtx configs minimal:**

Omit any directive that isn't strictly required. Defaults are well-chosen for local dev. Avoid `source: publisher` — it appears in older docs and forum posts but is not valid in mediamtx v1.x. If you need to extend the config, cross-reference the [mediamtx release notes](https://github.com/bluenviron/mediamtx/releases) for the exact version pinned in the Dockerfile.

**Diagnosing silent supervisord crash loops:**

When one port responds and another doesn't, check individual process status — not just container status:

```sh
docker exec <container> supervisorctl status
```

A process in `BACKOFF` or `FATAL` state confirms a crash loop even when the container overall is healthy. Check process-specific logs:

```sh
docker exec <container> supervisorctl tail mediamtx stderr
```

**Use a port-specific healthcheck:**

The mock-camera-wifi Dockerfile healthcheck pings `http://localhost:8080/health`, which only confirms the Python server is alive. A crashed mediamtx still passes this check. A more complete healthcheck would also probe the RTSP port:

```yaml
# docker-compose.yml
healthcheck:
  test: ["CMD-SHELL", "wget -qO- http://localhost:8080/health && nc -z localhost 8554"]
  interval: 10s
  start-period: 15s
  retries: 3
```

## Related

- `docs/plans/2026-05-26-011-feat-mock-camera-wifi-service-plan.md` — the implementation plan included `source: publisher` in the mediamtx config snippet; this was the upstream source of the incorrect setting
