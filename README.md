# SST Cam App

**Mobile companion app for the SST Cam — an open-source AI-assisted sports camera on NVIDIA Jetson.**

Flutter app (Android / iOS) that discovers, pairs, and controls the camera over
**BLE** (command & control) and pulls live preview + recordings over **WiFi Direct**.
Built **contract-first** against the shared [`sst-cam-proto`](https://github.com/ScoutSportTechnology/sst-cam-proto)
wire spec, so the full UI runs and is tested against an in-app mock long before
hardware exists.

> Status: **active development.** Connect/control, local data, and the full
> feature UI work today against the mock backend. End-to-end against real
> firmware is gated on the [firmware pipeline](https://github.com/ScoutSportTechnology/sst-cam-firmware#roadmap).

---

## Where it sits

```text
  ┌─────────────┐   BLE control     ┌──────────────┐
  │  SST Cam    │◄─────────────────►│   Firmware   │
  │  App (this) │   WiFi Direct     │  (Jetson)    │
  └─────────────┘   preview + data  └──────────────┘
         │                                 ▲
         └──── both speak ────────────┐    │
                                      ▼    │
                              ┌──────────────┐
                              │  sst-cam-proto│  shared wire contract
                              └──────────────┘
```

The app **always initiates**; firmware never pushes. Every exchange is
`Command → CommandResponse`; telemetry and match state are polled on timers.

---

## Roadmap

System-wide arc — this repo's slice marked per phase:

| Phase | Theme | App status |
| ----- | ----- | ---------- |
| 1 | **Contract & scaffolding** — wire spec, dev container, mock backend | ✅ done |
| 2 | **Connect & control** — discovery, pairing, commands, telemetry | ✅ done |
| 3 | **Capture & transfer** — recording control, WiFi Direct preview, downloads | 🚧 built on mock; real-device wiring pending firmware |
| 4 | **Intelligence** — display AI tracking / auto-framing state | ⬜ pending firmware |
| 5 | **Broadcast** — overlay authoring, scoreboard/banner, streaming config | 🚧 authoring + render built; live output pending |

### Module checklist

Built and working (against mock backend, tested):

- [x] **BLE layer** — `BleService` port, `flutter_blue_plus` impl + in-app mock, chunked-payload protocol
- [x] **WiFi layer** — `WifiService` port + P2P channel + handoff, live-preview view
- [x] **Local database** — Drift: clips, teams, users, sport presets, streaming destinations, thumbnails
- [x] **Discovery** — device scan / filter (UUID + `sst-cam-` name prefix), diagnostics, debug page
- [x] **Camera / main** — connection + control surface
- [x] **Match** — landing, setup, live session, event sheet, overlay renderer
- [x] **Teams** — roster, team matches, stats
- [x] **Settings** — sport presets, streaming destinations, users, data backup/restore, developer tools
- [x] **Video** — recordings list, match detail, download sheet, playback
- [x] **Dev backend** — emulator + internal mocks, seedable dev data, env-switched at launch

Pending:

- [ ] **Real-device integration** — full BLE + WiFi Direct flow against firmware hardware
- [ ] **Live AI/auto-framing display** — once firmware ships detections + decision
- [ ] **Live streaming output** — overlay-composited stream from camera
- [ ] **iOS device validation** — beyond simulator

---

## Quick start

Open in VS Code → **Reopen in Container** (devcontainer ships Flutter, Android
SDK, `protoc`, mock-camera WiFi service). Then:

```bash
just get      # flutter pub get
just run      # dev build (mock backend)
just test     # unit + widget tests
just ci       # format-check + analyze + test
```

iOS builds need macOS + Xcode (devcontainer is Linux-only). See
[`CLAUDE.md`](CLAUDE.md) for architecture, the full command list, and the
contract-first design.

---

## Related repos

- [`sst-cam-firmware`](https://github.com/ScoutSportTechnology/sst-cam-firmware) — on-device C++ runtime (Jetson)
- [`sst-cam-proto`](https://github.com/ScoutSportTechnology/sst-cam-proto) — shared BLE/WiFi wire contract (consumed as a submodule)
- [`sst-cam-emulator`](https://github.com/ScoutSportTechnology/sst-cam-emulator) — cross-stack bridge to test app ↔ firmware without a Jetson

---

⚽ Goal: a simple, open, extensible mobile app that gives anyone professional-style
control of their own sports camera.
