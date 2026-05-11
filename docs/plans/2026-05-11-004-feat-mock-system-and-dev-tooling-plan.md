---
title: "feat: Mock system, dev tooling, and highlight trimming"
type: feat
status: completed
date: 2026-05-11
origin: docs/brainstorms/2026-05-11-mock-system-requirements.md
---

# feat: Mock system, dev tooling, and highlight trimming

## Summary

Splits the `AppEnv` enum from mock-data concerns via a new `kUseMockData` bool dart-define, wires JSON fixture assets into the Drift DB on first launch, adds DB inspection tooling (in-app debug screen + Drift DevTools), standardizes video file paths away from `/tmp`, extends `ClipsTable` with a `startSeconds` column to support on-device highlight trimming via `ffmpeg_kit_flutter`, purges all "Phase 7" labels from the codebase, and documents data contracts for every major screen.

---

## Problem Frame

Development requires a full mock layer that covers every screen without a physical camera, and the current approach conflates environment-level config with data concerns, stores downloads in `/tmp`, and leaves "Phase 7" placeholder labels scattered across the BLE and WiFi service implementations. See origin for the full narrative.

---

## Requirements

- R1–R3. Flag system: `AppEnv` for env-level behavior; `kUseMockData` bool for data loading; reset honors the flag.
- R4. Base seed (default user, sport presets) always runs unconditionally on fresh DB.
- R5–R7. Mock fixtures as JSON assets; live SQLite gitignored; fixture schema documented inline.
- R8–R10. File paths: app-private `videos/` subfolder for recordings and clips; Documents for exports.
- R11–R12. DB inspection: in-app debug screen (long-press About row, non-prod) + Drift DevTools extension.
- R13. `mock-video.mp4` bundled as a Flutter asset; single source for all mock scenarios.
- R14–R16. Live preview: raw WiFi stream (or looping mock asset); compact score section always visible; event log shown.
- R17–R18. Playback: toggleable event timeline and scoreboard overlays; mock video used for all library matches.
- R19–R21. Highlight trimming: `ClipsTable` stores start offset + duration; cut-only trim produces a shareable MP4.
- R22. Data contracts as named Dart types for camera card, live preview, library tile, playback, recordings, and clip row.
- R23–R25. Phase 7 cleanup: remove labels; relabel stubs; ensure mock coverage; refactor `libraryProvider` to DB-backed.

**Origin actors:** A1 (Developer), A2 (End user)
**Origin flows:** F1 (App launch in mock mode), F2 (Reset app state), F3 (View or share a highlight), F4 (Live preview with score)
**Origin acceptance examples:** AE1 (R2, R3, R4, R5), AE2 (R3, R6), AE3 (R8), AE4 (R15, R16), AE5 (R20, R21), AE6 (R23, R24)

---

## Scope Boundaries

- Real BLE proto encoding and WiFi download firmware wiring — stubs relabeled, not implemented.
- Multiple mock video files per match.
- Video re-encoding (trimming is cut-only via `-c copy`).
- Cloud sync or remote backup of mock state.
- Production APK size optimization for the mock video asset (103 MB adds to all debug builds; production flavor exclusion is deferred).

### Deferred to Follow-Up Work

- Production build flavor that excludes `assets/mock/` from the release APK/IPA — separate Gradle/Xcode configuration.
- `ThumbnailsTable` DAO (table exists; deferred until clip playback thumbnails are designed).
- Real `WifiServiceImpl.startDownload` path computation — deferred with other firmware wiring.

---

## Context & Research

### Relevant Code and Patterns

- `lib/env.dart` — `AppEnv` enum (3 values) + `kAppEnv` const; add `kUseMockData` here alongside existing pattern.
- `lib/db/app_database.dart` — `LazyDatabase`, `schemaVersion = 1`, `MigrationStrategy.onCreate`; bump to v2 and add `onUpgrade` for `ClipsTable`.
- `lib/db/tables/clips_table.dart` — currently has `id, matchId, durationSeconds, sizeBytes, startedAt`; add `startSeconds`.
- `lib/db/daos/sport_presets_dao.dart` — `seedBuiltInsForUser(userId)` is the pattern for base seeding; mirror it for first-launch user creation.
- `lib/wifi/mock_wifi_service.dart:212` — the only hardcoded `/tmp/` path; replace with the videos subfolder helper.
- `lib/models/device.dart` — `ScoutDevice` class; add `batteryPercent` and `rssi` fields.
- `lib/state/app_data.dart` — inline `_seedLibrary` const (lines 71–159) and `libraryProvider` (line 958); both replaced by DB-backed provider.
- `lib/pages/settings_page.dart` — About row `_RowItem` (lines 96–103); wrap in `GestureDetector` for the debug screen entry point.
- `lib/pages/match_page.dart` — `_LiveThumb` + `_ScoreBlock` (lines 1851–1914); the score section that R15 builds on.
- `lib/ble/ble_service_impl.dart` lines 14, 213, 222, 235, 304 — "Phase 7" occurrences.
- `lib/wifi/wifi_service_impl.dart` lines 9, 23, 29, 55 — "Phase 7" occurrences.
- `test/test_helpers.dart` — `_seedInMemoryDb()` is the reference seed; `MockDataSeeder` mirrors its entity coverage.
- `pubspec.yaml` — `assets: [assets/brand/]`; add `assets/mock/` here.
- `devtools_options.yaml` — empty `extensions:`; add `drift: enabled`.
- `lib/pages/diagnostics_page.dart` — existing diagnostics pattern (BLE, not DB); style reference for the new debug screen.

