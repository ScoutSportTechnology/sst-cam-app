---
title: "feat: mock-camera-wifi Docker Service"
type: feat
status: active
date: 2026-05-26
origin: docs/brainstorms/2026-05-26-developer-settings-requirements.md
parent-plan: docs/plans/2026-05-26-010-feat-developer-settings-emulator-plan.md
---

# feat: mock-camera-wifi Docker Service

## Summary

A Docker Compose service that emulates the SST-Cam's WiFi Direct data plane — the two channels the real Jetson firmware exposes once a WiFi Direct group is established:

1. **RTSP H.264 live preview** on port `8554`, path `/preview` — served by [mediamtx](https://github.com/bluenviron/mediamtx) with a looping sample video pumped in by ffmpeg.
2. **HTTP recording download** on port `8080` — a lightweight HTTP/1.1 server that validates Bearer tokens and serves the sample MP4 with `Range` request support (resumable downloads).

The service lives at `.devcontainer/mock-camera-wifi/` and is wired into the devcontainer via Docker Compose (see parent plan U11). The Android app reaches it via `adb reverse tcp:8554 tcp:8554` and `adb reverse tcp:8080 tcp:8080`, so the app's RTSP and HTTP clients connect to `localhost` exactly as they do against real firmware.

This plan is self-contained. An implementing agent only needs this document and the files it references. The parent plan (`docs/plans/2026-05-26-010-feat-developer-settings-emulator-plan.md`) describes how the Flutter app side (`MockWifiService`, devcontainer migration) integrates with these ports.

---

## Problem Frame

The SST-Cam's WiFi Direct stack serves two independent protocols that the Flutter app's preview player (`flutter_vlc_player`) and download client both connect to directly:

- **RTSP H.264 preview** — the app opens an RTSP session to `rtsp://<group_owner_ip>:8554/preview`. Without a real camera, the RTSP client never gets exercised in development.
- **HTTP Range download** — the app issues `GET /recordings/{id}` with an `Authorization: Bearer <token>` header. Without a real server, the download code path degrades to a file-copy simulation.

The `MockWifiService` (parent plan U6) returns a `WifiDirectGroup` pointing to `localhost` on these ports. This service fulfills those ports so the app's actual code paths — RTSP client initialization, chunked HTTP download, progress reporting, Range resumption — are exercised during development without a physical Jetson camera.

The service must be installable on any developer machine by rebuilding the devcontainer with no manual setup steps.

---

## Requirements

These derive from parent plan U6's port contract and the `proto/wifi.proto` + `proto/bluetooth.proto` schemas:

- R1. RTSP stream available at `rtsp://0.0.0.0:8554/preview` continuously (loops when the video ends). No auth required for RTSP — the real firmware also does not gate the preview stream.
- R2. HTTP server listening on `0.0.0.0:8080`. Endpoints:
  - `GET /health` → `200 OK` with body `{"status":"ok"}`.
  - `GET /recordings/{id}` → serve the bundled sample MP4 with proper `Content-Length`, `Content-Type: video/mp4`, `Accept-Ranges: bytes`, and `206 Partial Content` on `Range` requests.
- R3. Bearer token validation on `GET /recordings/{id}`: `Authorization: Bearer <token>` header must be present and non-empty. The server accepts **any** non-empty token string (dev environment; no shared secret needed). Missing or empty token → `401 Unauthorized`.
- R4. The bundled sample MP4 is a short (≤30 s), valid H.264 file with audio strip, small enough to commit to the repo (`≤5 MB`). It is the same file served for all recording IDs.
- R5. The entire service is a single Docker image. No host-side ffmpeg, mediamtx, or Python installation required.
- R6. The service starts automatically when the devcontainer is built and stays running (`restart: unless-stopped`).
- R7. Ports `8554` (TCP) and `8080` (TCP) are exposed and mapped 1:1 to the host.
- R8. The `adb reverse tcp:8554 tcp:8554` and `adb reverse tcp:8080 tcp:8080` calls in `post-start.sh` (parent plan U11) are sufficient to bridge an attached Android device. No additional network config is required inside the service.

---

## Scope Boundaries

- No RTMP relay or outbound streaming. The Jetson's `gst-rtmp-src` publishes to YouTube/Twitch independently; the phone is never in that path.
- No TLS. The WiFi Direct link is a local WPA2 segment; encryption is at the WiFi layer.
- No per-session PSK or SSID generation. Credentials are hardcoded to `DIRECT-mock-sst-cam` / `dev-psk` in `MockWifiService`. The HTTP server does not enforce matching SSID.
- No mediamtx clustering, recording, or on-demand publishing. Single-path continuous loop only.
- The HTTP server does not store or return real recording metadata — it serves the same MP4 regardless of the `{id}` path segment, matching how the Flutter download client is expected to use the URL.
- Thumbnail endpoint (`/thumbnail`) — not implemented; the BLE path handles thumbnails without WiFi.

---

## Architecture

```
Host (devcontainer network)
  ├── app service (Flutter devcontainer)
  │     └── Android phone ←─ adb reverse ─── localhost:8554 / localhost:8080
  └── mock-camera-wifi service
        ├── mediamtx         (process 1)  — RTSP H.264 at :8554/preview
        ├── ffmpeg loop      (process 2)  — pushes sample.mp4 → mediamtx RTSP input
        └── download-server  (process 3)  — HTTP/1.1 at :8080 with Range + Bearer
```

All three processes run inside a **single container** managed by a `supervisord` or a minimal shell init script. Single-image design avoids inter-container networking and compose dependency ordering.

---

## Context & Research

### Key files in this repo

- `proto/wifi.proto` — `WifiDirectGroupResponse` (preview_port=8554, download_port=8080); `PreviewStreamDescriptor` (RTSP H.264, 640×360, 15 fps); download uses `Authorization: Bearer <auth_token>` from `DownloadTokenResponse.auth_token` in `bluetooth.proto`.
- `proto/bluetooth.proto` — `DownloadTokenResponse { recording_id, http_url, auth_token, expires_at }`. The `http_url` field carries the full download URL. **URL format decision**: the mock BLE emulator (parent plan U4) must construct `http_url` as `http://<group_owner_ip>:8080/recordings/<id>` — **without** a `.mp4` suffix. The `bluetooth.proto` comment shows `abc.mp4` as an illustrative example, but the actual URL format is implementation-defined. Omitting the extension keeps the download path a clean REST resource identifier and avoids a 404 when the server registers `/recordings/{id}` without extension.
- `lib/mock/emulator/mock_wifi_service.dart` (parent plan U6) — the client side; this service fulfills its expectations at `rtsp://localhost:8554/preview` and `http://localhost:8080/recordings/{id}`.
- `.devcontainer/docker-compose.devcontainer.yml` (parent plan U11) — compose file that launches this service alongside the `app` service.
- `.devcontainer/script/post-start.sh` (parent plan U11) — runs `adb reverse tcp:8554 tcp:8554 || true` and `adb reverse tcp:8080 tcp:8080 || true`.

### Technology choices

- **mediamtx** (formerly `rtsp-simple-server`) — lightweight Go binary, official Docker Hub image `bluenviron/mediamtx:latest`; supports inbound RTSP publish and outbound RTSP read; no transcoding needed.
- **ffmpeg** — loops the sample MP4 and re-publishes it as RTSP to mediamtx's ingest port (`rtsp://localhost:8554/preview`). Available in the Alpine `ffmpeg` package.
- **Python 3 http.server** extended with a `RangeHTTPServer` wrapper — zero-dependency, ships in Alpine's `python3` package, ≤50 lines of code. Handles `Range` headers and `401` for missing tokens. Alternatively, a small Go binary can be compiled in the Dockerfile for smaller image size; the Python approach is chosen for simplicity and auditability.
- **supervisord** (`s6-overlay` is also viable but heavier) — manages the three processes; configured via a minimal `supervisord.conf`. Alpine package: `py3-supervisor`.

---

## Key Technical Decisions

- **Single container, three processes via supervisord**: Avoids inter-container DNS and startup ordering complexity. supervisord restarts any process that exits (ffmpeg or the download server). The tradeoff is a slightly larger image (~200 MB), acceptable for a dev-only tool.

- **mediamtx ingest via RTSP publish (not direct file path)**: mediamtx supports both RTSP ingest and direct file reading (`runOnReady: ffmpeg ... -i sample.mp4 ...`). Using ffmpeg-as-publisher is more realistic (it exercises the RTSP publish path as the Jetson's `gst-rtsp-server` would) and makes it easy to replace the sample video without reconfiguring mediamtx.

- **Python RangeHTTPServer for downloads**: The Flutter download client uses `http` package's `HttpClient` which sends `Range: bytes=N-` on resumption. Python's built-in `http.server` does not handle `Range` by default; a ≤50-line subclass adds it. This keeps the Docker image's download server easily auditable and modifiable.

- **Accept any non-empty Bearer token**: `MockBleService.requestDownload()` (parent plan U4) returns a fixed `auth_token = 'dev-token'` in its proto response. The HTTP server validates that a `Bearer` header is present and non-empty — it does not check the value. This avoids coupling the server secret to the mock BLE emitter. Any future integration test can supply any token.

- **Sample video committed at ≤5 MB**: A 10–15 second clip at 640×360 H.264 baseline, 500 kbps, no audio — typically 500 KB–1 MB. Commit it at `.devcontainer/mock-camera-wifi/sample.mp4`. It doubles as both the RTSP preview source (ffmpeg loops it into mediamtx) and the HTTP download response (served verbatim).

- **No separate RTSP sample vs. download sample**: Using the same file for both is correct: in real usage, the preview stream is a separate live feed and the download is an on-device recording. For a mock, matching the video content between preview and download is an acceptable simplification and avoids maintaining two assets.

---

## Implementation Units

### S1. Project structure

**Goal:** Create the file skeleton under `.devcontainer/mock-camera-wifi/`.

**Files:**
- Create: `.devcontainer/mock-camera-wifi/Dockerfile`
- Create: `.devcontainer/mock-camera-wifi/supervisord.conf`
- Create: `.devcontainer/mock-camera-wifi/entrypoint.sh`
- Create: `.devcontainer/mock-camera-wifi/download_server.py`
- Create: `.devcontainer/mock-camera-wifi/mediamtx.yml`
- Add: `.devcontainer/mock-camera-wifi/sample.mp4` (bundled sample video — see S2)

**Approach:**
- Keep all service files self-contained under this directory. No files outside `.devcontainer/mock-camera-wifi/` except the compose reference and post-start.sh (managed by parent plan U11).
- The `Dockerfile` is the sole build artifact; `COPY` brings in all config files and the sample video.

---

### S2. Sample video

**Goal:** Provide a short, valid H.264 MP4 committed to the repo.

**Approach:**

Generate locally with ffmpeg (run once; commit the output):

```bash
ffmpeg -f lavfi -i "testsrc2=size=640x360:rate=15" \
       -f lavfi -i "sine=frequency=440:sample_rate=44100" \
       -t 10 \
       -c:v libx264 -profile:v baseline -level 3.0 \
       -b:v 500k -c:a aac -b:a 64k \
       -movflags +faststart \
       .devcontainer/mock-camera-wifi/sample.mp4
```

The `testsrc2` synthetic source produces a colorful test card with a timecode overlay — visually useful for verifying frame movement in the RTSP preview player. Audio is optional and can be stripped (`-an`) if even smaller size is needed.

Target: ≤2 MB, ≤10 s, H.264 baseline, 640×360, 15 fps. This satisfies R4.

**Alternative:** If the repo already has `assets/ble/mock-video.mp4`, evaluate whether it meets these specs before generating a new one (run `ffprobe assets/ble/mock-video.mp4` and compare resolution and codec). If it does, symlink or copy it here rather than maintaining two files.

---

### S3. mediamtx configuration

**Goal:** Configure mediamtx to accept an inbound RTSP publish at `/preview` and re-serve it.

**File:** `.devcontainer/mock-camera-wifi/mediamtx.yml`

**Key settings:**

```yaml
# Bind RTSP server to all interfaces
rtspAddress: :8554

# Allow any publisher without auth (internal ffmpeg only; not exposed beyond adb reverse)
authInternalUsers:
  - user: any
    pass: any
    ips: []
    permissions:
      - action: publish
        path: any
      - action: read
        path: any

paths:
  preview:
    # ffmpeg publishes here; readers consume from the same path
    source: publisher
```

mediamtx v1.x configuration format — verify the current `bluenviron/mediamtx:latest` tag and adjust key names if the major version has changed.

**Patterns:** mediamtx documentation at https://github.com/bluenviron/mediamtx — refer to the `paths` and `authInternalUsers` sections.

---

### S4. ffmpeg loop publisher

**Goal:** Continuously publish the sample video into mediamtx so the RTSP path is always live.

**In entrypoint.sh (or supervisord program):**

```bash
ffmpeg -re \
       -stream_loop -1 \
       -i /srv/sample.mp4 \
       -c copy \
       -f rtsp \
       -rtsp_transport tcp \
       rtsp://localhost:8554/preview
```

- `-re`: read at native playback rate (15 fps) to simulate a real camera.
- `-stream_loop -1`: loop indefinitely.
- `-c copy`: no re-encoding; pass H.264/AAC streams through as-is.
- `-rtsp_transport tcp`: avoids UDP fragmentation issues in the container bridge network.

supervisord restarts this process if it exits (mediamtx not yet ready on first start). A 2-second `sleep` before the first ffmpeg invocation in `entrypoint.sh` avoids the initial race.

---

### S5. HTTP download server

**Goal:** Serve `GET /recordings/{id}` with Bearer validation and Range support.

**File:** `.devcontainer/mock-camera-wifi/download_server.py`

**Key behaviors:**
- Listens on `0.0.0.0:8080`.
- `GET /health` → `200 {"status":"ok"}`. No auth required.
- `GET /recordings/{id}` — validate `Authorization: Bearer <token>` header (any non-empty token). Serve `/srv/sample.mp4` as the response body regardless of `{id}`.
  - Full response: `200 OK`, `Content-Type: video/mp4`, `Content-Length: <size>`, `Accept-Ranges: bytes`.
  - Range response: parse `Range: bytes=N-M` (or `bytes=N-`), respond `206 Partial Content` with correct `Content-Range` header and partial body.
- Any other path → `404 Not Found`.
- Missing or empty `Authorization` → `401 Unauthorized` with body `{"error":"unauthorized"}`.

**Implementation note:** Python's `http.server.BaseHTTPRequestHandler` gives direct access to headers and lets you write the response manually. A ≤50-line class that overrides `do_GET` covers all cases. No third-party packages required.

**Test scenarios (manual):**
- `curl http://localhost:8080/health` → `{"status":"ok"}` with status 200.
- `curl -H "Authorization: Bearer dev-token" http://localhost:8080/recordings/abc123` → MP4 bytes, status 200.
- `curl -H "Authorization: Bearer dev-token" -H "Range: bytes=0-999" http://localhost:8080/recordings/abc123` → first 1000 bytes, status 206, correct `Content-Range` header.
- `curl http://localhost:8080/recordings/abc123` (no auth) → status 401.

---

### S6. Dockerfile

**Goal:** Build a single image containing mediamtx, ffmpeg, Python 3, supervisord, and the sample video.

**File:** `.devcontainer/mock-camera-wifi/Dockerfile`

**Approach:**

```dockerfile
FROM bluenviron/mediamtx:latest AS mediamtx-bin

FROM alpine:3.21

# Install runtime dependencies
RUN apk add --no-cache ffmpeg python3 py3-supervisor

# Copy mediamtx binary from official image
COPY --from=mediamtx-bin /mediamtx /usr/local/bin/mediamtx

# Copy service files
COPY mediamtx.yml /etc/mediamtx/mediamtx.yml
COPY supervisord.conf /etc/supervisord.conf
COPY download_server.py /srv/download_server.py
COPY sample.mp4 /srv/sample.mp4
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 8554 8080

ENTRYPOINT ["/entrypoint.sh"]
```

Multi-stage build pulls the mediamtx binary from the official image to avoid compiling Go. Alpine base keeps the image under ~200 MB.

**Note:** Pin `bluenviron/mediamtx` to a specific minor version tag (e.g., `v1.12.0`) rather than `latest` to prevent unexpected breaks on mediamtx major releases. Check the latest stable tag at the time of implementation.

---

### S7. supervisord configuration

**Goal:** Keep all three processes running; auto-restart on failure.

**File:** `.devcontainer/mock-camera-wifi/supervisord.conf`

```ini
[supervisord]
nodaemon=true
logfile=/dev/null
logfile_maxbytes=0

[program:mediamtx]
command=/usr/local/bin/mediamtx /etc/mediamtx/mediamtx.yml
autostart=true
autorestart=true
stdout_logfile=/dev/fd/1
stdout_logfile_maxbytes=0
stderr_logfile=/dev/fd/2
stderr_logfile_maxbytes=0

[program:ffmpeg]
command=/bin/sh -c "sleep 2 && ffmpeg -re -stream_loop -1 -i /srv/sample.mp4 -c copy -f rtsp -rtsp_transport tcp rtsp://localhost:8554/preview"
autostart=true
autorestart=true
stdout_logfile=/dev/fd/1
stdout_logfile_maxbytes=0
stderr_logfile=/dev/fd/2
stderr_logfile_maxbytes=0

[program:download-server]
command=python3 /srv/download_server.py
autostart=true
autorestart=true
stdout_logfile=/dev/fd/1
stdout_logfile_maxbytes=0
stderr_logfile=/dev/fd/2
stderr_logfile_maxbytes=0
```

Logging to `/dev/fd/1` and `/dev/fd/2` forwards stdout/stderr to Docker logs — visible via `docker compose logs mock-camera-wifi`.

---

### S8. entrypoint.sh

**Goal:** Single entry point that launches supervisord.

**File:** `.devcontainer/mock-camera-wifi/entrypoint.sh`

```bash
#!/bin/sh
set -e
exec supervisord -c /etc/supervisord.conf
```

Minimal; supervisord takes over process management from here.

---

### S9. Docker Compose entry (in parent plan U11)

**Goal:** Wire the service into `.devcontainer/docker-compose.devcontainer.yml`.

This unit is owned by parent plan U11 but the spec belongs here.

**Service definition:**

```yaml
  mock-camera-wifi:
    build:
      context: .
      dockerfile: mock-camera-wifi/Dockerfile
    restart: unless-stopped
    ports:
      - "8554:8554"   # RTSP H.264 preview
      - "8080:8080"   # HTTP recording download
    volumes: []       # stateless; no mounts needed
```

The `context: .` is relative to `dockerComposeFile` in `devcontainer.json`, which points to `.devcontainer/docker-compose.devcontainer.yml`. The Dockerfile path `mock-camera-wifi/Dockerfile` is relative to that context.

---

### S10. post-start.sh update (in parent plan U11)

**Goal:** Bridge Android device's localhost to host ports 8554 and 8080.

This unit is owned by parent plan U11 but the spec belongs here.

**Append to `.devcontainer/script/post-start.sh`:**

```bash
# Bridge mock-camera-wifi ports to attached Android device (no-op if no device connected)
adb reverse tcp:8554 tcp:8554 2>/dev/null || true
adb reverse tcp:8080 tcp:8080 2>/dev/null || true
```

Place after the existing `setsid -f "$(dirname "$0")/adb-bridge.sh"` line. The `|| true` prevents post-start failure when no Android device is connected at container start.

---

## Integration Contract

This table defines the exact interface between the mock-camera-wifi service and the Flutter app (`MockWifiService`). Any change to either side must keep these values aligned.

| Signal | Value | Consumed by |
|--------|-------|-------------|
| RTSP preview URL | `rtsp://localhost:8554/preview` | `MockWifiService.previewDescriptor()` → VLC player |
| HTTP download base | `http://localhost:8080/recordings/{id}` (no `.mp4` suffix — `bluetooth.proto` comment is illustrative only) | `MockWifiService.downloadRecording()` |
| Bearer token validation | Any non-empty string | `MockBleService.requestDownload()` → returns `auth_token = 'dev-token'` |
| RTSP codec | H.264 | `PreviewCodec.PREVIEW_CODEC_RTSP_H264` in `wifi.proto` |
| Preview dimensions | 640×360 @ 15 fps | `PreviewStreamDescriptor` defaults in `MockWifiService` |
| Health endpoint | `GET /health` → `{"status":"ok"}` | devcontainer post-start readiness check (optional) |

---

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| mediamtx major version API break | Pin to a specific version tag in the Dockerfile; note the pinned version in a comment |
| ffmpeg not installed in Alpine mediamtx image | Multi-stage build copies only the binary; ffmpeg is installed separately via `apk` |
| adb reverse not persisting across device reconnection | Developer must re-run `adb reverse` (or reconnect the devcontainer) after re-plugging the device; document in `.devcontainer/mock-camera-wifi/README.md` |
| RTSP path not immediately available on container start | ffmpeg's 2-second startup delay in supervisord; app should retry RTSP connection (VLC does this by default) |
| `sample.mp4` file size exceeds git LFS thresholds | Check `.gitattributes` before committing; if LFS is configured, add `*.mp4 filter=lfs` or keep file ≤5 MB to avoid needing LFS |
| Python Range implementation incorrect | Manual `curl` tests in S5 verify all cases before merging; correct `Content-Range` is required for the Flutter download client's resumption logic |

---

## Verification

End-to-end manual verification steps after implementing all units:

1. `docker compose -f .devcontainer/docker-compose.devcontainer.yml build mock-camera-wifi` — image builds without errors.
2. `docker compose -f .devcontainer/docker-compose.devcontainer.yml up -d mock-camera-wifi` — service starts.
3. `curl http://localhost:8080/health` → `{"status":"ok"}`, status 200.
4. `curl -H "Authorization: Bearer dev-token" http://localhost:8080/recordings/test-id` → MP4 bytes, status 200, `Content-Type: video/mp4`.
5. `curl -H "Authorization: Bearer dev-token" -H "Range: bytes=0-999" http://localhost:8080/recordings/test-id` → 1000 bytes, status 206, `Content-Range: bytes 0-999/<total>`.
6. `curl http://localhost:8080/recordings/test-id` (no Bearer) → status 401.
7. `ffplay rtsp://localhost:8554/preview` — video plays and loops without freezing.
8. Attach Android device → `adb reverse tcp:8554 tcp:8554 && adb reverse tcp:8080 tcp:8080` → open the dev APK → connect a mock camera → navigate to preview → VLC player shows the test card video.
9. Navigate to a match with a recording → trigger download → progress bar increments → download completes.

---

## Sources & References

- **Parent plan:** [docs/plans/2026-05-26-010-feat-developer-settings-emulator-plan.md](docs/plans/2026-05-26-010-feat-developer-settings-emulator-plan.md) — U6 (MockWifiService), U11 (devcontainer compose migration)
- **Origin brainstorm:** [docs/brainstorms/2026-05-26-developer-settings-requirements.md](docs/brainstorms/2026-05-26-developer-settings-requirements.md)
- **WiFi proto contract:** `proto/wifi.proto` — `WifiDirectGroupResponse`, `PreviewStreamDescriptor`, `PreviewCodec`
- **Download auth contract:** `proto/bluetooth.proto` — `DownloadTokenResponse` (http_url, auth_token)
- **mediamtx:** https://github.com/bluenviron/mediamtx
