# App as Source of Truth — Requirements
_Brainstormed: 2026-05-05 | Scope: Deep architectural refactor_

## What this is

A full ownership flip: today the camera owns all business data (teams, users, rosters, matches, presets, streaming destinations) and the app is a thin BLE CRUD client. After this refactor the **app owns all business data** in a local SQLite DB, and the **camera is a stateless executor** that only knows what the app pushes per session.

---

## Architectural Decisions (locked in)

| Concern | Decision |
|---------|----------|
| Source of truth | App SQLite DB |
| Camera persistence | None — in-memory session state + file system only |
| Data push direction | App → Camera, one-way, per session |
| Camera write-back | Never — files are the only output |
| Multi-phone v1 | Backup/restore (local JSON, device UUID validated) |
| Cloud / server | Out of scope v1 |

---

## Data Ownership

### App owns (stored in SQLite)

| Entity | Notes |
|--------|-------|
| Users | UUID-based, no auth/roles, purely for scoping data per person |
| Teams | Name, short name, sport, hidden flag |
| Players | Per team roster |
| Team matches | Past results + upcoming, per team |
| Matches | Sport format config: type, number of periods, period duration |
| Streaming credentials | RTMP URL + stream key per platform, per user |
| Clip metadata | Duration, size, started_at, associated match UUID |
| Thumbnail file path references | Local paths to JPEG thumbnails |

### Camera owns (no persistence across sessions)

| Entity | Notes |
|--------|-------|
| In-memory session state | Current match UUID, output paths, active config |
| File system recordings | Under `/{user_uuid}/{match_uuid}/` structure below |

**Device file tree:**
```
/data/video/{user_uuid}/{match_uuid}/{match_uuid}.mp4
/data/video/{user_uuid}/{match_uuid}/{clip_uuid}.mp4
/data/thumbnail/{user_uuid}/{match_uuid}/{match_uuid}.jpg
/data/thumbnail/{user_uuid}/{match_uuid}/{clip_uuid}.jpg
```

`manifest.json` is eliminated — that session metadata belongs in the app DB (clips table), not on device.

---

## Session Flow

1. User selects match config in app (teams, sport format, streaming destination)
2. App connects to camera via BLE (control) + WiFi Direct (preview/download)
3. App pushes session config to camera: `{ matchUuid, userUuid, sportConfig, streamingKeys, outputPathPrefix }`
4. Camera records and streams using pushed config
5. Camera never writes back to app DB — only produces files
6. After session: app queries camera for new file metadata, stores in SQLite clips/thumbnail tables

---

## BleService Interface Changes

### Remove (all camera-side CRUD — ~20 methods)

- `listTeams`, `createTeam`, `updateTeam`, `deleteTeam`, `setTeamHidden`
- `addPlayer`, `updatePlayer`, `removePlayer`
- `addTeamMatch`, `removeTeamMatch`, `listTeamMatches`
- `listSportPresets`, `createSportPreset`, `updateSportPreset`, `deleteSportPreset`
- `listStreamingDestinations`, `createStreamingDestination`, `updateStreamingDestination`, `deleteStreamingDestination`
- `listUsers`, `createUser`, `updateUser`, `deleteUser`, `getActiveUser`, `setActiveUser`

### Keep

- `startScan`, `stopScan`, discovery stream
- `connect`, `disconnect`, `connectionStateStream`
- `telemetryStream`
- `requestThumbnail`
- `sendCommand` (generic)
- `matchStateStream`
- `listRecordings`, `requestDownload`

### Add

- `pushSessionConfig(deviceId, config)` — pushes match UUID, sport config, streaming keys, output path prefix to camera before session start
- Camera `GetDeviceInfo` response must include device UUID (needed for backup restore validation)

---

## App Data Layer Changes

### Drift (SQLite) integration

`drift` and `sqlite3_flutter_libs` are already in `pubspec.yaml` (unused). This refactor integrates them as the data layer for all entities listed in "App owns" above.

### Controller decoupling