### Institutional Learnings

- Drift FK pragmas (`PRAGMA foreign_keys = ON`) must fire in `beforeOpen`; absence silently breaks cascade deletes. Already wired in `app_database.dart` — preserve in all migrations.
- Use composite PKs for built-in records seeded per user (e.g., `'$userId-preset-soccer-std'`). Shared global IDs with `insertOnConflictUpdate` cause silent cross-user data corruption.
- `AppDatabase.forTesting(NativeDatabase.memory(closeStreamsSynchronously: true))` pattern must be used in all new test harnesses.
- All Drift stream subscriptions in Riverpod `AsyncNotifier.build()` must include `onError:`.
- Any user-supplied file path must be canonicalized against the expected base directory before use.

### External References

- `ffmpeg_kit_flutter` (`pub.dev/packages/ffmpeg_kit_flutter`) — cut-only MP4 trimming via `-c copy`; no re-encode; ~30-40 MB APK footprint for the full-GPL variant. Use the `ffmpeg_kit_flutter_min` (LGPL, ~15 MB) if all codecs are not needed — sufficient for `-c copy`.
- Drift DevTools: bundled with `drift_dev ^2.20.2` (already a dev dependency); activated via `devtools_options.yaml` `extensions: drift: enabled`.
- `path_provider` `getApplicationSupportDirectory()` — already used for the Drift DB; extend to `videos/` subfolder for all video files.

---

## Key Technical Decisions

- **`kUseMockData` is a top-level `const bool`, not part of `AppEnv`.** `AppEnv` controls log verbosity and diagnostic behavior; `kUseMockData` controls fixture injection. These are orthogonal: a developer can run `dev` + no mock data (real device, seed only) or `stage` + mock data (emulator, full fixtures). Coupling them in an enum forces them to move together.
- **`MockDataSeeder` writes directly to the Drift DB, not to `DevDataStore`.** `DevDataStore` is referenced in past planning docs but the file does not exist. Introducing it now would add a redundant in-memory layer between the fixture JSON and the Drift DB. `MockDataSeeder` is the simpler and more consistent path.
- **Base seed lives in `AppDatabase.migration.onCreate`, not in `main.dart`.** All initialization logic in one place; `main.dart` is responsible only for wiring `kUseMockData → MockDataSeeder` after the DB is open.
- **`ffmpeg_kit_flutter_min` (LGPL variant) for trimming.** The `-c copy` flag copies raw bitstream frames without decoding; no GPL codecs are needed. The LGPL variant is ~15 MB lighter and avoids GPL license implications.
- **Score section is already implemented in `_LiveThumb._ScoreBlock`** (derived from `liveMatchProvider`). U10 is a verification and wiring unit, not a greenfield build.
- **`ScoutDevice` gains `batteryPercent` and `rssi` as nullable `int?`.** Both are unavailable in some BLE scan states; nullable avoids a forced-zero default that would mislead the UI.

---

## Open Questions

### Resolved During Planning

- *Which Flutter package handles cut-only MP4 trimming?* — `ffmpeg_kit_flutter_min` with `-c copy`. No re-encode; no GPL implications. Alternative (platform channel with `MediaMuxer`/`AVAssetExportSession`) would require ~200 lines of native code for equivalent functionality.
- *Does Drift DevTools require runtime changes?* — No. The extension is bundled in `drift_dev` (already a dev dependency). Only `devtools_options.yaml` needs updating.
- *Where does `DevDataStore` fit?* — It does not exist. `MockDataSeeder` replaces any planned role for it.
- *Is the compact score section new work or existing?* — Existing. `_ScoreBlock` in `match_page.dart` satisfies R15 for `_SessionScreen`. U10 validates the wiring covers F4 / AE4.

### Deferred to Implementation

- *Exact schema name for the new `ClipsTable` column.* Dart field `startSeconds`, SQLite column `start_seconds`. Confirm via generated `app_database.g.dart` after `just gen-db`.
- *`LibraryMatch` model survival.* After `libraryProvider` moves to DB-backed queries, `LibraryMatch` may be retired or kept as a view-model assembled from Drift row types. The implementer should pick the shape that minimizes churn.
- *`MockDataSeeder` idempotency strategy.* Options: check-before-insert (`insertOrIgnore`), wipe-then-reseed, or flag in `SharedPreferences`. The reset flow (F2) always wipes the DB first, so idempotency on first launch is the primary concern.

---

## Output Structure

