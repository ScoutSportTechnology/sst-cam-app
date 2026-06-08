---
repo: sst-cam-firmware
---

# Firmware coordination rules

## App → Firmware changes that require firmware action

| App change | Firmware impact | Action required |
|---|---|---|
| New `BleCommand` subclass added | Firmware must handle the new command in its BLE dispatch loop | Open an outbound handoff; firmware adds handler before the app can ship the real impl |
| New `CommandResponse` field consumed by app | Field must exist in the proto and firmware must populate it | Coordinate via sst-cam-proto first; firmware populates; app reads |
| Changed `OverlayLayout` rendering semantics | Both renderers must stay in sync | Update the shared semantics table in `firmware/inbound/2026-06-08-overlay-pixel-parity-contract.md` and agree before changing either |
| New bundled font | Firmware must bundle the identical TTF binary | Supply the file and open an outbound request |
| Changed WiFi Direct flow trigger timing | Firmware must match expected `StartWifiDirect` timing | Coordination required; a mismatch here leaves the device stuck in `starting` |

## Firmware → App changes that require app action

| Firmware change | App impact | Action required |
|---|---|---|
| New proto field in `CommandResponse` | App may need to read and surface it | Firmware opens an inbound handoff here; app responds with a plan unit |
| Changed `WifiDirectGroupResponse` shape | `WifiServiceImpl` mapping breaks | Firmware documents in inbound; app updates the mapping in the same commit as the proto bump |
| New BLE command the firmware expects | App must send it at the right point in the flow | Firmware opens an inbound handoff; app adds `BleCommand` subclass + updates protocol + mock |
| Changed group-owner IP or port convention | `WifiP2pChannel` / preview URL construction breaks | Inbound handoff required before firmware ships the change |

## Atomicity rules

- Adding a new `BleCommand` in the app requires updating `BleProtocol` **and** `MockBleService`
  exhaustive switches in the **same commit** (U4/U5 atomicity rule from prior plan).
- A proto message change requires a sst-cam-proto version bump and a coordinated app
  submodule update — see `docs/cross-repo/proto/coordination.md`.
