---
date: 2026-05-21
plan_number: "008"
type: refactor
status: completed
origin: docs/brainstorms/2026-05-21-file-structure-requirements.md
---

# refactor: Restructure lib/ to Feature-Based Layout

## Problem Frame

`lib/` is a type-based flat layout — `pages/`, `state/`, `models/`, `ble/`, etc. — that no longer scales. Three symptoms: (1) `match_page.dart` is 2 763 lines with 40+ private classes; `app_data.dart` is 1 351 lines mixing four unrelated controllers; (2) there is no predictable location for new files — form sheets and full pages coexist at the same flat level; (3) mock implementations are scattered across domain folders alongside real code.

This plan reorganises `lib/` into a feature-based layout without changing any behavior, provider wiring, or public API.

---

## Scope Boundaries

### In scope
- Move and reorganise all files under `lib/`
- Extract private screen/tab/sheet classes into their own files (make public where needed)
- Split `app_data.dart` into per-feature state files
- Update all relative imports in `lib/` and all package imports in `test/`
- Restructure `test/` to mirror the new `lib/` layout — test files move to `test/features/`, `test/core/`, `test/mock/` matching their lib counterpart

### Deferred to Follow-Up Work
- Adding new tests for extracted classes (covered by existing tests via the same widget under test)

### Out of scope (R14)
- No changes to provider logic, data flow, or feature behaviour
- No barrel (`index.dart`) files
- No changes to `proto/`, `assets/`, `justfile`, `pubspec.yaml`, or CI workflow files

---

## Key Technical Decisions

| Decision | Rationale |
|---|---|
| Core-first sequencing | `lib/core/` files are imported by features; they must land at new paths before features move and update their imports |
| State files created fresh in their feature folders | `app_data.dart` is not moved wholesale — each controller is extracted into a new file created at its target path, avoiding a transient state where half the file is gone |
| Mock files moved after real services (U4) | `mock_ble_service.dart` imports `BleService` from `ble/`; moving real services first means the mock's new path at `lib/mock/` can import from `lib/core/ble/` with correct relative paths |
| Each unit ends with `flutter analyze` | Relative imports in `lib/` mean a missed update produces an immediate compile error; running analyze per unit surfaces mistakes before they compound |
| `just gen-db` after db/ moves (U3) | Generated `.g.dart` files use `part of` and are safe to move with parents, but re-running codegen after the move confirms the build chain still works |
| `debug_page.dart` dependency on `_MatchesTab` fixed in U9 | Research found `debug_page.dart` references the private `_MatchesTab` across file boundaries — this becomes valid when `_MatchesTab` is promoted to public `TeamMatchesTab` in U9 |
| `live_preview_view.dart` stays in `core/widgets/` | Imported by both `main_page.dart` and `match_page.dart` — two features share it, so it is a shared widget per R11.4 |
| Test restructure deferred to U12 | All lib/ units update test import paths in-place as a side-effect of each unit's import sweep; test files physically move in U12 after all lib/ destinations are settled — one sweep instead of 12 incremental ones |

---

## High-Level Technical Design

*This illustrates the intended approach and is directional guidance for review, not implementation specification.*

### Per-file move protocol

Every file move in this plan follows the same four-step pattern:

1. **Create** the file at its target path with the same content
2. **Update outbound imports** in the new file — relative paths change since the file is now at a different depth/location
3. **Update all inbound imports** — every file in `lib/` that imported the old path (relative) and every file in `test/` that imported the old path (package) gets its import updated to the new path
4. **Delete** the original file

This is repeated for every moved file within a unit. The unit ends with `flutter analyze` before proceeding.

### Dependency sequencing

```
U1 (scaffold)
  └─ U2 (core/models, core/theme, core/widgets)
       └─ U3 (core/ble, core/db, core/wifi, core/services)
            └─ U4 (lib/mock/)
                 └─ U5 (core/config, core/shell, core/state providers)
                      └─ U6 (split app_data.dart → feature state files)
                           ├─ U7 (discovery feature)
                           ├─ U8 (settings feature)
                           ├─ U9 (teams feature + tab extraction)
                           ├─ U10 (video feature + DownloadSheet)
                           └─ U11 (match feature + screen extraction)
                                └─ U12 (restructure test/ to mirror lib/)
                                     └─ U13 (cleanup + verification)
```

U7–U11 are independent of each other once U6 is complete and can be executed in any order. U12 runs after all lib/ restructuring is complete so test file moves and import updates can be done in one sweep.

---

## Output Structure