```
assets/
  mock/
    mock-video.mp4              ← moved from repo root
    fixtures/
      teams.json
      matches.json
      events.json
      recordings.json
      streaming_destinations.json
lib/
  db/
    daos/
      clips_dao.dart            ← new
    mock_data_seeder.dart       ← new
  services/
    clip_service.dart           ← new
    video_path_service.dart     ← new
  pages/
    debug_page.dart             ← new
```

---

## High-Level Technical Design

> *This illustrates the intended approach and is directional guidance for review, not implementation specification. The implementing agent should treat it as context, not code to reproduce.*

**App initialization data flow:**

```
main() / ProviderScope
  │
  ├─ AppDatabase opens (getApplicationSupportDirectory()/scout_camera.sqlite)
  │    └─ migration.onCreate
  │         ├─ CREATE TABLE ... (all tables, v2 schema)
  │         ├─ CREATE INDEX ...
  │         └─ _seedBaseData(db)        ← unconditional
  │              ├─ create default User
  │              └─ seedBuiltInsForUser(defaultUserId)
  │
  └─ if kUseMockData
       └─ MockDataSeeder.seed(db)       ← reads assets/mock/fixtures/*.json
            ├─ insert teams
            ├─ insert team_matches + events
            ├─ insert recordings (in app_data library model)
            └─ insert streaming_destinations
```

**Flag decision matrix:**

| `kAppEnv`   | `kUseMockData` | BLE/WiFi backend | DB fixtures |
|-------------|----------------|-----------------|-------------|
| devMock     | true           | Mock services   | Loaded      |
| devMock     | false          | Mock services   | Not loaded  |
| devDevice   | false          | Real impl       | Not loaded  |
| prod        | false          | Real impl       | Not loaded  |

**Highlight trimming flow (F3):**

```
User taps event on match detail
  → ClipService.trim(source: videoPath, start: clip.startSeconds, duration: clip.durationSeconds)
       → ffmpeg: -ss {start} -t {duration} -c copy -y {outputPath}
       → success → ClipsDao.insert(clipRecord)
       → present: play in-app  OR  share sheet (system)
```

---

## Implementation Units

### U1. Flag system and Drift DevTools activation

**Goal:** Add `kUseMockData` bool dart-define to `lib/env.dart`; rename `AppEnv` values from `devMock/devDevice/prod` to `dev/stage/prod`; update `devtools_options.yaml` to activate the Drift DevTools extension.

**Requirements:** R1, R2, R12

**Dependencies:** None

**Files:**
- Modify: `lib/env.dart`
- Modify: `devtools_options.yaml`
- Modify: `lib/state/ble_providers.dart` (update `isMock` references)
- Modify: `lib/state/wifi_providers.dart` (update `isMock` references)
- Modify: `lib/state/app_data.dart` (remove `kAppEnv.isMock` guard on library)
- Test: `test/env_test.dart` (new)

**Approach:**
- Add `const bool kUseMockData = bool.fromEnvironment('kUseMockData', defaultValue: false)` to `lib/env.dart`.
- Rename `AppEnv.devMock → AppEnv.dev`, `AppEnv.devDevice → AppEnv.stage`. Update the `label` extension getter and the `kAppEnv` const resolver accordingly. Update the dart-define string from `dev-mock/dev-device` to `dev/stage`.
- The `isMock` getter on `AppEnv` continues to exist but its sole use is now service backend selection (not data). Rename it `isDevBackend` to clarify it controls which BLE/WiFi impl is instantiated, not whether mock data loads.
- In `devtools_options.yaml`, add `drift: enabled` under `extensions:`.

**Patterns to follow:**
- `lib/env.dart` existing const-from-environment pattern.

**Test scenarios:**
- Happy path: `kUseMockData` defaults to `false` when dart-define is absent.
- Happy path: `kUseMockData = true` when `--dart-define=kUseMockData=true` is set.
- Happy path: `kAppEnv == AppEnv.dev` when `APP_ENV=dev`.
- Edge case: `kAppEnv == AppEnv.prod` with `kUseMockData=true` is a valid combination — assert both flags are independent.

**Verification:**
- `grep -r "devMock\|dev-mock\|isMock"` returns zero hits in `lib/` after rename.
- `grep "Phase 7"` is not part of this unit but sets the stage for U7.
- Drift DevTools tab appears in `flutter pub run devtools` session without any runtime code change.

---

### U2. Asset scaffold and fixture JSON files

**Goal:** Create `assets/mock/` directory, move `mock-video.mp4` into it, declare the asset in `pubspec.yaml`, and author the five fixture JSON files that `MockDataSeeder` will consume.

**Requirements:** R5, R6, R7, R13

**Dependencies:** None

**Files:**
- Create: `assets/mock/mock-video.mp4` (moved from `mock-video.mp4` at repo root)
- Create: `assets/mock/fixtures/teams.json`
- Create: `assets/mock/fixtures/matches.json`
- Create: `assets/mock/fixtures/events.json`
- Create: `assets/mock/fixtures/recordings.json`
- Create: `assets/mock/fixtures/streaming_destinations.json`
- Modify: `pubspec.yaml` (add `- assets/mock/` to flutter.assets)
- Modify: `.gitignore` (ensure `*.sqlite` is ignored — verify existing entry covers it)
- Test: `test/assets_test.dart` (new — verifies each fixture file is valid JSON and loadable)

