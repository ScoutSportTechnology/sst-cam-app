---
date: 2026-05-21
topic: file-structure-restructure
tags: [architecture, refactor, file-layout, features, conventions]
---

# File Structure Restructure

## Summary

Reorganise `lib/` from a type-based flat layout into a feature-based layout with sub-feature depth where warranted. Five top-level feature folders under `lib/features/`; shared infrastructure under `lib/core/`; all dev-time mock implementations under `lib/mock/`. Features with distinct parallel concerns (`teams`, `video`, `settings`) get sub-feature sub-folders. `match` is partially split: landing and setup are screens of the match flow and stay flat; the live session is a sub-feature with its own folder and state. Consolidate app-level entry files: only `main.dart` and `app.dart` remain at `lib/` root; `app_shell.dart` moves to `core/shell/`; `app_config.dart` and `env.dart` move to `core/config/`. Split `match_page.dart` (2 763 lines) and `app_data.dart` (1 351 lines) by extracting screens, sheets, and controllers into their correct locations. Establish a repeatable rule for when a widget earns its own file and when a sub-folder is warranted.

---

## Problem Frame

Three overlapping pains make the codebase hard to review and hard to navigate:

1. **File length.** `match_page.dart` is 2 763 lines and contains 40+ private classes — scrolling past unrelated classes to reach the one being changed is slow, and PR diffs for even small changes are enormous. `app_data.dart` (1 351 lines) mixes four unrelated controllers in one file.

2. **No predictable location.** Form sheets (`player_form_sheet.dart`) live next to full pages (`teams_page.dart`) in a flat `pages/` directory with no grouping. There is no convention for whether a widget lives in the page file or has been extracted, or which folder owns which concern.

3. **State and UI tangled across top-level folders.** The current `state/` folder has a mix of BLE providers, DB providers, and multiple domain controllers with no clear ownership.

---

## Target Structure

```
lib/
  main.dart                            # entry point only
  app.dart                             # root widget + theme
  features/
    match/
      match_page.dart                  # thin router (Landing/Setup → Session)
      landing_screen.dart              # was _LandingScreen — pick upcoming match
      setup_screen.dart                # was _SetupScreen — configure match settings
      match_state.dart                 # UpcomingMatch, top-level match providers
      session/
        session_screen.dart            # was _SessionScreen — live scoring
        event_sheet.dart               # was _EventSheet — event logging
        session_state.dart             # LiveMatchController, LiveMatchState, LiveEvent
    teams/
      teams_page.dart                  # teams list
      team_detail_page.dart            # thin tab host (imports the three tab widgets)
      team_form_sheet.dart
      teams_state.dart                 # TeamsController
      roster/
        roster_tab.dart                # was _RosterTab in team_detail_page.dart
        player_form_sheet.dart
      stats/
        stats_tab.dart                 # was _StatsTab in team_detail_page.dart
      matches/
        team_matches_tab.dart          # was _MatchesTab in team_detail_page.dart
        team_match_form_sheet.dart
    video/
      video_page.dart                  # library list
      video_team_matches_page.dart
      video_state.dart                 # LibraryEvent, LibraryMatch, video providers
      playback/
        video_match_detail_page.dart   # video player + events
        download_sheet.dart            # was _DownloadSheet (345 lines, complex stateful)
    settings/
      settings_page.dart               # main hub — nav rows to sub-feature pages
      users/
        users_settings_page.dart
        user_form_sheet.dart
        users_state.dart               # UsersController
      sport_presets/
        sport_presets_page.dart
        sport_preset_form_sheet.dart
        sport_presets_state.dart       # SportPresetsController
      streaming/
        streaming_destinations_page.dart
        streaming_destination_form_sheet.dart
        streaming_state.dart           # StreamingDestinationsController
      data/
        data_settings_page.dart
    discovery/
      discovery_page.dart
      debug_page.dart
      diagnostics_page.dart
  core/
    config/
      app_config.dart                  # was lib/app_config.dart
      env.dart                         # was lib/env.dart
    shell/
      app_shell.dart                   # was lib/app_shell.dart — 5-tab navigation shell
    ble/
      ble_service.dart
      ble_service_impl.dart
      ble_providers.dart               # was lib/state/ble_providers.dart
    db/
      app_database.dart
      app_database.g.dart
      tables/
      daos/
    wifi/
      wifi_service.dart
      wifi_service_impl.dart
      wifi_providers.dart              # was lib/state/wifi_providers.dart
      wifi_handoff.dart                # was lib/state/wifi_handoff.dart
    services/
      backup_service.dart
      clip_service.dart
      video_path_service.dart
    state/
      last_camera.dart                 # cross-feature shared state
      db_providers.dart                # was lib/state/db_providers.dart
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
      proto/                           # (gitignored, generated by just gen-proto)
    widgets/
      indicators.dart
      live_preview_view.dart
      wf_button.dart
      wf_card.dart
      wf_chip.dart
    theme/
      tokens.dart
  mock/
    mock_ble_service.dart              # was lib/ble/mock_ble_service.dart
    mock_wifi_service.dart             # was lib/wifi/mock_wifi_service.dart
    mock_data_seeder.dart              # was lib/db/mock_data_seeder.dart
```