```
lib/
  main.dart
  app.dart
  features/
    match/
      match_page.dart
      landing_screen.dart
      setup_screen.dart
      match_state.dart
      session/
        session_screen.dart
        event_sheet.dart
        session_state.dart
    teams/
      teams_page.dart
      team_detail_page.dart
      team_form_sheet.dart
      teams_state.dart
      roster/
        roster_tab.dart
        player_form_sheet.dart
      stats/
        stats_tab.dart
      matches/
        team_matches_tab.dart
        team_match_form_sheet.dart
    video/
      video_page.dart
      video_team_matches_page.dart
      video_state.dart
      playback/
        video_match_detail_page.dart
        download_sheet.dart
    settings/
      settings_page.dart
      users/
        users_settings_page.dart
        user_form_sheet.dart
        users_state.dart
      sport_presets/
        sport_presets_page.dart
        sport_preset_form_sheet.dart
        sport_presets_state.dart
      streaming/
        streaming_destinations_page.dart
        streaming_destination_form_sheet.dart
        streaming_state.dart
      data/
        data_settings_page.dart
    discovery/
      discovery_page.dart
      debug_page.dart
      diagnostics_page.dart
  core/
    config/
      app_config.dart
      env.dart
    shell/
      app_shell.dart
    ble/
      ble_service.dart
      ble_service_impl.dart
      ble_providers.dart
    db/
      app_database.dart
      app_database.g.dart
      tables/
      daos/
    wifi/
      wifi_service.dart
      wifi_service_impl.dart
      wifi_providers.dart
      wifi_handoff.dart
    services/
      backup_service.dart
      clip_service.dart
      video_path_service.dart
    state/
      last_camera.dart
      db_providers.dart
    models/
      command.dart
      device.dart
      match.dart
      recording.dart
      sport_preset.dart
      streaming.dart
      team.dart
      telemetry.dart
      user.dart
      wifi.dart
      proto/
    widgets/
      indicators.dart
      live_preview_view.dart
      wf_button.dart
      wf_card.dart
      wf_chip.dart
    theme/
      tokens.dart
  mock/
    mock_ble_service.dart
    mock_wifi_service.dart
    mock_data_seeder.dart
```

---

## Implementation Units

### U1. Scaffold folder structure

**Goal:** Create all new directories so subsequent units can place files immediately without creating directories on the fly.

**Requirements:** R1, R2, R12

**Dependencies:** none

**Files:**
- `lib/features/match/session/` (create directory)
- `lib/features/teams/roster/` (create directory)
- `lib/features/teams/stats/` (create directory)
- `lib/features/teams/matches/` (create directory)
- `lib/features/video/playback/` (create directory)
- `lib/features/settings/users/` (create directory)
- `lib/features/settings/sport_presets/` (create directory)
- `lib/features/settings/streaming/` (create directory)
- `lib/features/settings/data/` (create directory)
- `lib/features/discovery/` (create directory)
- `lib/core/config/` (create directory)
- `lib/core/shell/` (create directory)
- `lib/core/ble/` (create directory)
- `lib/core/db/tables/` (create directory)
- `lib/core/db/daos/` (create directory)
- `lib/core/wifi/` (create directory)
- `lib/core/services/` (create directory)
- `lib/core/state/` (create directory)
- `lib/core/models/proto/` (create directory, gitignored contents move with parent)
- `lib/core/widgets/` (create directory)
- `lib/core/theme/` (create directory)
- `lib/mock/` (create directory)

**Approach:** Create all directories before any file moves. No files are created or changed — this unit is a pure directory scaffold. Placing a `.gitkeep` is not needed since subsequent units fill the directories immediately.

**Test scenarios:**
- Test expectation: none — directory creation produces no behavioral change; `flutter analyze` still passes on the unchanged codebase

**Verification:** `ls lib/features lib/core lib/mock` shows the expected sub-folders; `flutter analyze` reports zero errors.

---

### U2. Move core/models, core/theme, core/widgets

**Goal:** Establish `lib/core/models/`, `lib/core/theme/`, and `lib/core/widgets/` with all shared data models and UI primitives. These are the most widely imported files in the codebase; settling them first lets every subsequent unit import from their final paths.

**Requirements:** R2.1, R2.2 (models/theme/widgets portion)

**Dependencies:** U1

**Files:**
- `lib/core/models/command.dart` (moved from `lib/models/command.dart`)
- `lib/core/models/device.dart`
- `lib/core/models/match.dart`
- `lib/core/models/recording.dart`
- `lib/core/models/sport_preset.dart`
- `lib/core/models/streaming.dart`
- `lib/core/models/team.dart`
- `lib/core/models/telemetry.dart`
- `lib/core/models/user.dart`
- `lib/core/models/wifi.dart`
- `lib/core/theme/tokens.dart` (moved from `lib/theme/tokens.dart`)
- `lib/core/widgets/indicators.dart` (moved from `lib/widgets/indicators.dart`)
- `lib/core/widgets/live_preview_view.dart`
- `lib/core/widgets/wf_button.dart`
- `lib/core/widgets/wf_card.dart`
- `lib/core/widgets/wf_chip.dart`
- All `lib/` and `test/` files that import any of the above (import path updates only)