**Approach:**
- Add a schema comment block at the top of each JSON fixture file describing fields and types (satisfying R7).
- Fixture coverage minimum (from R5): 1 team, 3 past matches, 1 upcoming match, 2 recording entries, 1 streaming destination. Mirror the entity shapes used in `test/test_helpers.dart:_seedInMemoryDb()` for consistency.
- JSON field names mirror Dart model field names (camelCase) for straightforward parsing in `MockDataSeeder`.
- `events.json` references match IDs from `matches.json` — use stable mock IDs (e.g., `"mock-match-001"`) to avoid coupling.
- Moving the 103 MB video: add `mock-video.mp4` to `.gitattributes` with `filter=lfs` if Git LFS is configured; otherwise, confirm the file is already tracked and simply move it.

**Patterns to follow:**
- `assets/brand/` existing asset directory pattern in `pubspec.yaml`.

**Test scenarios:**
- Happy path: `rootBundle.loadString('assets/mock/fixtures/teams.json')` succeeds and parses to a non-empty list.
- Happy path: same for each of the five fixture files.
- Edge case: fixture JSON is well-formed (parseable as `List<dynamic>` or `Map<String, dynamic>`).

**Verification:**
- `flutter pub run flutter_test test/assets_test.dart` passes.
- `mock-video.mp4` is absent from repo root; `assets/mock/mock-video.mp4` exists.
- `pubspec.yaml` assets section includes `assets/mock/`.

---

### U3. ClipsTable schema migration and DAO

**Goal:** Add `startSeconds` integer column to `ClipsTable`, bump the schema to version 2 with a migration, create `ClipsDao`, and wire it into `AppDatabase`.

**Requirements:** R19, R20

**Dependencies:** None (parallel-safe with U1 and U2)

**Files:**
- Modify: `lib/db/tables/clips_table.dart`
- Modify: `lib/db/app_database.dart`
- Create: `lib/db/daos/clips_dao.dart`
- Modify: `lib/db/app_database.g.dart` (regenerated — run `just gen-db` after edits)
- Test: `test/db/clips_dao_test.dart` (new)

**Approach:**
- Add `IntColumn get startSeconds => integer().withDefault(const Constant(0))()` to `ClipsTable`.
- Bump `schemaVersion` to `2` in `AppDatabase`.
- Add `MigrationStrategy(onCreate: ..., onUpgrade: (m, from, to) { if (from == 1) { await m.addColumn(clipsTable, clipsTable.startSeconds); } })`.
- `ClipsDao`: `@DriftAccessor(tables: [ClipsTable])`. Methods: `insertClip(ClipsTableCompanion)`, `clipsForMatch(matchId)` (returns `Stream<List<Clip>>`), `deleteClip(clipId)`.
- Add `ClipsDao` to `@DriftDatabase(daos: [...])` in `AppDatabase` and to the `AppDatabase.forTesting` path.

**Patterns to follow:**
- `lib/db/daos/teams_dao.dart` — `@DriftAccessor` pattern, stream-based queries.
- Existing `MigrationStrategy.onCreate` block in `app_database.dart` for index creation style.

**Test scenarios:**
- Happy path: fresh DB (schema v2) → `clips` table has `start_seconds` column, default 0.
- Happy path: insert clip with `startSeconds = 300` → `clipsForMatch` returns it with correct value.
- Happy path (migration): simulate v1 DB open with v2 schema → `onUpgrade` adds column; existing rows get default 0.
- Edge case: insert clip with `matchId` referencing a non-existent match → FK violation, insert rejected.
- Happy path: `deleteClip` removes the record; `clipsForMatch` stream emits empty list.

**Verification:**
- `just gen-db` completes without errors.
- `just test` passes including new `clips_dao_test.dart`.
- The `clips` table in a fresh DB has columns: `id, match_id, duration_seconds, size_bytes, started_at, start_seconds`.

---

### U4. Base seed guarantee

**Goal:** Ensure that on every fresh DB initialization a default user and sport presets are created unconditionally, regardless of `kUseMockData`.

**Requirements:** R4

**Dependencies:** U3 (schema must be at v2 before seeding runs)

**Files:**
- Modify: `lib/db/app_database.dart`
- Modify: `lib/db/daos/users_dao.dart` (add `createDefaultUser` or expose `insertUser`)
- Test: `test/db/base_seed_test.dart` (new)

**Approach:**
- Extract a `_seedBaseData(AppDatabase db)` async function (or method) called at the end of `migration.onCreate`.
- It creates a single default user (stable mock ID: `'default-user'`, name `'Coach'`) then calls `db.sportPresetsDao.seedBuiltInsForUser('default-user')`.
- On subsequent launches (onUpgrade), base seed is NOT re-run — only on `onCreate`. Reset (F2) handles rebuilding by dropping and recreating the DB, which re-triggers `onCreate`.
- Use `insertOnConflictUpdate` so the function is safe to call idempotently if needed.