---

## Sub-feature and placement rationale

| Concern | Location | Reason |
|---|---|---|
| `main.dart`, `app.dart` | `lib/` root | True entry-point files. Everything else is an implementation detail below them. |
| `app_shell.dart` | `core/shell/` | Navigation scaffolding — it is app infrastructure, not a user-facing feature. |
| `app_config.dart`, `env.dart` | `core/config/` | Configuration and environment selection are core concerns shared by all layers. |
| Mock implementations | `lib/mock/` | All dev-time fakes grouped together. Signals clearly that they are a parallel dev-time system, not part of real feature or core logic. |
| `match` | Partial — `session/` only | Landing and setup are sequential screens of the same flow. Session is a standalone concern (its own controller and state machine) that the match flow launches. |
| `teams` | `roster/`, `stats/`, `matches/` | Three parallel concerns each with their own forms. A developer working on roster never needs to open the stats or matches files. |
| `video` | `playback/` | Playback (video player + download sheet) is a distinct sub-experience from the library list. Future sub-features (live preview, event cropping) slot in cleanly alongside it. |
| `settings` | `users/`, `sport_presets/`, `streaming/`, `data/` | Each section has its own page, form sheet, and controller. Flat would put 8+ files in one folder with no grouping. |
| `discovery` | No sub-folders | Three small files, no parallel sub-concerns. |

---

## Requirements

### R1 — Feature folders

- R1.1. Create `lib/features/` with five sub-folders: `match`, `teams`, `video`, `settings`, `discovery`.
- R1.2. Every file that is exclusively used by one tab moves into that tab's feature folder (or sub-feature folder).
- R1.3. Cross-feature imports are allowed — a file in `features/match/` may import from `features/teams/` when it needs `TeamsController`. No barrel files or re-exports required.

### R2 — Core folder

- R2.1. Create `lib/core/` with sub-folders: `config`, `shell`, `ble`, `db`, `wifi`, `services`, `state`, `models`, `widgets`, `theme`.
- R2.2. All existing `lib/ble/`, `lib/db/`, `lib/wifi/`, `lib/services/`, `lib/models/`, `lib/theme/`, and `lib/widgets/` contents move into their `lib/core/` counterparts with the same internal structure preserved. Mock files are excluded — they move to `lib/mock/` instead (see R12).
- R2.3. Provider files currently in `lib/state/` move to their domain folder inside `lib/core/`: `ble_providers.dart` → `core/ble/`, `db_providers.dart` → `core/state/`, `wifi_providers.dart` and `wifi_handoff.dart` → `core/wifi/`.
- R2.4. `last_camera.dart` moves to `lib/core/state/`.
- R2.5. `app_config.dart` and `env.dart` move to `lib/core/config/`.
- R2.6. `app_shell.dart` moves to `lib/core/shell/`.
- R2.7. After all moves, `lib/state/` is deleted. `lib/app_config.dart`, `lib/env.dart`, and `lib/app_shell.dart` at the old root paths are deleted.

### R3 — match: screen extraction and session sub-feature

- R3.1. Extract `_LandingScreen` → `features/match/landing_screen.dart` as `LandingScreen`.
- R3.2. Extract `_SetupScreen` → `features/match/setup_screen.dart` as `SetupScreen`. `_CustomFormatDialog` stays in this file as `_CustomFormatDialog` (only used by `SetupScreen`).
- R3.3. Create `features/match/session/` sub-folder.
- R3.4. Extract `_SessionScreen` → `features/match/session/session_screen.dart` as `SessionScreen`.
- R3.5. Extract `_EventSheet` → `features/match/session/event_sheet.dart` as `EventSheet`.
- R3.6. `match_page.dart` becomes a thin router whose only job is importing the screen files and routing between them based on state. It must not contain business logic or significant widgets.
- R3.7. Private helper classes that belong to one screen (`_ScoreBlock`, `_TopBar`, `_ControlGroup`, `_Dot`, `_Square`, `_PauseGlyph`, `_PlayGlyph`, `_PlayPainter`, `_StepHeader`, `_NumberPad`, `_ToggleRow`, `_RowItem`, etc.) stay in their parent screen file.