**Approach:** Apply the per-file move protocol for each file. The `proto/` directory inside `lib/models/` is gitignored generated code — move the directory structure but the generated files regenerate via `just gen-proto`. After all moves, delete `lib/models/`, `lib/theme/`, and `lib/widgets/`.

Model files have minimal outbound imports (mostly `package:flutter` and sibling models). The bulk of the work here is updating inbound imports: approximately 30–40 import statements across `lib/ble/`, `lib/state/`, `lib/pages/`, `lib/services/`, and `test/`.

**Test scenarios:**
- `flutter analyze` passes with zero errors after all imports are updated
- `just test` passes — no model or widget behavior changes

**Verification:** `lib/models/`, `lib/theme/`, `lib/widgets/` directories no longer exist; `flutter analyze` clean.

---

### U3. Move core/ble, core/db, core/wifi, core/services

**Goal:** Move the real (non-mock) service and infrastructure files to `lib/core/`. Generated `.g.dart` files move with their parent DAOs/database class.

**Requirements:** R2.1, R2.2 (ble/db/wifi/services portion)

**Dependencies:** U2 (ble_service_impl imports from core/models; moving it after models are settled avoids a two-step import update)

**Files:**
- `lib/core/ble/ble_service.dart` (moved from `lib/ble/ble_service.dart`)
- `lib/core/ble/ble_service_impl.dart`
- `lib/core/db/app_database.dart` (moved from `lib/db/app_database.dart`)
- `lib/core/db/app_database.g.dart`
- `lib/core/db/tables/clips_table.dart` (and all other table files)
- `lib/core/db/tables/sport_presets_table.dart`
- `lib/core/db/tables/streaming_destinations_table.dart`
- `lib/core/db/tables/team_matches_table.dart`
- `lib/core/db/tables/teams_table.dart`
- `lib/core/db/tables/thumbnails_table.dart`
- `lib/core/db/tables/users_table.dart`
- `lib/core/db/daos/clips_dao.dart` (and all other DAO files + their .g.dart)
- `lib/core/db/daos/sport_presets_dao.dart`
- `lib/core/db/daos/streaming_destinations_dao.dart`
- `lib/core/db/daos/teams_dao.dart`
- `lib/core/db/daos/users_dao.dart`
- `lib/core/wifi/wifi_service.dart` (moved from `lib/wifi/wifi_service.dart`)
- `lib/core/wifi/wifi_service_impl.dart`
- `lib/core/services/backup_service.dart` (moved from `lib/services/backup_service.dart`)
- `lib/core/services/clip_service.dart`
- `lib/core/services/video_path_service.dart`
- All `lib/` and `test/` files that import any of the above (import path updates)

**Approach:** Apply the per-file move protocol. The `.g.dart` files use `part of` directives pointing to their parent file — update these `part of` declarations to reflect the new file path. The `part` declarations in the parent files (`app_database.dart`, `*_dao.dart`) also need updating to point to their `.g.dart` siblings at the new location. Mock files (`mock_ble_service.dart`, `mock_wifi_service.dart`, `mock_data_seeder.dart`) are left in their current location — they are moved in U4.

After moving db/, run `just gen-db` to verify the build tool can still resolve the Drift schema and regenerate cleanly.

**Test scenarios:**
- `just gen-db` completes without errors
- `flutter analyze` passes after all imports updated
- `just test` passes — all DAO and service tests pass unchanged (imports updated in test files)

**Verification:** `lib/ble/`, `lib/db/`, `lib/wifi/`, `lib/services/` directories no longer exist; `flutter analyze` clean; `just test` green.

---

### U4. Move mock files to lib/mock/

**Goal:** Consolidate all dev-time fake implementations under `lib/mock/`.

**Requirements:** R12

**Dependencies:** U3 (mock files import from real services; those are now at `lib/core/ble/`, `lib/core/wifi/`, etc. — importing from correct final paths)

**Files:**
- `lib/mock/mock_ble_service.dart` (moved from `lib/ble/mock_ble_service.dart`)
- `lib/mock/mock_wifi_service.dart` (moved from `lib/wifi/mock_wifi_service.dart`)
- `lib/mock/mock_data_seeder.dart` (moved from `lib/db/mock_data_seeder.dart`)
- All `lib/` and `test/` files that import any mock (import path updates — approximately 15+ test files import mock_ble_service)

**Approach:** Apply the per-file move protocol. The mock classes' outbound imports update to point to `lib/core/ble/`, `lib/core/db/`, `lib/core/wifi/` using paths relative to `lib/mock/`. The inbound import sweep is the largest in this unit: `test/` files importing mocks use `package:sst_cam_app/ble/mock_ble_service.dart` — update all to `package:sst_cam_app/mock/mock_ble_service.dart`. Class names and interfaces are unchanged.

**Test scenarios:**
- `flutter analyze` passes
- `just test` passes — mock-dependent tests continue to work
- `test/ble/mock_ble_service_test.dart` passes (imports updated)