**Patterns to follow:**
- `lib/db/daos/sport_presets_dao.dart` — `seedBuiltInsForUser` pattern.
- `test/test_helpers.dart` — `_seedInMemoryDb` reference for which entities to create.

**Test scenarios:**
- Happy path: `AppDatabase.forTesting(memory)` opens → `usersDao.allUsers()` returns exactly 1 user with id `'default-user'`.
- Happy path: Sport presets for `'default-user'` cover every value in `kSports` (7 presets).
- Edge case: `_seedBaseData` called twice on same DB → no duplicate users created (idempotent).
- Happy path (migration guard): upgrading from v1 → v2 does NOT re-run `_seedBaseData` — only adds the `start_seconds` column.

**Verification:**
- `just test` passes.
- After a clean install in mock mode, `allUsers()` returns 1 record before `MockDataSeeder` has run.

---

### U5. MockDataSeeder service

**Goal:** Create `lib/db/mock_data_seeder.dart` that reads the five fixture JSON files from the asset bundle and inserts them into the Drift DB. Wire it into app startup behind `kUseMockData`.

**Requirements:** R1, R5, R6, R7

**Dependencies:** U2 (fixture files), U3 (ClipsDao), U4 (base seed runs first)

**Files:**
- Create: `lib/db/mock_data_seeder.dart`
- Modify: `lib/main.dart` (wire seeder after DB open)
- Test: `test/db/mock_data_seeder_test.dart` (new)

**Approach:**
- `MockDataSeeder` is a plain class (no Riverpod dependency) with a single `Future<void> seed(AppDatabase db)` method.
- Load each fixture JSON via `rootBundle.loadString('assets/mock/fixtures/X.json')`.
- Parse into typed maps; call the appropriate DAO insert methods.
- Insertion order: teams → matches → events (linked to matches) → recordings → streaming destinations.
- Use `insertOnConflictUpdate` (or `insertOrIgnore`) so `seed()` is safe to call after a reset without clearing first.
- In `lib/main.dart`, after `ProviderScope` injects the DB: `if (kUseMockData) { await MockDataSeeder().seed(db); }`.
- The debug screen reset (U9) calls `db.close() → delete file → reopen → await _seedBaseData() → if kUseMockData → await MockDataSeeder().seed(db)`. This full sequence is triggered by the reset action.

**Patterns to follow:**
- `test/test_helpers.dart:_seedInMemoryDb` — entity coverage reference.
- `lib/services/backup_service.dart` — `rootBundle` / JSON parsing pattern.

**Test scenarios:**
- Happy path: `MockDataSeeder().seed(db)` on a base-seeded test DB → `teamsDao.allTeams()` returns ≥ 1 team.
- Happy path: matches loaded → `teamMatchesDao.upcomingMatches()` returns 1, `pastMatches()` returns 3.
- Happy path: recordings fixture populated → accessible from `libraryProvider` after U8.
- Edge case: `seed()` called twice → no duplicate records (idempotent).
- Error path: malformed JSON in fixture → `FormatException` propagated with a clear message identifying which fixture file failed.

**Verification:**
- `flutter run --dart-define=kUseMockData=true` → library tab shows 3 past matches, settings shows default user and 1 team — all without a physical device.
- `just test` passes.

---

### U6. ScoutDevice model extension and file path standardization

**Goal:** Add `batteryPercent` and `rssi` as nullable `int?` fields to `ScoutDevice`. Fix `MockWifiService` to save downloads to `getApplicationSupportDirectory()/videos/` instead of `/tmp`. Introduce `VideoPathService` for consistent path computation.

**Requirements:** R8, R9, R22

**Dependencies:** None (parallel-safe with U1–U5)

**Files:**
- Modify: `lib/models/device.dart`
- Create: `lib/services/video_path_service.dart`
- Modify: `lib/wifi/mock_wifi_service.dart` (fix line ~212)
- Modify: `lib/ble/mock_ble_service.dart` (populate new fields)
- Test: `test/services/video_path_service_test.dart` (new)

**Approach:**
- `ScoutDevice`: add `final int? batteryPercent` and `final int? rssi` (nullable because values may not be available during scan).
- Update `ScoutDevice` constructor, `==` operator, and `hashCode` if needed — `id` remains the identity field.
- `VideoPathService`: a stateless class with two async methods: `Future<String> recordingsDir()` (returns `{supportDir}/videos`) and `Future<String> clipPath(recordingId, startSeconds)` (returns `{supportDir}/videos/{recordingId}_clip_{startSeconds}.mp4`). Calls `getApplicationSupportDirectory()` and creates the directory if absent.
- `MockWifiService.startDownload`: replace `saveAs ?? '/tmp/${token.recordingId}.mp4'` with `saveAs ?? await VideoPathService().recordingsPath(token.recordingId)`.

**Patterns to follow:**
- `lib/db/app_database.dart` — `getApplicationSupportDirectory()` usage for the DB path.
- `lib/models/recording.dart` — `ScoutDevice` field pattern.

