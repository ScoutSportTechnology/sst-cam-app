# SST-Cam Firmware Contract

_Last updated: 2026-07-07 | Version: 2 | Companion app version: see `DeviceInfoResponse.protocol_version` (expected: 4)_

This document is the **single source of truth for firmware development**. It describes what the SST-Cam firmware must implement to work correctly with the companion app, how communication is structured, and explicit constraints the firmware must respect. When this document and the proto files conflict, the proto files win — but that indicates this document needs updating.

---

## 0.1. Overlay model (v2 — firmware-unilateral, clean recording) — READ FIRST

As of Phase D #6 the overlay is **firmware-unilateral** and recordings are **clean**:

- **Live stream:** the camera composites the scoreboard overlay onto the RTSP preview only. The app draws no overlay of its own, live or on playback.
- **Recording (L1):** the recorded MP4 is **clean** — the overlay is **never** burned into it. Alongside `<matchId>.mp4`, the camera persists the overlay as a **timeline** file `<matchId>.timeline.json` (an `anchor_ms` plus the ordered scene changes shown during the recording).
- **Overlaid copy (L2), on demand:** when the app asks for an overlaid clip, the camera decodes the clean L1, composites the persisted timeline, and encodes a separate **L2** into `videos/exports/`, exposed for a single tokened download. This is offline/CPU-bound (no NVENC) and is **refused while a match is live** (`ResponseStatus.LIVE_SESSION_ACTIVE`).
- **New commands** (additive over proto `v0.1.0-beta.2`): `ExportOverlayedCommand` + `PollExportCommand` (the burn/poll flow) and `SetPreviewLayoutCommand` (single vs side-by-side dual-camera preview).

Sections below that still describe "overlay baked into the recorded footage" predate this model; where they conflict, **§0.1 wins**.

---

## 1. Architecture principle: app is source of truth

The companion app (Flutter, Android/iOS) owns **all business data**:
- Users and profiles
- Teams, rosters, player info
- Match configurations (sport, periods, period length)
- Streaming destinations and credentials
- Recording metadata and download history

**The camera is a stateless executor.** It:
- Receives a session configuration once per session and holds it in memory
- Reacts to events pushed by the app (recording start/stop, match events, score updates)
- Renders overlays on the live RTSP stream **only**; records a **clean L1** and persists the
  overlay as a `<matchId>.timeline.json` sidecar, burning an overlaid L2 on demand (see §0.1)
- Produces video files addressable by the app-generated `match_uuid`
- Serves files over HTTP for download

**The camera never:**
- Persists business data across sessions
- Pushes unsolicited data to the app
- Makes decisions about what to record or how to configure a session without being told
- Acts as a match timer authority (the app is the clock)

---

## 2. Dual-channel architecture

The app uses two separate radio links simultaneously. BLE is always on and handles all
control. WiFi Direct carries all bulk data (video stream + file downloads) and is only
active while a camera is connected.

```
┌─────────────────────────────────────────────────────────────────────┐
│                            PHONE (App)                              │
│                                                                     │
│   BLE radio (always on)          WiFi radio (active while paired)  │
└──────────┬──────────────────────────────────┬───────────────────────┘
           │                                  │
           │  Bluetooth 5.x                   │  802.11 P2P (WiFi Direct)
           │  Low power, small payloads        │  High bandwidth, local only
           │  Commands & responses             │  Video stream + file downloads
           │                                  │
┌──────────┴──────────────────────────────────┴───────────────────────┐
│                            JETSON (Camera)                          │
│                                                                     │
│   BlueZ via D-Bus (sdbus-c++)         wpa_supplicant (P2P)          │
│   BLE peripheral + GATT service       WiFi Direct Group Owner       │
│   Command Write + Command Response    gst-rtsp-server  :8554        │
│                                       HTTP download server :8080    │
└─────────────────────────────────────────────────────────────────────┘
```

### What goes over each channel

| Channel | Data | Direction |
|---------|------|-----------|
| BLE | All commands and responses (GetDeviceInfo, GetTelemetry, PushSessionConfig, RecordingControl, MatchControl, etc.) | Bidirectional (app writes, camera notifies) |
| BLE | `StartWifiDirectCommand` / `WifiDirectGroupResponse` — WiFi credentials | BLE-transported |
| WiFi Direct / RTSP | Live H.264 preview stream (scoreboard overlay included) | Camera → Phone |
| WiFi Direct / HTTP | Recording file downloads (byte-range, bearer auth) | Camera → Phone |

The phone **keeps its cellular connection** while on WiFi Direct. The camera can reach RTMP streaming servers through the phone's internet connection (tethering). WiFi Direct is a local-only link.

---

## 3. Connection handshake

### 3.0. Universal connect handshake (state-health cycle, proto §9b)

**Every connect runs the same handshake** — first connect, manual reconnect, app
relaunch, camera reboot — because a session OUTLIVES the BLE connection (the
firmware keeps recording/streaming through app disconnects, bounded by
`PushSessionConfigCommand.auto_stop_minutes`). Immediately after the GATT
channel is up, and **before treating the device as connected**, the app sends,
in order:

1. `GetDeviceInfoCommand` — protocol gate. The app refuses the session on a
   `protocol_version` skew (current expected version: **4**) and drops the link.