**Verification:** No `mock_*.dart` files remain under `lib/core/`; `flutter analyze` clean.

---

### U5. Move core/config, core/shell, core/state providers

**Goal:** Move the remaining infrastructure files — app config, env, app shell, and the provider files currently in `lib/state/` — to their final locations. Deletes `lib/state/`.

**Requirements:** R2.3, R2.4, R2.5, R2.6, R2.7

**Dependencies:** U3 (provider files import from `lib/core/ble/`, `lib/core/wifi/`, etc.)

**Files:**
- `lib/core/config/app_config.dart` (moved from `lib/app_config.dart`)
- `lib/core/config/env.dart` (moved from `lib/env.dart`)
- `lib/core/shell/app_shell.dart` (moved from `lib/app_shell.dart`)
- `lib/core/ble/ble_providers.dart` (moved from `lib/state/ble_providers.dart`)
- `lib/core/wifi/wifi_providers.dart` (moved from `lib/state/wifi_providers.dart`)
- `lib/core/wifi/wifi_handoff.dart` (moved from `lib/state/wifi_handoff.dart`)
- `lib/core/state/db_providers.dart` (moved from `lib/state/db_providers.dart`)
- `lib/core/state/last_camera.dart` (moved from `lib/state/last_camera.dart`)
- `lib/app.dart` (import update: `app_shell.dart` → `core/shell/app_shell.dart`, `app_config.dart` → `core/config/app_config.dart`)
- `lib/main.dart` (import update: `env.dart` → `core/config/env.dart`)
- All other `lib/` files importing `env.dart`, `app_config.dart`, or any `state/` provider (import updates)
- All `test/` files importing `app_shell.dart`, `last_camera.dart`, or any provider (import updates)
- `test/app_shell_test.dart` (import update)
- `test/state/last_camera_test.dart` (import update)

**Approach:** Apply the per-file move protocol for each file. `env.dart` is imported by 6 `lib/` files; each updates its relative import. After all files are moved and imports updated, delete `lib/state/`. At this point, `lib/app_config.dart`, `lib/env.dart`, and `lib/app_shell.dart` at the old root are also deleted — they have been replaced by their `lib/core/` counterparts.

**Test scenarios:**
- `flutter analyze` passes
- `test/app_shell_test.dart` passes
- `test/state/last_camera_test.dart` passes
- `just test` fully green

**Verification:** `lib/state/` directory deleted; `lib/app_config.dart`, `lib/env.dart`, `lib/app_shell.dart` deleted; `lib/` root contains only `main.dart` and `app.dart`; `flutter analyze` clean.

---

### U6. Split app_data.dart into feature state files

**Goal:** Dissolve `lib/state/app_data.dart` by creating seven new state files, each owning one domain's controllers and models. Update all 14 lib/ consumers and 8 test consumers to import from their specific new file. Delete `app_data.dart`.

**Requirements:** R4, R5.8, R7.3, R7.5, R7.7, R8, R9.3

**Dependencies:** U5 (new state files import from `lib/core/`; those paths must be settled)

**Files created:**
- `lib/features/match/match_state.dart` — `UpcomingMatch` and match-level providers
- `lib/features/match/session/session_state.dart` — `LiveMatchController`, `LiveMatchState`, `LiveEvent`
- `lib/features/teams/teams_state.dart` — `TeamsController`
- `lib/features/video/video_state.dart` — `LibraryEvent`, `LibraryMatch`, video providers
- `lib/features/settings/users/users_state.dart` — `UsersController`, `UsersControllerException`
- `lib/features/settings/sport_presets/sport_presets_state.dart` — `SportPresetsController`, `SportPresetsControllerException`
- `lib/features/settings/streaming/streaming_state.dart` — `StreamingDestinationsController`

**Files modified:**
- All 14 `lib/` files that import `app_data.dart`: each switches its import from `state/app_data.dart` to the specific new file(s) it actually uses
- All 8 `test/` files that import `app_data.dart`: same import update to specific new files
- `lib/state/app_data.dart` — deleted after all content is extracted

**Approach:** Each new state file is created with a fresh write containing exactly the classes it owns, importing from `lib/core/` paths. Do not move `app_data.dart` and edit it — write each target file independently so there is no transient broken state. After all seven files exist and their consumers are updated, delete `app_data.dart`. For consumers that imported multiple symbols from `app_data.dart`, split the import into multiple targeted imports (one per new file). Provider names may be updated if a name is ambiguous after the split; wiring is unchanged.

**Test scenarios:**
- `flutter analyze` passes immediately after `app_data.dart` is deleted
- `test/state/app_data_filter_test.dart` passes with updated imports
- `test/state/active_user_providers_test.dart` passes with updated imports
- `just test` fully green
- No provider is imported from a wrong file (verify with `grep -r "app_data" lib/` returning zero results)