**Test scenarios:**
- Happy path: `VideoPathService().recordingsDir()` returns a path under the app support directory (not `/tmp`).
- Happy path: `clipPath('rec-1', 300)` returns a path ending in `rec-1_clip_300.mp4`.
- Happy path: the directory is created by `recordingsDir()` if it does not exist.
- Happy path: `MockWifiService.startDownload` with `saveAs=null` → download saved to the app-private videos dir.
- Happy path: `ScoutDevice` constructed with `batteryPercent: 80, rssi: -65` → fields accessible.
- Edge case: `ScoutDevice` constructed without `batteryPercent` and `rssi` (null) → no NPE in UI display code.

**Verification:**
- `grep -rn '"/tmp/' lib/` returns zero hits.
- `just test` passes.

---

### U7. Phase 7 label cleanup

**Goal:** Remove every "Phase 7" string from source files in `lib/`; relabel stubs with plain `TODO: wire to firmware — ...` comments or `UnimplementedError`s without phase numbering.

**Requirements:** R23, R24

**Dependencies:** None

**Files:**
- Modify: `lib/ble/ble_service_impl.dart` (lines ~14, 213, 222, 235, 304)
- Modify: `lib/wifi/wifi_service_impl.dart` (lines ~9, 23, 29, 55)
- Modify: `lib/state/app_data.dart` (lines ~5, 955 — comments only)
- Modify: `docs/plans/2026-05-05-001-feat-settings-page-reshape-plan.md` (remove "Phase 7" from Deferred section)
- Modify: `docs/plans/2026-05-05-003-refactor-app-source-of-truth-plan.md` (remove "Phase 7" references)
- Test: `test/phase7_cleanup_test.dart` (a simple grep-based test verifying no Phase 7 strings remain)

**Approach:**
- In `ble_service_impl.dart`: replace `'Phase 7: proto encoding + BLE write not yet implemented'` → `'TODO: wire to firmware — BLE proto encoding and chunking'`. Same pattern for `pushSessionConfig`.
- In `wifi_service_impl.dart`: replace each "Phase 7: ..." `UnimplementedError` message with `'TODO: wire to firmware — WiFi Direct group negotiation'`, `'TODO: wire to firmware — HTTP recording download'`, etc.
- Remove `// Phase 7` comments in `app_data.dart`.
- In plan docs, replace "Phase 7" references with plain prose (e.g., "firmware integration" or "future firmware wiring").

**Test scenarios:**
- Verification test: `expect(grep('Phase 7', 'lib/'), isEmpty)` — implemented as a Dart test that reads source files and asserts the string is absent.

**Verification:**
- `grep -rn "Phase 7" lib/ docs/plans/` returns zero lines.

---

### U8. libraryProvider DB-backed refactor

**Goal:** Replace the inline `_seedLibrary` Dart constant and the `libraryProvider` that returns it with a Drift-backed provider that queries `TeamMatchesTable` (joined with `TeamsTable` and `ClipsTable`).

**Requirements:** R18, R25

**Dependencies:** U3 (ClipsDao), U5 (MockDataSeeder populates the matches the provider will query)

**Files:**
- Modify: `lib/state/app_data.dart` (remove `_seedLibrary` const, replace `libraryProvider`)
- Modify: `lib/db/daos/teams_dao.dart` or create `lib/db/daos/team_matches_dao.dart` (add `pastMatchesForLibrary()` query returning joined rows)
- Test: `test/state/library_provider_test.dart` (new)

**Approach:**
- Add a `pastMatchesForLibrary()` method to the appropriate DAO that returns a stream of rows joining `TeamMatchesTable` ↔ `TeamsTable` (for team name) and a left-join with `ClipsTable` (for clip count and total size).
- `libraryProvider` becomes a `StreamProvider<List<LibraryMatch>>` (or `AsyncNotifier`) that subscribes to that DAO stream.
- `LibraryMatch` is assembled from the joined rows rather than from inline constants; its shape is preserved for UI compatibility.
- Remove the `_seedLibrary` const list and the `LibraryEvent` inline data — these are now populated by the DB via `MockDataSeeder` fixtures or real BLE data.
- The comment "library will move to BLE in Phase 7" is replaced with an inline note that the provider reads from the local DB (seeded by mock fixtures or future BLE sync).

**Patterns to follow:**
- `lib/state/app_data.dart` — `TeamsController` as an `AsyncNotifier` for the error-handling pattern.
- `lib/db/daos/teams_dao.dart` — `watchForUser()` join query for the multi-table stream pattern.
- Institutional learning: watch streams must include `onError:`.

**Test scenarios:**
- Happy path (mock mode): after `MockDataSeeder.seed()`, `libraryProvider` stream emits 3 `LibraryMatch` items.
- Happy path (empty DB): `libraryProvider` stream emits an empty list.
- Integration: insert a new `TeamMatch` row via DAO → `libraryProvider` stream emits an updated list.
- Edge case: team for a match is deleted → cascade removes the match; `libraryProvider` emits without the deleted entry.

**Verification:**
- `just test` passes.
- Library tab shows 3 matches in an emulator session with `kUseMockData=true` and an empty state without it.

---