2. `SetDeviceTimeCommand` (phone epoch ms) — fixes the device wall clock.
   Firmware must apply it to the system clock and reject implausible values
   (pre-2020 epoch) with `ERROR`, leaving the clock untouched.
3. `GetSessionSnapshotCommand` — pure read of the firmware's ACTUAL state
   (`SessionSnapshotResponse`: session phase, active camera, preview layout,
   recording/streaming/raw flags, recording elapsed, match state incl.
   `match_uuid`, per-camera health, last-session summary, wifi_group_up). The
   app **adopts** these values instead of force-resetting selections — the
   firmware must therefore report its real current selections, not defaults.
4. Reconcile: when the app holds persisted match data for the running
   `match_uuid`, it pushes an absolute `SetMatchStateCommand` carrying app
   scores only (absent fields must be left untouched — the firmware clock is
   authoritative and is never overwritten on reconnect).

Any step failing (or timing out) makes the app drop the link — the firmware
must tolerate a disconnect at any point in this sequence. Telemetry and
match-state polling start **only after** the handshake completes.

The app leans on three snapshot/poll contract points for scoreboard survival
(U2), so the firmware must report them faithfully:

- `MatchState.elapsed_seconds` / `clock_running` — the app adopts the
  firmware clock outright on every rejoin AND corrects its local clock from
  every ~2 s match-state poll (an adopted elapsed past the configured period
  length auto-fires one `MATCH_PERIOD_END`). `elapsed_seconds` must be
  monotonic per period and NOT clamped at the period length.
- `last_session` (idle snapshots only, with `match_uuid` + `end_reason` +
  `end_clock_seconds` + `file_valid`) — a reconnecting app uses it to explain
  "ended while away" and to finalize its library entry; it matches the
  summary against its persisted match's uuid and ignores it otherwise.
- Telemetry `is_recording` — the app treats an observed true→false edge
  without an app command as firmware truth (auto-stop / recovery) and follows
  it instead of erroring, so the flag must reflect the real encoder state.

### 3.1. WiFi Direct credential exchange

**The WiFi Direct credential exchange happens automatically as part of connecting.**
The app sends `StartWifiDirectCommand` immediately after the BLE connection is established
and device info is confirmed. No user action is required. The app will not enable any
feature that depends on the data channel (live preview, recording control, file downloads)
until the WiFi Direct group is up and the phone has joined it.

```
App                                    Camera
───                                    ──────

[User taps a device in the scan list]

BLE connect ─────────────────────────► GATT service ready

──── Step 1: identify the device (protocol gate) ──────────────────────

→ GetDeviceInfoCommand
← DeviceInfoResponse
    device_id:        "sst-cam-a1b2c3d4"   ← stable hardware UUID
    firmware_version: "1.0.0"
    protocol_version: 4                    ← app refuses the session on skew

──── Step 1b: fix the device clock, read actual state (§3.0) ───────────

→ SetDeviceTimeCommand { epoch_ms }
← CommandResponse (status only)
→ GetSessionSnapshotCommand
← SessionSnapshotResponse (phase, selections, activity, match state, health)
→ SetMatchStateCommand (only when the app holds the running match's data)
← CommandResponse (status only)

──── Step 2: start telemetry stream (only after the handshake) ─────────

→ GetTelemetryCommand (repeated every ~1 s for the lifetime of the connection)
← DeviceTelemetry
    storage_free_bytes, storage_total_bytes
    wifi_state, wifi_ssid, wifi_signal_dbm
    temp_celsius, ram_used_pct, cpu_used_pct
    is_recording, is_streaming
    battery_level_pct

──── Step 3: bring up WiFi Direct (automatic, non-optional) ────────────

→ StartWifiDirectCommand
← WifiDirectGroupResponse
    ssid:           "DIRECT-sst-cam-0001-x7k"
    psk:            "Kp9mQ3rZnXwY"          ← per-session random PSK
    group_owner_ip: "192.168.49.1"
    preview_port:   8554
    download_port:  8080
    role:           "GROUP_OWNER"

[Phone joins the WiFi Direct group on its WiFi interface.
 Cellular stays connected for internet access.]

──── Connection ready ──────────────────────────────────────────────────

[App enables: live preview, session setup, recording controls, file downloads]
[RTSP stream at rtsp://192.168.49.1:8554/preview is now accessible]
[HTTP server at http://192.168.49.1:8080 is now accessible]
```

**The camera must:**
- Complete the WiFi Direct group setup before responding to `StartWifiDirectCommand`
- Start the RTSP preview server and HTTP download server before sending `WifiDirectGroupResponse`
- Generate a new random PSK for every connection; never hardcode or reuse

---

## 4. BLE discovery

The firmware **MUST** do both of the following or the app will not show the camera in the device list:

1. **Advertise the SST-Cam service UUID** in the BLE advertising payload:
   ```
   Service UUID: A1B2C3D4-0001-0000-8000-00805F9B34FB
   ```

2. **Set the BLE device name** to `sst-cam-NNNN` where NNNN is a zero-padded 4-digit unit number (e.g. `sst-cam-0001`).

The app filters on UUID first (primary) and name prefix `sst-cam-` (secondary). Both must match.

---

## 5. GATT service layout

| Role | UUID | Properties |
|------|------|------------|
| SST-Cam Service | `A1B2C3D4-0001-0000-8000-00805F9B34FB` | — |
| Command Write | `A1B2C3D4-0011-0000-8000-00805F9B34FB` | Write Without Response |
| Command Response | `A1B2C3D4-0012-0000-8000-00805F9B34FB` | Notify |