### R4 — match: state split

- R4.1. `UpcomingMatch` and any providers used by landing/setup screens move to `features/match/match_state.dart`.
- R4.2. `LiveMatchController`, `LiveMatchState`, `LiveEvent` move to `features/match/session/session_state.dart`.

### R5 — teams: sub-feature extraction

- R5.1. Create `features/teams/roster/`, `features/teams/stats/`, `features/teams/matches/` sub-folders.
- R5.2. Extract `_RosterTab` from `team_detail_page.dart` → `features/teams/roster/roster_tab.dart` as `RosterTab`.
- R5.3. Move `player_form_sheet.dart` → `features/teams/roster/player_form_sheet.dart`.
- R5.4. Extract `_StatsTab` from `team_detail_page.dart` → `features/teams/stats/stats_tab.dart` as `StatsTab`. Private helpers (`_LeaderboardTable`, etc.) stay in this file.
- R5.5. Extract `_MatchesTab` from `team_detail_page.dart` → `features/teams/matches/team_matches_tab.dart` as `TeamMatchesTab`. Private helpers (`_MatchRow`, etc.) stay in this file.
- R5.6. Move `team_match_form_sheet.dart` → `features/teams/matches/team_match_form_sheet.dart`.
- R5.7. `team_detail_page.dart` becomes a thin tab host that imports `RosterTab`, `StatsTab`, and `TeamMatchesTab`. Private helpers that belong to the page shell (`_TeamHeader`, `_AddFab`) stay in this file.
- R5.8. `teams_state.dart` stays at `features/teams/` level — `TeamsController` is used by both `teams_page.dart` and `features/match/` (for team selection), so it lives at the feature root, not inside a sub-feature.

### R6 — video: playback sub-feature

- R6.1. Create `features/video/playback/` sub-folder.
- R6.2. Move `video_match_detail_page.dart` → `features/video/playback/video_match_detail_page.dart`.
- R6.3. Extract `_DownloadSheet` from `video_match_detail_page.dart` → `features/video/playback/download_sheet.dart` as `DownloadSheet`.
- R6.4. Remaining private helpers in `video_match_detail_page.dart` (`_Player`, `_Scrubber`, `_OverlayToggleRow`, `_EventsHeader`, `_EventRow`, `_Footer`, `_Opt`, `_Radio`) stay in that file.
- R6.5. `video_page.dart`, `video_team_matches_page.dart`, and `video_state.dart` stay at `features/video/` level.

### R7 — settings: sub-feature folders

- R7.1. Create `features/settings/users/`, `features/settings/sport_presets/`, `features/settings/streaming/`, `features/settings/data/` sub-folders.
- R7.2. Move `users_settings_page.dart` and `user_form_sheet.dart` → `features/settings/users/`.
- R7.3. Extract `UsersController` and `UsersControllerException` from `app_data.dart` → `features/settings/users/users_state.dart`.
- R7.4. Move `sport_presets_page.dart` and `sport_preset_form_sheet.dart` → `features/settings/sport_presets/`.
- R7.5. Extract `SportPresetsController` and `SportPresetsControllerException` from `app_data.dart` → `features/settings/sport_presets/sport_presets_state.dart`.
- R7.6. Move `streaming_destinations_page.dart` and `streaming_destination_form_sheet.dart` → `features/settings/streaming/`.
- R7.7. Extract `StreamingDestinationsController` from `app_data.dart` → `features/settings/streaming/streaming_state.dart`.
- R7.8. Move `data_settings_page.dart` → `features/settings/data/`.
- R7.9. `settings_page.dart` stays at `features/settings/` level — it is the hub that navigates to each sub-feature.

### R8 — app_data.dart deletion

- R8.1. Extract `LibraryEvent`, `LibraryMatch`, and any video-related providers → `features/video/video_state.dart`.
- R8.2. After all extractions (R4, R5.8, R7.3, R7.5, R7.7, R8.1), `lib/state/app_data.dart` must be empty and is deleted.

### R9 — Naming

- R9.1. When a private `_Widget` class moves to its own file, remove the leading underscore. Examples: `_LandingScreen` → `LandingScreen`, `_EventSheet` → `EventSheet`, `_RosterTab` → `RosterTab`, `_DownloadSheet` → `DownloadSheet`.
- R9.2. Public class names may be updated if the current name no longer fits after the move. Renaming must be confined to the restructure.
- R9.3. Provider names may be updated if the current name is ambiguous after the split, but provider wiring and relationships must remain unchanged.