### U9. In-app debug screen

**Goal:** Create `lib/pages/debug_page.dart` with browsable DB table views and a Reset action. Wire a long-press gesture on the About row in Settings (non-prod builds only) to navigate to it.

**Requirements:** R11

**Dependencies:** U3 (ClipsDao), U4 (base seed to display), U5 (MockDataSeeder called by reset)

**Files:**
- Create: `lib/pages/debug_page.dart`
- Modify: `lib/pages/settings_page.dart` (wrap About row in `GestureDetector`, gate by `kAppEnv != AppEnv.prod`)
- Test: `test/pages/debug_page_test.dart` (new — widget test)

**Approach:**
- `DebugPage` is a stateful widget with a `TabBar` or `ListView` showing one section per table: Users, Teams, TeamMatches, Clips.
- Each section calls the relevant DAO and renders rows as simple `ListTile` items (id + one label field). No editing UI.
- "Reset DB" `FilledButton` at the bottom: triggers `ref.read(appDatabaseProvider).close()` → delete file → re-init via `AppDatabase()` → `_seedBaseData()` → if `kUseMockData`, `MockDataSeeder().seed()`. Navigates back to root after reset.
- In `settings_page.dart`, the About `_RowItem` is wrapped in a `GestureDetector(onLongPress: () { if (kAppEnv != AppEnv.prod) Navigator.push(..., DebugPage()) }`. No visual indicator in prod builds — the gesture simply does nothing.

**Patterns to follow:**
- `lib/pages/diagnostics_page.dart` — existing debug-style page structure.
- `lib/pages/sport_presets_page.dart` — simple `ListView` of DB rows pattern.

**Test scenarios:**
- Happy path: `DebugPage` renders with tabs; each tab shows data from the seeded test DB.
- Happy path: Reset action in a widget test → DB is cleared and re-seeded; `DebugPage` renders updated (empty or re-seeded) tables.
- Edge case (prod): navigating to settings in a prod build → long-press on About row does nothing (no `DebugPage` push).
- Integration: long-press → `DebugPage` opens; shows default user row.

**Verification:**
- Long-press on the About row in a `dev` build opens the debug screen.
- Long-press in a `prod` build does nothing.
- Reset action returns the app to a clean or mock-seeded state.

---

### U10. Compact score section on live preview

**Goal:** Verify that `_ScoreBlock` in `match_page.dart` satisfies R15 and F4/AE4. If the live preview page is a separate route from `_SessionScreen`, ensure the score section exists there too.

**Requirements:** R14, R15, R16

**Dependencies:** U5 (mock events populate the score via `liveMatchProvider`)

**Files:**
- Read: `lib/pages/match_page.dart` (verify `_LiveThumb._ScoreBlock` is on the right route)
- Modify: `lib/pages/match_page.dart` (only if the score section is missing or on the wrong screen)
- Test: `test/pages/match_page_score_test.dart` (new — widget test)

**Approach:**
- Confirm that `_ScoreBlock` is rendered as part of the live preview screen that A1/A2 sees during a match session (F4 trigger).
- Confirm the score is derived live from `liveMatchProvider.homeScore` / `awayScore` (no separate polling needed).
- In mock mode, `liveMatchProvider` is populated from mock events; the score should update when mock events are dispatched.
- If `_ScoreBlock` is only rendered inside a collapsed `_LiveThumb` (preview thumbnail, not full-screen), extend the full-screen `_SessionScreen` to include a persistent score row.

**Patterns to follow:**
- `match_page.dart` existing `_ScoreBlock` widget and `liveMatchProvider` derivation.

**Test scenarios:**
- Happy path: `_SessionScreen` renders with a score section showing `0 – 0` on initial state.
- Happy path (AE4): after a "Goal — Home" event is added to `liveMatchProvider`, score section updates to `1 – 0` without user interaction.
- Edge case: score section is visible even when the event log is empty.
- Edge case: score section persists when the event log is scrolled.

**Verification:**
- Score section is visible without scrolling on the live preview page.
- Adding a goal event updates the score display within one frame.

---

### U11. Highlight trimming service

**Goal:** Add `ffmpeg_kit_flutter_min` dependency, create `ClipService` that trims an MP4 with `-c copy`, and wire the trim action to `ClipsDao` record creation and an in-app share sheet.

**Requirements:** R19, R20, R21

**Dependencies:** U3 (ClipsDao), U6 (VideoPathService for output path)

**Files:**
- Modify: `pubspec.yaml` (add `ffmpeg_kit_flutter_min`)
- Create: `lib/services/clip_service.dart`
- Modify: `lib/pages/video_match_detail_page.dart` (wire trim action to `ClipService`)
- Test: `test/services/clip_service_test.dart` (new)