Only two characteristics. All control data flows through them. No dedicated notification characteristics for telemetry or any other periodic data.

> **UUID note:** These are placeholders. Replace with officially registered UUIDs before production; the layout must not change.

---

## 6. Communication model: app initiates, camera responds

**The app is always the initiator.** The camera never pushes unsolicited data.

```
App                                     Camera
───                                     ──────

Writes Command bytes ─────────────────► Command Write characteristic
                                        (camera processes the command)
Notification handler ◄─────────────── Command Response characteristic notify
matches correlation_id
```

Every write on Command Write must produce exactly one notify on Command Response carrying a matching `correlation_id`. The camera **must respond to every command** — if it cannot fulfill one, respond with `status = ERROR` and a descriptive `error_message`. For deferred features respond with `status = UNSUPPORTED`.

---

## 7. MTU and chunking

Request MTU 512 bytes after connect. Minimum guaranteed is 23 bytes (20 usable after ATT overhead).

All messages use the `ChunkedPayload` envelope:

```
┌──────────────────────────────────────────────┐
│ ChunkedPayload                               │
│   correlation_id : string  (UUID v4)         │
│   chunk_index    : uint32  (0-based)         │
│   total_chunks   : uint32                    │
│   data           : bytes   (proto payload)   │
└──────────────────────────────────────────────┘
```

Single-chunk messages set `chunk_index = 0` and `total_chunks = 1`.

**Thumbnail flow control:** Send the response one chunk at a time. After each chunk, wait for a `ChunkAck` write from the app before sending the next. Target: ≤ 160×90 JPEG at quality 60 (~4–8 KB ≈ 10–20 chunks at 500 bytes each).

---

## 8. Workflows

There are four distinct workflows. Each is described with what data moves, over which channel, and what the camera must do in response.

---

### 8.1 Workflow: Live preview

**Trigger:** App opens the camera detail screen or session screen after the WiFi Direct group is up.

**Channel:** WiFi Direct / RTSP (no BLE commands needed to start/stop the stream).

```
App                                    Camera
───                                    ──────

RTSP client connects ────────────────► gst-rtsp-server at :8554/preview

                          ◄──────────── H.264 NAL units (NVENC encoded)
                                        640×360 @ 15 fps (suggested)
                                        1000–2000 kbps (suggested)
                                        Scoreboard overlay composited in

[App renders frames in its preview widget]

RTSP client disconnects ─────────────► camera keeps encoding
                                        (stream stays alive; next client
                                         reconnects without BLE command)
```

**Notes:**
- The RTSP stream is always active once the WiFi Direct group is up. The camera does not need a BLE command to start or stop streaming to the preview client.
- The scoreboard overlay on the stream starts empty (no score, no clock) and updates as the app pushes match events.
- The overlay is composited onto the **live stream only**; the recording stays clean and the overlay is captured to the `<matchId>.timeline.json` sidecar. An on-demand L2 burn (§0.1) must reproduce the **same** overlay the stream showed at each timestamp.

---

### 8.2 Workflow: Session (match recording + streaming)

**Trigger:** User selects a match and taps "Start" in the app.

**Channel:** BLE for all commands; WiFi Direct / RTSP for the live preview during the session; WiFi Direct / HTTP is irrelevant during recording (used after).

