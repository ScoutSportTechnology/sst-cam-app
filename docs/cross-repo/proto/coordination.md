---
repo: sst-cam-proto
---

# Proto coordination rules

## App → Proto changes that require proto action

| App need | Proto impact | Action |
|---|---|---|
| New BLE command | New `Command.oneof` arm + `CommandResponse.oneof` arm | Open outbound handoff; proto repo adds fields + bumps version; app regenerates |
| New field on existing message | Add field to proto | Outbound handoff; proto bumps; app regenerates and maps |
| Rename / remove field | Breaking change — proto and app must coordinate timing | Outbound handoff with migration plan; never rename unilaterally |

## Proto → App changes that require app action

| Proto change | App impact | Action |
|---|---|---|
| New `Command.oneof` arm | App `BleProtocol._toProtoCommand` switch needs a new case | Inbound handoff; app adds `BleCommand` subclass + protocol + mock (atomicity rule) |
| New field in `CommandResponse` | App response mapping may need updating | Inbound handoff; app updates `_mapOkResponse` and the corresponding model |
| Proto version bump (submodule) | `just gen-proto` regenerates `lib/models/proto/`; re-run and fix any mapping breakage | Standard update; no handoff needed unless the API surface changed |

## Submodule update workflow

```bash
cd proto                     # enter the submodule
git fetch && git checkout <sha-or-tag>
cd ..
just gen-proto               # regenerate Dart bindings
flutter analyze              # catch mapping breakage early
git add proto
git commit -m "chore(proto): bump sst-cam-proto to <version>"
```

Always regenerate and verify `flutter analyze` before committing the submodule bump.