**Approach:**
- `ClipService.trim({required sourcePath, required startSeconds, required durationSeconds, required outputPath})` runs the FFmpeg command `-ss {start} -t {duration} -c copy -y {output}` via `FFmpegKit.execute()`.
- On success (return code 0): call `ClipsDao.insertClip(...)` to persist the clip record.
- On failure: surface `ClipTrimException` with the FFmpeg log excerpt.
- After trim completes, the caller presents either an in-app video player or the system share sheet (`Share.shareXFiles([XFile(outputPath)])`) — the UI decides which; `ClipService` only produces the file.
- `ClipService` is a plain class (no Riverpod); injected as a dependency of the video detail page provider.
- In mock mode, the source video is the mock asset path; `VideoPlayerController.asset(...)` on the mock video serves as the test subject for the trim.

**Patterns to follow:**
- `lib/services/backup_service.dart` — service class without Riverpod, injected via providers.
- `lib/wifi/mock_wifi_service.dart` — async progress reporting pattern (for future trim-progress if needed).

**Test scenarios:**
- Happy path: `ClipService.trim` with valid params on `mock-video.mp4` at offset 10s, duration 5s → output file exists at expected path; return code 0.
- Happy path: `ClipsDao` record inserted after successful trim with correct `startSeconds` and `durationSeconds`.
- Error path: source file does not exist → `ClipTrimException` thrown; no DB record created.
- Edge case: `durationSeconds` extends beyond video end → FFmpeg handles gracefully (clips to end); no crash.
- Error path: FFmpeg return code non-zero → exception with log message; no partial file left at output path (or file cleaned up).
- Integration (Covers F3 / AE5): given a match with a "Goal" event at 12:30 in mock mode, trim action produces an MP4 at the expected path playable by `video_player`.

**Verification:**
- Trim action on the video match detail page produces a file.
- The file is playable using `VideoPlayerController.file(outputPath)`.
- A `Clip` row appears in the debug screen DB view after a successful trim.
- `just test` passes for `clip_service_test.dart`.

---

## System-Wide Impact

- **Interaction graph:** `AppDatabase.migration.onCreate` now calls `_seedBaseData`; `main.dart` conditionally calls `MockDataSeeder.seed`; `DebugPage` reset action touches all of these. `libraryProvider` switches from a sync `Provider` to a `StreamProvider` — all consumers become async-aware.
- **Error propagation:** `MockDataSeeder` fixture parse failures should be logged and surfaced as a developer-visible error (not silently swallowed). `ClipService` exceptions propagate to the UI caller; no silent failures.
- **State lifecycle risks:** The debug screen reset closes and deletes the SQLite file while Riverpod providers may still hold references to it. The reset action must invalidate all DB-touching providers after reopening the DB. Consider `ProviderContainer.invalidateAll()` or a targeted list of DB-dependent providers.
- **API surface parity:** `ScoutDevice` gains nullable fields — all existing construction sites (`MockBleService`, `BleServiceImpl`) must pass values or `null`. No existing callers should break, but a compile-time scan is needed.
- **Integration coverage:** The full F3 flow (trim → DB record → in-app play or share) crosses `ClipService` → `ClipsDao` → `VideoMatchDetailPage`. A widget integration test covering this path end-to-end is higher-value than unit tests of each layer in isolation.
- **Unchanged invariants:** `BleService` abstract interface is unchanged. `BackupService` export/import paths are unchanged. `SportPresetsDao.seedBuiltInsForUser` contract is unchanged.

---

## Risks & Dependencies

| Risk | Mitigation |
|------|------------|
| 103 MB `mock-video.mp4` inflates all debug APKs | Accepted for dev builds; production exclusion via build flavor deferred (see Scope Boundaries) |
| `ffmpeg_kit_flutter_min` may not ship to iOS simulator | Test on a physical device or Android emulator; document iOS simulator limitation |
| DB reset in `DebugPage` may leave dangling Riverpod stream subscriptions | Invalidate all DB providers after the new `AppDatabase` is open; add a Riverpod scope reset if needed |
| `libraryProvider` change from `Provider` → `StreamProvider` may break existing consumers | Grep for all `ref.watch(libraryProvider)` usages before landing U8; update callers |
| `ClipsTable` migration may fail on devices with existing v1 DBs in dev | Test with an existing v1 DB on a device before landing U3; the migration is a single `ALTER TABLE ADD COLUMN` which is safe in SQLite |
| `ScoutDevice` nullable field addition may cause null-check exceptions in UI | Audit all `device.batteryPercent` / `device.rssi` call sites before landing U6; add null-guards |

---

## Sources & References

- **Origin document:** [docs/brainstorms/2026-05-11-mock-system-requirements.md](docs/brainstorms/2026-05-11-mock-system-requirements.md)
- Related code: `lib/env.dart`, `lib/db/app_database.dart`, `lib/wifi/mock_wifi_service.dart:212`, `lib/state/app_data.dart:958`
- Institutional learning: `docs/solutions/architecture-patterns/app-source-of-truth-drift-sqlite-2026-05-06.md`
- External: `pub.dev/packages/ffmpeg_kit_flutter` (LGPL min variant)
- Settings page About row: `lib/pages/settings_page.dart` lines 96–103
- Phase 7 occurrences: `lib/ble/ble_service_impl.dart` lines 14, 213, 222, 235, 304; `lib/wifi/wifi_service_impl.dart` lines 9, 23, 29, 55