**Verification:** `grep -r "app_data" lib/` and `grep -r "app_data" test/` both return zero results; `flutter analyze` clean; `just test` green.

---

### U7. Move discovery feature

**Goal:** Move the three discovery-tab files into `lib/features/discovery/`.

**Requirements:** R1.1, R1.2, R10

**Dependencies:** U6 (discovery files import from `lib/core/` and from state files; all those are settled)

**Files:**
- `lib/features/discovery/discovery_page.dart` (moved from `lib/pages/discovery_page.dart`)
- `lib/features/discovery/debug_page.dart` (moved from `lib/pages/debug_page.dart`)
- `lib/features/discovery/diagnostics_page.dart` (moved from `lib/pages/diagnostics_page.dart`)
- `lib/core/shell/app_shell.dart` (import update: discovery page paths change)
- Any other `lib/` or `test/` files referencing discovery pages (import updates)

**Approach:** Apply the per-file move protocol for all three files. `debug_page.dart` imports `env.dart`, provider files, and `app_data`-derived symbols — all now at `lib/core/` or feature state paths. Update outbound relative imports accordingly.

**Test scenarios:**
- `flutter analyze` passes
- Any integration tests that navigate to the discovery/debug page continue to pass

**Verification:** `lib/pages/discovery_page.dart`, `lib/pages/debug_page.dart`, `lib/pages/diagnostics_page.dart` no longer exist.

---

### U8. Restructure settings feature

**Goal:** Move all settings pages and form sheets into `lib/features/settings/` sub-folders. State files were already created in U6.

**Requirements:** R7.1, R7.2, R7.4, R7.6, R7.8, R7.9, R10

**Dependencies:** U6 (settings state files already at their target paths)

**Files:**
- `lib/features/settings/settings_page.dart` (moved from `lib/pages/settings_page.dart`)
- `lib/features/settings/users/users_settings_page.dart` (moved from `lib/pages/users_settings_page.dart`)
- `lib/features/settings/users/user_form_sheet.dart` (moved from `lib/pages/user_form_sheet.dart`)
- `lib/features/settings/sport_presets/sport_presets_page.dart` (moved from `lib/pages/sport_presets_page.dart`)
- `lib/features/settings/sport_presets/sport_preset_form_sheet.dart` (moved from `lib/pages/sport_preset_form_sheet.dart`)
- `lib/features/settings/streaming/streaming_destinations_page.dart` (moved from `lib/pages/streaming_destinations_page.dart`)
- `lib/features/settings/streaming/streaming_destination_form_sheet.dart` (moved from `lib/pages/streaming_destination_form_sheet.dart`)
- `lib/features/settings/data/data_settings_page.dart` (moved from `lib/pages/data_settings_page.dart`)
- `lib/core/shell/app_shell.dart` (import update: settings page paths change)
- All test files referencing settings pages (import updates)

**Approach:** Apply the per-file move protocol. Outbound imports in each settings page now point to their state file sibling (e.g., `settings_page.dart` imports from `../users/users_state.dart` for user count display). Cross-sub-feature references within settings are resolved with relative paths (e.g., `streaming_destinations_page.dart` imports `../streaming_state.dart`).

**Test scenarios:**
- `flutter analyze` passes
- `test/integration/settings_page_test.dart` passes with updated imports
- `test/pages/settings_page_shell_test.dart` passes
- `test/pages/settings_user_section_test.dart` passes
- `test/pages/settings_streaming_section_test.dart` passes
- `test/pages/settings_camera_section_test.dart` passes
- `test/pages/settings_backup_restore_test.dart` passes
- `test/pages/sport_presets_built_in_test.dart` passes
- `test/pages/user_form_sheet_test.dart` passes
- `test/pages/streaming_destination_form_sheet_test.dart` passes

**Verification:** No `lib/pages/settings_*.dart`, `lib/pages/users_*.dart`, `lib/pages/sport_preset*.dart`, `lib/pages/streaming_*.dart`, `lib/pages/data_*.dart` files remain.

---

### U9. Restructure teams feature — move pages and extract tab widgets

**Goal:** Move teams pages into `lib/features/teams/` and extract the three tab widgets from `team_detail_page.dart` into their sub-feature folders. `team_detail_page.dart` becomes a thin tab host. Fixes the `debug_page.dart` cross-boundary access to the now-public `TeamMatchesTab`.

**Requirements:** R5, R9.1, R10

**Dependencies:** U6 (teams_state.dart already at `lib/features/teams/`)

**Files created:**
- `lib/features/teams/roster/roster_tab.dart` — extracted from `team_detail_page.dart`; `_RosterTab` → `RosterTab` (public)
- `lib/features/teams/stats/stats_tab.dart` — extracted from `team_detail_page.dart`; `_StatsTab` → `StatsTab` (public); `_LeaderboardTable` and other private helpers stay in this file
- `lib/features/teams/matches/team_matches_tab.dart` — extracted from `team_detail_page.dart`; `_MatchesTab` → `TeamMatchesTab` (public); `_MatchRow` stays in this file