### R10 — Import updates

- R10.1. All imports across the codebase update to reflect new paths. No old paths are preserved via re-exports or barrel files.
- R10.2. `test/` files move to mirror the new `lib/` layout AND update their `package:sst_cam_app/` imports to reflect new paths.

### R11 — Split rules (convention for future work)

- R11.1. **File split rule.** A widget earns its own file when it is a distinct screen or sheet — a view the user navigates to or opens and dismisses independently. Building blocks (small helpers tightly coupled to one screen) stay in their parent file.
- R11.2. **Sub-feature folder rule.** A sub-folder is warranted when: (a) there are 2+ files that belong together as a parallel concern within the feature, and (b) a developer working on that concern would not normally need to open the other sub-folders. A linear flow (step A → step B) does not warrant a sub-folder per step.
- R11.3. **State placement.** State that belongs to a sub-feature lives in that sub-folder (`session/session_state.dart`). State used by multiple sub-folders or by other features lives at the feature root (`teams/teams_state.dart`).
- R11.4. **Shared widgets.** Widgets used by 2+ features go in `lib/core/widgets/`. Widgets used only within one feature stay in that feature folder.

### R12 — Mock folder

- R12.1. Create `lib/mock/` as a top-level sibling of `lib/features/` and `lib/core/`.
- R12.2. Move `lib/ble/mock_ble_service.dart` → `lib/mock/mock_ble_service.dart`.
- R12.3. Move `lib/wifi/mock_wifi_service.dart` → `lib/mock/mock_wifi_service.dart`.
- R12.4. Move `lib/db/mock_data_seeder.dart` → `lib/mock/mock_data_seeder.dart`.
- R12.5. All three files retain their class names and interfaces unchanged. Only the file path changes.
- R12.6. Any file that imports a mock (e.g., `app_config.dart` selecting `MockBleService` at runtime) updates its import path to point to `lib/mock/`.

### R13 — Test directory restructure

The `test/` directory mirrors the `lib/` layout so a test file's location directly implies what it tests.

- R13.1. Move `test/pages/*` tests into `test/features/<feature>/[sub-feature]/` matching the destination of the lib file under test.
- R13.2. Move `test/state/*` tests into `test/features/<feature>/[sub-feature]/` or `test/core/state/` matching where the state now lives.
- R13.3. Move `test/ble/`, `test/db/`, `test/models/`, `test/services/`, `test/widgets/` into `test/core/<domain>/` matching the `lib/core/` layout.
- R13.4. Move `test/ble/mock_ble_service_test.dart` and `test/db/mock_data_seeder_test.dart` → `test/mock/` matching `lib/mock/`.
- R13.5. `test/integration/` keeps its flat structure — integration tests cross features and do not belong to any single feature folder.
- R13.6. `test/test_helpers.dart` and `test/widget_test.dart` stay at `test/` root.
- R13.7. `test/app_shell_test.dart` → `test/core/shell/app_shell_test.dart`.
- R13.8. `test/state/app_data_filter_test.dart` is renamed and moved to reflect the specific state file(s) it now tests after `app_data.dart` is split.

### R14 — Out of scope

- R14.1. No changes to provider logic, data flow, or feature behaviour.
- R14.2. No introduction of barrel (`index.dart`) files.
- R14.3. No changes to `proto/`, `assets/`, `justfile`, or `pubspec.yaml`.
- R14.4. No changes to CI workflow files.

---

## Success Criteria

- `lib/` root contains exactly two files: `main.dart` and `app.dart`.
- `match_page.dart` is under 150 lines and contains only routing logic.
- `team_detail_page.dart` is a thin tab host — under 250 lines — that contains no tab content.
- `app_data.dart` is deleted.
- All mock implementations live in `lib/mock/` — none remain in `core/ble/`, `core/db/`, or `core/wifi/`.
- No `lib/pages/`, `lib/state/`, `lib/ble/`, `lib/wifi/`, `lib/services/`, `lib/models/`, `lib/widgets/`, `lib/theme/` top-level directories remain.
- `flutter analyze` passes with zero new errors.
- `just test` passes unchanged.
- `test/` directory structure mirrors `lib/` — a test file's folder path implies the feature or core domain it covers.
- No `test/pages/` or `test/state/` directories remain.
- Any new file added to the project (lib/ or test/) has exactly one obvious home — no ambiguity about which folder it belongs to.