```
App                                    Camera
───                                    ──────

──── Session setup ─────────────────────────────────────────────────────

→ PushSessionConfigCommand
    match_uuid:              "550e8400-e29b-41d4-a716-446655440000"
    user_uuid:               "d3b07384-d9a0-4b5a-8e31-4a3b9d8c6e1f"
    sport:                   "soccer"
    num_periods:             2
    period_length_seconds:   2700
    rtmp_url:                "rtmp://live.twitch.tv/live/sk_xxx"  (or null)
    video_output_path:       "/data/video/{user_uuid}/{match_uuid}/"
    thumbnail_output_path:   "/data/thumbnail/{user_uuid}/{match_uuid}/"
    team_a_id:               "team-real-madrid"
    team_b_id:               "team-barcelona"
    team_a_name:             "Real Madrid"
    team_b_name:             "Barcelona"
    team_a_color_hex:        "#FFFFFF"
    team_b_color_hex:        "#A50044"
← CommandResponse(OK)
[camera stores session metadata in memory; prepares output directories]

──── Overlay layout push (see Section 9 for full spec) ─────────────────

→ PushOverlayLayoutCommand
    layout: {
      canvas_width:  1920,
      canvas_height: 1080,
      elements: [
        // scoreboard background bar
        { id: "sb_bg",     shape: RECT, bounds: {x1:0, y1:0, z:1, x2:480, y2:80},
          style: { fill_color: "#111111", opacity: 0.85 } },
        // home team name label
        { id: "team_a",    shape: TEXT, bounds: {x1:10, y1:8, z:2, x2:220, y2:48},
          style: { font_size:22, text_color:"#FFFFFF", font_weight:BOLD },
          binding: BINDING_TEAM_A_NAME },
        // away team name label
        { id: "team_b",    shape: TEXT, bounds: {x1:260, y1:8, z:2, x2:470, y2:48},
          style: { font_size:22, text_color:"#FFFFFF", font_weight:BOLD },
          binding: BINDING_TEAM_B_NAME },
        // score display (auto-updates on ScoreUpdateCommand)
        { id: "score",     shape: TEXT, bounds: {x1:190, y1:5, z:2, x2:290, y2:75},
          style: { font_size:52, text_color:"#FFFFFF", font_weight:BOLD,
                   text_align:CENTER },
          binding: BINDING_SCORE_VS },
        // period label (P1 / P2 / HT / FT — auto-updates on MatchControlCommand)
        { id: "period",    shape: TEXT, bounds: {x1:10, y1:50, z:2, x2:100, y2:75},
          style: { font_size:16, text_color:"#AAAAAA" },
          binding: BINDING_PERIOD_LABEL },
        // clock (display-only; auto-updates on MatchControlCommand)
        { id: "clock",     shape: TEXT, bounds: {x1:370, y1:50, z:2, x2:470, y2:75},
          style: { font_size:16, text_color:"#AAAAAA", font_family:"monospace",
                   text_align:RIGHT },
          binding: BINDING_MATCH_CLOCK }
      ],
      templates: [
        // goal banner — activated by BannerEventCommand(template_id="goal")
        { event_type: "goal", duration_ms: 5000,
          elements: [
            { shape: RECT, bounds: {x1:560, y1:420, z:5, x2:1360, y2:660},
              style: { fill_color:"#E8B500", opacity:0.95, corner_radius:8 } },
            { shape: TEXT, bounds: {x1:580, y1:440, z:6, x2:1340, y2:560},
              style: { font_size:64, text_color:"#000", font_weight:BOLD,
                       text_align:CENTER, static_text:"GOAL" } },
            { shape: TEXT, bounds: {x1:580, y1:565, z:6, x2:1340, y2:635},
              style: { font_size:28, text_color:"#000", text_align:CENTER,
                       static_text:"{{player_name}}  #{{number}}" } }
          ]
        },
        // yellow card, red card, substitution templates follow same pattern ...
      ]
    }
← CommandResponse(OK)
[camera stores layout; overlay renderer is now configured]
[app stores same layout for its Flutter preview widget rendering]

──── Recording + streaming ─────────────────────────────────────────────

→ RecordingControlCommand(RECORDING_START)
← CommandResponse(OK)
[camera: open /data/video/{user_uuid}/{match_uuid}/{match_uuid}.mp4
         start encoding and muxing to MP4]

→ StreamingControlCommand(STREAMING_START, "rtmp://live.twitch.tv/live/sk_xxx")
← CommandResponse(OK)
[camera: start RTMP push to destination; overlay on stream]

──── Match events (BLE only; camera renders overlay in real time) ───────

→ MatchControlCommand(MATCH_KICKOFF, period=1)
← CommandResponse(OK)
[camera: scoreboard clock starts from 00:00
         show "KICKOFF" overlay for ~3s on the live stream (recording stays clean;
         the overlay change is appended to the timeline sidecar)]

→ ScoreUpdateCommand(team_id="team-real-madrid", delta=+1)
← CommandResponse(OK)
[camera: home score becomes 1; update scoreboard overlay]

→ BannerEventCommand(template_id="goal",
    params={"player_name": "Benzema", "number": "9", "team": "Real Madrid"},
    duration_s=5)
← CommandResponse(OK)
[camera: show "GOAL — Benzema #9" banner for 5 s on the live stream (recording stays clean; captured to the timeline sidecar)]

→ MatchControlCommand(MATCH_CLOCK_PAUSE, period=1)   ← VAR check
← CommandResponse(OK)
[camera: scoreboard clock pauses; no overlay change]

→ MatchControlCommand(MATCH_CLOCK_RESUME, period=1)
← CommandResponse(OK)
[camera: scoreboard clock resumes]

→ MatchControlCommand(MATCH_PERIOD_END, period=1)
← CommandResponse(OK)
[camera: clock stops; show "HALF TIME" overlay]

→ MatchControlCommand(MATCH_PERIOD_START, period=2)
← CommandResponse(OK)
[camera: clock restarts from 00:00; show "PERIOD 2" overlay]

... (second period events) ...

→ MatchControlCommand(MATCH_FINAL_WHISTLE, period=2)
← CommandResponse(OK)
[camera: clock stops; show final score overlay; keep scoreboard on screen]

──── End recording ─────────────────────────────────────────────────────

→ RecordingControlCommand(RECORDING_STOP)
← CommandResponse(OK)
[camera: finalize and close MP4 file
         file is now at /data/video/{user_uuid}/{match_uuid}/{match_uuid}.mp4]

→ StreamingControlCommand(STREAMING_STOP)
← CommandResponse(OK)
[camera: close RTMP connection]
```

**Notes on recording pause/resume:**
```
→ RecordingControlCommand(RECORDING_PAUSE)    ← e.g. during half-time break
← CommandResponse(OK)
[camera: pause muxer; file stays open; is_recording = false in telemetry]

→ RecordingControlCommand(RECORDING_RESUME)
← CommandResponse(OK)
[camera: resume muxer into same file; is_recording = true in telemetry]
```

---

### 8.3 Workflow: Post-session file download

**Trigger:** After recording stops, app needs to sync metadata and offer the user a download.

**Channel:** BLE to discover and authenticate; WiFi Direct / HTTP for the actual bytes.