**Files moved:**
- `lib/features/teams/teams_page.dart` (moved from `lib/pages/teams_page.dart`)
- `lib/features/teams/team_detail_page.dart` (moved from `lib/pages/team_detail_page.dart`)
- `lib/features/teams/team_form_sheet.dart` (moved from `lib/pages/team_form_sheet.dart`)
- `lib/features/teams/roster/player_form_sheet.dart` (moved from `lib/pages/player_form_sheet.dart`)
- `lib/features/teams/matches/team_match_form_sheet.dart` (moved from `lib/pages/team_match_form_sheet.dart`)

**Files modified:**
- `lib/features/teams/team_detail_page.dart` — after extraction, becomes a thin tab host importing `RosterTab`, `StatsTab`, `TeamMatchesTab`; private shell helpers (`_TeamHeader`, `_AddFab`) remain; target line count under 250
- `lib/features/discovery/debug_page.dart` — updates its reference from the private `_MatchesTab` to the now-public `TeamMatchesTab` imported from `features/teams/matches/team_matches_tab.dart`
- `lib/core/shell/app_shell.dart` — import update for teams page paths
- All test files referencing teams pages (import updates)

**Approach:** Extract each tab widget by creating its target file with the class content from `team_detail_page.dart`, updating the class visibility (remove `_` prefix), and updating the class's outbound imports to relative paths from its new location. Then update `team_detail_page.dart` to import and use the three new public classes, removing the now-extracted private classes from its body. Apply the per-file move protocol for the moved pages.

**Test scenarios:**
- `team_detail_page.dart` is under 250 lines after extraction
- `flutter analyze` passes — `debug_page.dart`'s reference to `TeamMatchesTab` resolves correctly
- `test/db/teams_dao_test.dart` passes with updated imports
- Any existing widget tests covering teams pages pass
- `just test` fully green

**Verification:** `lib/pages/teams_page.dart`, `lib/pages/team_detail_page.dart`, `lib/pages/player_form_sheet.dart`, `lib/pages/team_form_sheet.dart`, `lib/pages/team_match_form_sheet.dart` no longer exist; `team_detail_page.dart` is under 250 lines.

---

### U10. Restructure video feature — move pages and extract DownloadSheet

**Goal:** Move video pages into `lib/features/video/`, create the `playback/` sub-folder, and extract `_DownloadSheet` from `video_match_detail_page.dart`.

**Requirements:** R6, R8.1, R9.1, R10

**Dependencies:** U6 (`video_state.dart` already at `lib/features/video/`)

**Files created:**
- `lib/features/video/playback/download_sheet.dart` — extracted from `video_match_detail_page.dart`; `_DownloadSheet` → `DownloadSheet` (public, 345 lines, complex stateful widget)

**Files moved:**
- `lib/features/video/video_page.dart` (moved from `lib/pages/video_page.dart`)
- `lib/features/video/video_team_matches_page.dart` (moved from `lib/pages/video_team_matches_page.dart`)
- `lib/features/video/playback/video_match_detail_page.dart` (moved from `lib/pages/video_match_detail_page.dart`)

**Files modified:**
- `lib/features/video/playback/video_match_detail_page.dart` — after `_DownloadSheet` is extracted, imports `DownloadSheet` from the sibling `download_sheet.dart`; remaining private helpers (`_Player`, `_Scrubber`, `_OverlayToggleRow`, `_EventsHeader`, `_EventRow`, `_Footer`, `_Opt`, `_Radio`) stay in this file
- `lib/core/shell/app_shell.dart` — import update for video page paths
- All test files referencing video pages (import updates)

**Approach:** Extract `_DownloadSheet` by creating `download_sheet.dart` with the class content, making it public (`DownloadSheet`), and updating its outbound imports. Then update `video_match_detail_page.dart` to import `DownloadSheet` from its sibling and remove the extracted class. Apply the per-file move protocol for the remaining pages.

**Test scenarios:**
- `flutter analyze` passes
- `just test` fully green (video page tests pass with updated imports)

**Verification:** `lib/pages/video_*.dart` files no longer exist; `lib/features/video/playback/download_sheet.dart` exists as a standalone file.

---

### U11. Restructure match feature — move pages and extract screens

**Goal:** Move and split `match_page.dart` into a thin router plus four extracted screen/sheet files. Create the `session/` sub-folder. `match_page.dart` becomes under 150 lines.

**Requirements:** R3, R4, R9.1, R10

**Dependencies:** U6 (`match_state.dart` and `session/session_state.dart` already at their target paths)

