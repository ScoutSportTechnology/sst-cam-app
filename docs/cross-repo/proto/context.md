---
repo: sst-cam-proto
relation: dependency (submodule)
---

# Proto repo — context

## What it is

`sst-cam-proto` is the shared wire-format repository. It owns `proto/bluetooth.proto`
(and future WiFi control protos). The app consumes it as a git submodule at
`proto/` (see `lib/core/ble/ble_protocol.dart` for Dart-side mappings).

Firmware also submodules `sst-cam-proto` and uses the same `.proto` files for its
C++ / Python BLE stack.

## How it relates to us

The proto repo is the **source of truth for every BLE message type**. The app's
`BleProtocol` (encode) and response-mapping logic (decode) must stay in sync with
whatever version of the proto is pinned in the submodule.

`just gen-proto` regenerates `lib/models/proto/` from the submodule; those generated
files are gitignored — only `BleServiceImpl` touches them.

## Standing assumptions

- The app's `BleCommand` sealed hierarchy mirrors the proto's `Command.oneof`. Every
  new command type must exist in the proto **before** the app's `BleProtocol` can
  encode it.
- `StartWifiDirectCommand` and `WifiDirectGroupResponse` already exist in
  `proto/bluetooth.proto` (confirmed 2026-06-03 proto update).
- The proto repo assigns field numbers; the app does not invent its own. A mismatch
  silently encodes/decodes the wrong oneof arm.