```
App                                    Camera
───                                    ──────

──── Discovery over BLE ────────────────────────────────────────────────

→ ListRecordingsCommand
← RecordingListResponse
    recordings: [
      {
        id:          "550e8400-e29b-41d4-a716-446655440000"  ← match_uuid
        duration_s:  5412
        size_bytes:  3_221_225_472   ← 3 GB
        started_at:  1748908800000   ← unix millis
        sport:       "Soccer"
        teams:       "Real Madrid vs Barcelona"
      }
    ]

──── Token request over BLE ────────────────────────────────────────────

→ DownloadRequestCommand(recording_id="550e8400-...")
← DownloadTokenResponse
    recording_id: "550e8400-..."
    http_url:     "http://192.168.49.1:8080/recordings/550e8400-....mp4"
    auth_token:   "tok_9f3a2b..."    ← short-lived bearer token (~15 min)
    expires_at:   1748909700000

──── File download over WiFi Direct HTTP (separate TCP connection) ──────

GET /recordings/550e8400-....mp4 HTTP/1.1
Host: 192.168.49.1:8080
Authorization: Bearer tok_9f3a2b...

◄─── HTTP/1.1 200 OK
     Content-Type: video/mp4
     Content-Length: 3221225472
     Accept-Ranges: bytes
     [binary MP4 bytes — full file. The L1 at /recordings/<id> is CLEAN; an overlaid copy is a separate on-demand L2 under videos/exports/ (§0.1)]

──── Resumable download (if connection drops mid-transfer) ─────────────

GET /recordings/550e8400-....mp4 HTTP/1.1
Host: 192.168.49.1:8080
Authorization: Bearer tok_9f3a2b...
Range: bytes=1073741824-               ← resume from 1 GB

◄─── HTTP/1.1 206 Partial Content
     Content-Range: bytes 1073741824-3221225471/3221225472
     [remaining bytes]
```

**HTTP server requirements:**
- Authenticate every request; reject expired or missing tokens with `401 Unauthorized`
- Support `Range: bytes=N-` for resumable downloads
- URL pattern: `http://<group_owner_ip>:<download_port>/recordings/{match_uuid}.mp4`
- Token lifetime: ~15 minutes (issued fresh per `DownloadRequestCommand`)

---

### 8.4 Workflow: Disconnect

**Trigger:** User navigates away from the camera screen, or BLE connection drops.

```
App                                    Camera
───                                    ──────

[Optional — sent before explicit user disconnect]
→ StopWifiDirectCommand
← CommandResponse(OK)

[BLE disconnects]

[Camera must, regardless of which happens first:]
  - Finalize any in-progress recording (close and flush MP4 file)
  - Close RTMP stream if active
  - Tear down WiFi Direct group
  - Clear session config from memory (match_uuid, team info, paths, RTMP key)
```

**If BLE drops unexpectedly** (crash, out of range, battery) before `StopWifiDirectCommand`:
- The camera must still finalize the recording and tear down WiFi Direct
- Do not wait for a `StopWifiDirectCommand` that will never arrive
- The app will reconnect and issue `ListRecordingsCommand` to discover what was saved

---

## 9. Overlay layout system

This section specifies how the app sends a visual design spec to the camera and how the camera must render it. See `proto/bluetooth.proto` Section 11 for all message definitions.

### 9.1 Design principle

The app is the single source of overlay design. The camera never hard-codes layouts, fonts, colors, or animation. The firmware is a **generic compositor**: it receives a layout spec, stores it, and renders it — nothing more. When the app's designer changes the scoreboard, only the app changes; no firmware update is needed.

Both the app (Flutter/Skia) and the camera (Cairo/Pango) render the same layout spec from the same data. Rendering semantics — coordinate system, z-order, shape definitions, text layout, color/opacity, and conformance tolerances — are the shared contract and live in **`proto/overlay-rendering.md`** in the pinned `proto/` submodule. Both stacks must conform to that document.

### 9.3 Element types and bindings

**Persistent elements** (`OverlayLayout.elements`) — always visible once the layout is applied. Used for the scoreboard.

| Shape | Usage |
|-------|-------|
| `SHAPE_RECT` | Background panels, colored bars |
| `SHAPE_TEXT` | Labels, scores, clock; may have a `binding` |
| `SHAPE_CIRCLE` | Decorative dots, badges |

**Binding** — for `SHAPE_TEXT` elements, the camera updates the rendered text automatically when the corresponding data changes:

| Binding | Updates when | Renders as |
|---------|-------------|------------|
| `BINDING_STATIC` | Never (fixed text from `style.static_text`) | e.g. "vs" |
| `BINDING_SCORE_A` | `ScoreUpdateCommand(team_a_id, delta)` | e.g. "2" |
| `BINDING_SCORE_B` | `ScoreUpdateCommand(team_b_id, delta)` | e.g. "1" |
| `BINDING_SCORE_VS` | Either score changes | e.g. "2 – 1" |
| `BINDING_TEAM_A_NAME` | Never (set at session push) | e.g. "Real Madrid" |
| `BINDING_TEAM_B_NAME` | Never (set at session push) | e.g. "Barcelona" |
| `BINDING_MATCH_CLOCK` | `MatchControlCommand` | e.g. "23:41" (display-only) |
| `BINDING_PERIOD_LABEL` | `MatchControlCommand` | "P1", "P2", "HT", "FT" |