**Files created:**
- `lib/features/match/landing_screen.dart` — extracted from `match_page.dart`; `_LandingScreen` → `LandingScreen` (public); private helpers (`_MatchSearchField`, `_MatchSportFilterChips`, `_MatchTeamFilterChips`, `_AvatarCircle`, `_UpcomingRow`, `_NoUpcomingState`) stay in this file
- `lib/features/match/setup_screen.dart` — extracted from `match_page.dart`; `_SetupScreen` → `SetupScreen` (public); `_ValueRow`, `_DropdownRow`, `_CustomFormatDialog` stay in this file
- `lib/features/match/session/session_screen.dart` — extracted from `match_page.dart`; `_SessionScreen` → `SessionScreen` (public); `_PrimaryActionRow`, `_EndedBanner`, `_BottomControls`, `_TopBar`, `_LiveThumb`, `_ScoreBlock`, `_EventLogRow`, `_ControlGroup`, `_Dot`, `_Square`, `_PauseGlyph`, `_PlayGlyph`, `_PlayPainter` stay in this file
- `lib/features/match/session/event_sheet.dart` — extracted from `match_page.dart`; `_EventSheet` → `EventSheet` (public); `_StepHeader`, `_NumberPad`, `_ToggleRow`, `_RowItem` stay in this file

**Files moved:**
- `lib/features/match/match_page.dart` (moved from `lib/pages/match_page.dart` and thinned to router only)

**Files modified:**
- `lib/features/match/match_page.dart` — after all extractions, contains only the `MatchPage` router widget routing between `LandingScreen`, `SetupScreen`, and `SessionScreen` based on state; target line count under 150
- `lib/core/shell/app_shell.dart` — import update for match page path
- All test files referencing match pages or event sheet (import updates)

**Approach:** Create each screen file with its content extracted from `match_page.dart`. Classes that are private helpers of a given screen move with it (they stay private `_` within the new file). After all four screen files exist, rewrite `match_page.dart` to contain only the `MatchPage` widget and its routing logic, importing the four screen files. Apply the per-file move protocol.

**Test scenarios:**
- `match_page.dart` is under 150 lines after extraction
- `flutter analyze` passes
- `test/pages/match_page_test.dart` passes with updated imports
- `test/pages/match_event_sheet_test.dart` passes with updated imports (now imports from `session/event_sheet.dart`)
- `test/pages/match_landing_filter_test.dart` passes with updated imports (now imports from `landing_screen.dart`)
- `just test` fully green

**Verification:** `lib/pages/match_page.dart` no longer exists; `lib/features/match/match_page.dart` is under 150 lines; all four screen files exist.

---

### U12. Restructure test/ to mirror lib/

**Goal:** Move all test files into a directory structure that mirrors `lib/` — `test/features/`, `test/core/`, `test/mock/` — so a test file's location directly implies what it covers. Update all package imports within moved test files.

**Requirements:** R13, R10.2

**Dependencies:** U7, U8, U9, U10, U11 (all lib/ restructuring complete; test files can now import from their final lib/ paths)

**Files moved (complete mapping):**

*Features:*
- `test/pages/match_page_test.dart` → `test/features/match/match_page_test.dart`
- `test/pages/match_landing_filter_test.dart` → `test/features/match/match_landing_filter_test.dart`
- `test/pages/match_event_sheet_test.dart` → `test/features/match/session/event_sheet_test.dart`
- `test/pages/settings_page_shell_test.dart` → `test/features/settings/settings_page_shell_test.dart`
- `test/pages/settings_camera_section_test.dart` → `test/features/settings/settings_camera_section_test.dart`
- `test/pages/settings_backup_restore_test.dart` → `test/features/settings/data/settings_backup_restore_test.dart`
- `test/pages/settings_user_section_test.dart` → `test/features/settings/users/settings_user_section_test.dart`
- `test/pages/user_form_sheet_test.dart` → `test/features/settings/users/user_form_sheet_test.dart`
- `test/pages/settings_streaming_section_test.dart` → `test/features/settings/streaming/settings_streaming_section_test.dart`
- `test/pages/streaming_destination_form_sheet_test.dart` → `test/features/settings/streaming/streaming_destination_form_sheet_test.dart`
- `test/pages/sport_presets_built_in_test.dart` → `test/features/settings/sport_presets/sport_presets_built_in_test.dart`
- `test/state/active_user_providers_test.dart` → `test/features/settings/users/active_user_providers_test.dart`
- `test/state/app_data_filter_test.dart` → rename and move to the feature state file(s) it tests (e.g., `test/features/match/match_state_filter_test.dart` or split across relevant feature test folders)