`UsersController`, `TeamsController`, `SportPresetsController`, `StreamingDestinationsController` currently call `BleService.*` with a `deviceId`. After refactor they query Drift directly — no camera connection required for data operations.

`activeUserProvider` stays but is resolved from local DB, not from camera state.

### DevDataStore replacement

`lib/ble/dev_data_store.dart` (hand-rolled in-memory store backing `MockBleService`) is replaced by:
- A Drift in-memory DB for tests (same test patterns, real Drift queries)
- The `MockBleService` retains its session-push and recording methods (the BLE surface that remains)

---

## Proto Changes

`proto/bluetooth.proto` loses all team/user/preset/streaming CRUD command types (~60% of current commands).

Gains: `PushSessionConfig` command with payload: match UUID, user UUID, sport config (type, periods, period duration), streaming config (RTMP URL + stream key), output path prefix.

`GetDeviceInfoResponse` must include `device_uuid` field.

---

## Backup / Restore

### Location
Settings page — new "Backup & Restore" section.

### Backup
- Exports full app DB as a dated JSON file to local phone storage
- User can name or use auto-generated filename: `sst-backup-{YYYY-MM-DD}.json`

### File structure
```json
{
  "backup_version": 1,
  "created_at": "ISO8601",
  "device": {
    "uuid": "...",
    "model": "SST-CAM-01"
  },
  "users": [],
  "teams": [],
  "sport_configs": [],
  "streaming_configs": [],
  "matches": [],
  "clips": []
}
```

### Restore
1. User picks a backup JSON file from local storage
2. App reads `device.uuid` from file
3. App checks currently connected camera UUID via BLE `GetDeviceInfo`
4. If UUIDs match → import into local SQLite (replace current data)
5. If UUIDs mismatch → show error: "This backup is for a different camera"
6. If no camera connected → show warning: "Connect your camera first to verify backup compatibility"

### Constraints
- Restore replaces all local data (no merge)
- Only one backup file validated per restore action
- No scheduled auto-backup v1

---

## Scope Boundaries

### Deferred to later
- Cloud sync or server-side backup
- Incremental backup (delta only)
- Multi-device rosters (one camera per install v1)
- Scheduled automatic backups

### Outside this product's identity
- Server-side auth or user accounts
- Device DB mirror / two-way sync
- `manifest.json` on device (eliminated)

---

## Open Questions / Assumptions

| Item | Status |
|------|--------|
| Camera `GetDeviceInfo` currently returns UUID? | **Unverified** — `GetDeviceInfoCommand` exists; need to confirm UUID is in response payload |
| File metadata returned after session? | **Assumed** — app polls recordings list via existing `listRecordings` / `requestDownload`; clip UUIDs must be deterministic or returned by camera |
| Clip UUID ownership | **Assumed app-generated** — app creates UUID, pushes in session config, camera uses it for file naming |
| SQLite migration strategy for existing installs | **Assumed fresh-start** — greenfield project, no existing user data to migrate |

---

## Affected Files (major change surface)

| File | Change |
|------|--------|
| `lib/ble/ble_service.dart` | Remove ~20 methods; add `pushSessionConfig` |
| `lib/ble/ble_service_impl.dart` | Same delta |
| `lib/ble/mock_ble_service.dart` | Remove CRUD delegates; keep session/recording surface |
| `lib/ble/dev_data_store.dart` | Delete or repurpose as Drift in-memory test helper |
| `lib/state/app_data.dart` | Rewrite controllers to query Drift; remove BLE coupling |
| `proto/bluetooth.proto` | Remove CRUD command types; add `PushSessionConfig` |
| `lib/models/command.dart` | Remove ~20 BleCommand subclasses; add `PushSessionConfigCommand` |
| `pubspec.yaml` | No new deps — Drift already present |
| `lib/pages/settings_page.dart` | Add Backup & Restore section |
| New: `lib/db/` | Drift DB definition, tables, DAOs |
| New: `lib/services/backup_service.dart` | Export / import logic |