**Period label mapping:**

| MatchControlAction | BINDING_PERIOD_LABEL renders |
|--------------------|------------------------------|
| `MATCH_KICKOFF` (period=1) | "P1" |
| `MATCH_PERIOD_END` (period=N, N < num_periods) | "HT" |
| `MATCH_PERIOD_END` (period=N, N = num_periods) | "FT" |
| `MATCH_PERIOD_START` (period=N) | "P{N}" |
| `MATCH_FINAL_WHISTLE` | "FT" |
| `MATCH_CLOCK_PAUSE` / `MATCH_CLOCK_RESUME` | no change |

### 9.4 Templates (event-triggered banners)

`OverlayLayout.templates` defines reusable banner designs. A template is identified by `event_type`, which matches `BannerEventCommand.template_id`.

When `BannerEventCommand(template_id="goal", params={...})` arrives:
1. Camera finds the template with `event_type == "goal"`
2. Substitutes `{{param_name}}` placeholders in `style.static_text` with values from `params`
3. Shows the template's elements for `duration_ms`
4. Removes them when the duration expires

Substitution example:
```
style.static_text: "{{player_name}}  #{{number}}"
params:            { "player_name": "Benzema", "number": "9" }
rendered:          "Benzema  #9"
```

Unknown template IDs: show a generic text banner from the params dict for `duration_ms`.

### 9.5 Complete minimal layout example

```json
{
  "canvas_width": 1920,
  "canvas_height": 1080,
  "elements": [
    { "id": "sb_bg",    "shape": "RECT",
      "bounds": { "x1":0,   "y1":0,  "z":1, "x2":480,  "y2":80 },
      "style": { "fill_color":"#111111", "opacity":0.85 } },

    { "id": "team_a",   "shape": "TEXT",
      "bounds": { "x1":10,  "y1":8,  "z":2, "x2":185,  "y2":48 },
      "style": { "font_size":22, "text_color":"#FFF", "font_weight":"BOLD" },
      "binding": "BINDING_TEAM_A_NAME" },

    { "id": "score",    "shape": "TEXT",
      "bounds": { "x1":190, "y1":5,  "z":2, "x2":290,  "y2":75 },
      "style": { "font_size":52, "text_color":"#FFF", "font_weight":"BOLD",
                 "text_align":"CENTER" },
      "binding": "BINDING_SCORE_VS" },

    { "id": "team_b",   "shape": "TEXT",
      "bounds": { "x1":295, "y1":8,  "z":2, "x2":470,  "y2":48 },
      "style": { "font_size":22, "text_color":"#FFF", "font_weight":"BOLD" },
      "binding": "BINDING_TEAM_B_NAME" },

    { "id": "period",   "shape": "TEXT",
      "bounds": { "x1":10,  "y1":50, "z":2, "x2":100,  "y2":75 },
      "style": { "font_size":16, "text_color":"#AAA" },
      "binding": "BINDING_PERIOD_LABEL" },

    { "id": "clock",    "shape": "TEXT",
      "bounds": { "x1":370, "y1":50, "z":2, "x2":470,  "y2":75 },
      "style": { "font_size":16, "text_color":"#AAA",
                 "font_family":"monospace", "text_align":"RIGHT" },
      "binding": "BINDING_MATCH_CLOCK" }
  ],
  "templates": [
    { "event_type": "goal", "duration_ms": 5000,
      "elements": [
        { "shape": "RECT",
          "bounds": { "x1":560, "y1":420, "z":5, "x2":1360, "y2":660 },
          "style": { "fill_color":"#E8B500", "opacity":0.95, "corner_radius":8 } },
        { "shape": "TEXT",
          "bounds": { "x1":580, "y1":430, "z":6, "x2":1340, "y2":550 },
          "style": { "font_size":72, "text_color":"#000", "font_weight":"BOLD",
                     "text_align":"CENTER", "static_text":"GOAL" } },
        { "shape": "TEXT",
          "bounds": { "x1":580, "y1":555, "z":6, "x2":1340, "y2":640 },
          "style": { "font_size":28, "text_color":"#000", "text_align":"CENTER",
                     "static_text":"{{player_name}}  #{{number}}" } }
      ]
    }
  ]
}
```

---

## 10. Command reference

### 10.1 Required for v1

| Command | Response payload | Notes |
|---------|-----------------|-------|
| `GetDeviceInfoCommand` | `DeviceInfoResponse` | `device_id` must be a stable hardware UUID |
| `GetTelemetryCommand` | `DeviceTelemetry` | Polled at ~1 Hz; include `battery_level_pct` |
| `StartWifiDirectCommand` | `WifiDirectGroupResponse` | Part of connection handshake; generate per-session PSK |
| `StopWifiDirectCommand` | *(none, just OK)* | Tear down group; clear session memory |
| `PushSessionConfigCommand` | *(none, just OK)* | Hold in memory; discard on disconnect |
| `PushOverlayLayoutCommand` | *(none, just OK)* | Store layout; begin rendering; can be resent mid-session |
| `RecordingControlCommand` | *(none, just OK)* | RECORDING_START / STOP / PAUSE / RESUME |
| `StreamingControlCommand` | *(none, just OK)* | STREAMING_START (destination is full RTMP URL) / STOP |
| `MatchControlCommand` | *(none, just OK)* | All 6 actions; `period` field is 1-based; drives clock + period label bindings |
| `ScoreUpdateCommand` | *(none, just OK)* | Cumulative delta; drives SCORE_A / SCORE_B / SCORE_VS bindings |
| `BannerEventCommand` | *(none, just OK)* | Activates matching template; substitutes `{{params}}`; shows for `duration_ms` |
| `ThumbnailRequest` | `ThumbnailResponse` | 160×90 JPEG; flow-controlled chunks with `ChunkAck` |
| `ListRecordingsCommand` | `RecordingListResponse` | Scan output paths from session state; `id` = `match_uuid` |
| `DownloadRequestCommand` | `DownloadTokenResponse` | Issue short-lived bearer token; `http_url` uses WiFi Direct IP |

