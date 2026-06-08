---
repo: sst-cam-firmware
relation: peer
---

# Firmware repo — context

## What it is

The SST-Cam firmware runs on an NVIDIA Jetson board embedded in the sports camera.
It implements the camera-side of the BLE protocol, the WiFi Direct P2P group-owner,
the video pipeline (recording + RTSP preview), and the overlay compositor
(Cairo for shapes, Pango for text).

## How it relates to us

The firmware is the **other end of every BLE command**. The app sends `Command`
proto messages; the firmware returns `CommandResponse`. The app is always the
initiator — the firmware never pushes unsolicited data.

Key shared contracts:
- `proto/bluetooth.proto` (via sst-cam-proto submodule) — BLE wire format
- Overlay rendering semantics: same `OverlayLayout` spec rendered on Flutter (app)
  and Cairo/Pango (camera) to achieve pixel-parity
- WiFi Direct credentials: firmware generates a per-session SSID/PSK and delivers
  them to the app via `WifiDirectGroupResponse`

## Standing assumptions

- Firmware always replies within the BLE MTU timeout (~5 s); the app does not
  implement a hard timeout shorter than this.
- `font_family` absent or empty in the proto → firmware defaults to Inter Regular,
  matching the app's fallback. **Pending confirmation** from firmware (open question
  in `inbound/2026-06-08-overlay-pixel-parity-contract.md`).
- `group_owner_ip` for WiFi Direct is always `192.168.49.1`; preview on
  `:preview_port/preview`, downloads on `:download_port`.
- Canvas-to-surface scaling is uniform on both sides (`min(sx, sy)`).