*Core:*
- `test/app_shell_test.dart` → `test/core/shell/app_shell_test.dart`
- `test/ble/mock_ble_service_test.dart` → `test/mock/mock_ble_service_test.dart`
- `test/db/mock_data_seeder_test.dart` → `test/mock/mock_data_seeder_test.dart`
- `test/db/sport_presets_dao_test.dart` → `test/core/db/sport_presets_dao_test.dart`
- `test/db/streaming_destinations_dao_test.dart` → `test/core/db/streaming_destinations_dao_test.dart`
- `test/db/teams_dao_test.dart` → `test/core/db/teams_dao_test.dart`
- `test/db/users_dao_test.dart` → `test/core/db/users_dao_test.dart`
- `test/models/streaming_test.dart` → `test/core/models/streaming_test.dart`
- `test/models/user_test.dart` → `test/core/models/user_test.dart`
- `test/services/backup_service_test.dart` → `test/core/services/backup_service_test.dart`
- `test/services/clip_service_test.dart` → `test/core/services/clip_service_test.dart`
- `test/state/last_camera_test.dart` → `test/core/state/last_camera_test.dart`
- `test/widgets/live_preview_view_test.dart` → `test/core/widgets/live_preview_view_test.dart`

*Stays at test/ root:*
- `test/test_helpers.dart` — shared helpers used across all tests, stays at root
- `test/widget_test.dart` — top-level smoke test, stays at root

*Stays in test/integration/:*
- `test/integration/main_page_test.dart`
- `test/integration/settings_page_test.dart`

**Approach:** Move each test file to its target path and update all `package:sst_cam_app/` imports to reflect the new lib/ paths established in U2–U11. The `app_data_filter_test.dart` file requires a rename decision at implementation time — read its contents and move it to the folder matching the state file it primarily tests; if it spans multiple state files, split it.

**Test scenarios:**
- `just test` passes after all test files are moved and imports updated
- No `test/pages/`, `test/state/`, `test/ble/`, `test/db/`, `test/models/`, `test/services/`, `test/widgets/` directories remain
- `test/features/match/session/event_sheet_test.dart` exists and passes

**Verification:** `ls test/pages test/state test/ble test/db test/models test/services test/widgets` all return "No such file or directory"; `just test` green.

---

### U13. Final cleanup and verification

**Goal:** Delete all remaining old top-level directories in lib/, confirm the lib/ root contains only two files, and run the full verification suite against all success criteria.

**Requirements:** R1–R14 (all success criteria)

**Dependencies:** U12

**Files:**
- `lib/pages/` — delete if empty (should be empty after U7–U11)
- Any remaining empty old directories under `lib/`

**Approach:** Verify that `lib/pages/` is empty and delete it. Confirm `lib/` root contains only `main.dart` and `app.dart`. Run the full analysis and test suite. Confirm each success criterion from the requirements document.

**Test scenarios:**
- `lib/` root contains exactly `main.dart` and `app.dart`
- `match_page.dart` is under 150 lines
- `team_detail_page.dart` is under 250 lines
- `grep -r "app_data" lib/` returns zero results
- `grep -r "lib/pages/" lib/` returns zero results
- `grep -r "test/pages/" test/` returns zero results
- All mock files exist only under `lib/mock/`
- No `test/pages/` or `test/state/` directories remain
- `flutter analyze` reports zero errors
- `just test` is fully green
- `just ci` passes (format-check + analyze + test)

**Verification:** All success criteria from the origin document confirmed green.

---

## Deferred Implementation Notes

- **`part of` path update in `.g.dart` files:** The `part of 'filename.dart'` directives in generated files may use the filename only (not full path), in which case they need no update. If they use full relative paths, update them in U3. If `just gen-db` after U3 regenerates them incorrectly, re-run codegen and commit the regenerated output.
- **`proto/` directory:** The `lib/models/proto/` directory is gitignored. Move the directory structure in U2 but do not commit generated contents. After the move, `just gen-proto` will regenerate them at `lib/core/models/proto/`.
- **Provider rename decisions:** If any provider name is ambiguous after the split (e.g., a provider named `usersProvider` that lives in three different files is now clearly in `users_state.dart`), rename during U6. This is a judgment call for the implementer based on what is actually confusing at implementation time.
- **`main_page.dart`:** `lib/pages/main_page.dart` was not mentioned in the target structure. Verify during implementation whether it is still used or has been superseded. If used, it moves to its feature folder; if unused, delete it.

---

## System-Wide Impact

| Surface | Impact |
|---|---|
| Every `lib/` file | Import paths change; no logic changes |
| Every `test/` file | Files move to mirror `lib/` layout AND package import paths update |
| `app_shell.dart` | References all five tab page classes — updated in each feature unit |
| `app.dart` | Imports `app_shell.dart` and `app_config.dart` — updated in U5 |
| `main.dart` | Imports `env.dart` and mock files — updated in U4/U5 |
| `debug_page.dart` | Cross-boundary access to `_MatchesTab` — fixed to `TeamMatchesTab` in U9 |
| Generated `.g.dart` files | Move with parents in U3; `just gen-db` verifies correctness |
| CI (`just ci`) | No workflow changes; the same `format-check + analyze + test` commands apply |