### 10.2 Deferred (stub with `UNSUPPORTED` for v1)

| Command | Reason deferred |
|---------|----------------|
| `GetMatchStateCommand` | App is authoritative; `DeviceTelemetry.is_recording/is_streaming` cover operational status needs |
| `SetWifiConfigCommand` | Outbound WiFi for cellular tethering — separate from WiFi Direct group |
| `SetStreamingConfigCommand` | RTMP keys arrive in `PushSessionConfigCommand` |
| `FactoryResetCommand` | Admin utility |
| `FirmwareUpdateCommand` | Admin utility |

---

## 11. DeviceTelemetry fields

Sent in response to `GetTelemetryCommand` (polled at ~1 Hz by the app):

| Field | Type | Notes |
|-------|------|-------|
| `storage_free_bytes` | uint64 | Free bytes on the storage volume |
| `storage_total_bytes` | uint64 | Total capacity |
| `wifi_state` | WifiState enum | WIFI_CONNECTED when on a known network |
| `wifi_ssid` | string | SSID of connected network; empty when disconnected |
| `wifi_signal_dbm` | sint32 | Signal strength; 0 when disconnected |
| `internet_reachable` | bool | True if outbound internet is reachable (needed for RTMP) |
| `temp_celsius` | float | SoC / module temperature |
| `ram_used_pct` | float | 0.0–1.0 |
| `cpu_used_pct` | float | 0.0–1.0 |
| `uptime_seconds` | uint64 | Seconds since last boot |
| `is_recording` | bool | True while recording is active (false when paused) |
| `is_streaming` | bool | True while RTMP stream is active |
| `battery_level_pct` | uint32 | 0–100; report 0 when on wired power or unknown |
| `camera0_health` / `camera1_health` | CameraHealth enum (optional, fields 15–16) | Frame-truth per-camera health, on EVERY sample. Absent ⇒ the app renders "unreported" — it never fabricates OK |

### Per-camera health expectations (state-health cycle, U3)

The app folds the snapshot health with every 1 Hz telemetry sample (newest
wins) into one device-level gate:

- any camera `CAMERA_HEALTH_DOWN` → the app shows the persistent "device
  inoperable" banner and disables live preview, recording start and streaming
  start; downloads, WiFi and diagnostics stay available. The firmware MUST
  also refuse start-class capture commands (recording start/resume, raw
  capture start, streaming start) with `ResponseStatus.DEVICE_INOPERABLE` —
  the wire backstop the app surfaces as an explicit error. Stops, downloads
  and `StartWifiDirectCommand` are never health-gated.
- `CAMERA_HEALTH_RECOVERING` → soft indicator only; the app keeps actions
  enabled and relies on the `DEVICE_INOPERABLE` refusal, so recovering must
  NOT be reported as down (flapping OK↔RECOVERING must never look inoperable).
- The app trusts a health reading for ~5 poll intervals: if telemetry stalls
  while connected, health degrades to unknown and capture starts are
  conservatively disabled until a fresh sample arrives — keep health on every
  telemetry sample.

---

## 12. Session config fields (PushSessionConfigCommand)

| Field | Type | Notes |
|-------|------|-------|
| `match_uuid` | string | UUID v4, app-generated; use for file naming |
| `user_uuid` | string | UUID v4, identifies recording owner; use in path |
| `sport` | string | Lowercase, e.g. `"soccer"` |
| `num_periods` | int32 | e.g. 2 for football |
| `period_length_seconds` | int32 | e.g. 2700 for 45 min halves |
| `rtmp_url` | string? | Full RTMP URL including stream key; `null` = no streaming |
| `stream_key` | string? | Stream key if separate from URL; `null` when embedded |
| `video_output_path` | string | Absolute: `/data/video/{user_uuid}/{match_uuid}/` |
| `thumbnail_output_path` | string | Absolute: `/data/thumbnail/{user_uuid}/{match_uuid}/` |
| `team_a_id` | string | Must match `ScoreUpdateCommand.team_id` for home team |
| `team_b_id` | string | Must match `ScoreUpdateCommand.team_id` for away team |
| `team_a_name` | string | Display name for scoreboard, e.g. `"Real Madrid"` |
| `team_b_name` | string | Display name for scoreboard |
| `team_a_color_hex` | string | Scoreboard accent colour, e.g. `"#FFFFFF"` |
| `team_b_color_hex` | string | Scoreboard accent colour |
| `auto_stop_minutes` | uint32? | Unsupervised-session timeout (app setting, default 30, bounds 5–240). The app always sends it and **re-pushes the whole config mid-session when the operator changes it** — map it on every PushSessionConfig, not just the first |

---

## 13. File system layout

```
/data/video/{user_uuid}/{match_uuid}/{match_uuid}.mp4
/data/thumbnail/{user_uuid}/{match_uuid}/{match_uuid}.jpg
```

- **One MP4 per session.** Filename is always `{match_uuid}.mp4`. Paths come from `PushSessionConfigCommand`; create directories as needed.
- On `RECORDING_PAUSE` / `RECORDING_RESUME`, pause and resume the muxer — the output is still a single continuous MP4, not segments.
- On `RECORDING_STOP`, finalize and close the file immediately.
- On unexpected BLE disconnect, finalize whatever was recorded even if `RECORDING_STOP` was not sent.
- On `ListRecordingsCommand`, scan the paths known from session state and return what exists on disk.

---

## 14. Overlay renderer behaviour

The layout spec (shapes, positions, bindings, templates) is fully described in **Section 9**. This section specifies what the renderer must *do* at runtime when match events arrive.

The camera renders overlays on the **live RTSP stream only** (§0.1). The recording is clean; each scene change is appended to the `<matchId>.timeline.json` sidecar so an on-demand L2 burn can reproduce the identical overlay later. The renderer actions below describe what is shown on the live stream and captured to the timeline — not anything baked into the L1.

### Match control → renderer actions

| Action | Clock | Scoreboard label | Transient overlay |
|--------|-------|-----------------|-------------------|
| `MATCH_KICKOFF` (period=1) | Start from 00:00 | "P1" | Show "KICKOFF" for ~3 s |
| `MATCH_PERIOD_END` (period=N, N < num_periods) | Stop | "HT" | Show "HALF TIME" |
| `MATCH_PERIOD_END` (period=N, N = num_periods) | Stop | "FT" | Show "FULL TIME" |
| `MATCH_PERIOD_START` (period=N) | Restart from 00:00 | "P{N}" | Show "PERIOD {N}" for ~3 s |
| `MATCH_FINAL_WHISTLE` | Stop | "FT" | Show final score; keep scoreboard visible |
| `MATCH_CLOCK_PAUSE` | Freeze display | no change | none |
| `MATCH_CLOCK_RESUME` | Resume display | no change | none |

The clock is **display-only** — it has no effect on recording, streaming, or any other state.

### Standard BannerEventCommand template IDs

The app sends `BannerEventCommand(template_id=..., params={...})`. The camera finds the matching template in the stored layout and substitutes `{{params}}` placeholders (see Section 9.4). Unknown template IDs render a generic text banner from the params dict.

| `template_id` | Expected params |
|---------------|----------------|
| `goal` | `player_name`, `number`, `team` |
| `foul` | `player_name`, `number`, `team` |
| `yellow_card` | `player_name`, `number`, `team` |
| `red_card` | `player_name`, `number`, `team` |
| `substitution` | `player_out`, `player_in`, `team` |

---

## 15. Constraints the firmware must respect

These are hard rules, not guidelines.

1. **Never push unsolicited data.** Every notify must be a response to an app command identified by `correlation_id`. Extra notifies cause correlation mismatches and silently break the app.

2. **Never persist business data.** Teams, rosters, streaming keys, user profiles — none of this belongs on the camera. Hold session config in memory only.

3. **Finalize recordings on any disconnect.** Whether the app sends `StopWifiDirectCommand` or the BLE connection drops unexpectedly, the camera must close and flush the MP4 file. A corrupt file is worse than a truncated one.

4. **The camera does not drive the match clock.** Its scoreboard clock is a display property only, driven entirely by `MatchControlCommand` events from the app.

5. **Do not reuse reserved proto field numbers.** See `proto/bluetooth.proto` reserved declarations. Field numbers are wire identifiers — reusing a tombstoned number silently corrupts old clients.

6. **Respond to every command.** Every write on Command Write must produce exactly one notify on Command Response. Deferred commands respond with `status = UNSUPPORTED`.

7. **Bump `protocol_version` on breaking changes.** The app reads this from `DeviceInfoResponse` and warns or disables features when the firmware is behind what the app expects.

---

## 16. Proto file locations

| File | Contents |
|------|---------|
| `proto/bluetooth.proto` | All BLE control: framing, commands, responses, match events, session push, WiFi Direct handshake |
| `proto/wifi.proto` | WiFi-only descriptors: `PreviewStreamDescriptor`, `PreviewFrame` |
| `proto/README.md` | Developer reference: GATT UUIDs, MTU, versioning policy |

Firmware uses the `.proto` files directly. Dart bindings in `lib/models/proto/` are app-side only.

---

## 17. App-side polling intervals (reference)

| Data | Command | Interval |
|------|---------|---------|
| Telemetry | `GetTelemetryCommand` | ~1 s, continuous while connected |
| Match state | `GetMatchStateCommand` | deferred in v1 |
| Thumbnail | `ThumbnailRequest` | on demand |

---

## 18. Keeping this document current

Update this document whenever:
- A command is added, removed, or deprecated in `proto/bluetooth.proto`
- The connection handshake or session flow changes
- An overlay template ID is standardised
- A constraint changes

When starting a firmware development session, use this document as context:
> "Here is the app's protocol spec. Review it and tell me what you have implemented vs. what is outstanding."
