# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Flutter companion app for the SST Cam — open-source sports camera on NVIDIA Jetson.
Controls firmware over BLE (command/control) and WiFi Direct (live preview + downloads).
Built **contract-first** against a test-double BLE/WiFi layer — the whole app runs
and is tested without hardware.

## Commands

```bash
just get              # flutter pub get
just run              # dev build (mock backend, main.dart)
just test             # unit + widget tests
just test-integration # integration tests (needs device/emulator)
just test-all         # test + test-integration
just analyze          # flutter analyze
just format           # dart format
just format-check     # CI format check (exits non-zero on diff)
just gen-proto        # regenerate lib/models/proto/ from proto/*.proto (devcontainer)
just gen-db           # regenerate Drift *.g.dart from tables/daos (devcontainer)
just build-android    # debug APK (mock)        build-android-prod → real backend
just ci               # format-check + analyze + test (mirrors CI)
```

## Dev container

Open in VS Code → "Reopen in Container". Docker Compose
(`.devcontainer/docker-compose.yml`), two services:

- **app** — Flutter SDK, Android SDK, `protoc`, Dart protoc plugin, Node.js 22, Claude Code.
  All `just` commands run inside this container.
- **mock-camera-wifi** — RTSP H.264 preview on `:8554` (mediamtx + ffmpeg loop) and
  HTTP recording download on `:8080` (Bearer auth + Range). Simulates the camera's
  WiFi Direct data plane for dev without real hardware.

**iOS builds require macOS + Xcode.** The devcontainer is Linux-only.

## Entry points & backends

- `lib/main.dart` — **dev** entry: builds a `ProviderContainer` that **overrides**
  `bleServiceProvider`/`wifiServiceProvider` with mocks (+ seedable dev data, dev
  navigation), then runs an `UncontrolledProviderScope`.
- `lib/main_prod.dart` — **prod** entry: a bare `ProviderContainer` with **no
  overrides**, so the providers' defaults (the real `BleServiceImpl`/
  `WifiServiceImpl`) are used.
- `lib/core/config/env.dart` / `app_config.dart` — `kAppEnv.isDevBackend` gates
  dev-only diagnostics/seeding, **not** backend selection. Backend = provider
  default (real) vs. dev-entry Riverpod override (mock); there is no runtime
  `isDevBackend` service branch. Audit prod paths for any lingering `isDevBackend ||`
  bypass.

## Architecture — contract-first, pull model, feature-first

### Communication model

**The app always initiates.** The firmware never pushes unsolicited data.
Every exchange is: app sends `Command` → firmware sends `CommandResponse`,
matched by `correlation_id`. Telemetry / match state are polled on timers.
Large payloads use the `ChunkedPayload` envelope with symmetric `ChunkAck`
flow control. See `proto/README.md` and `proto/overlay-rendering.md`.

### Layering

```text
lib/
  main.dart / main_prod.dart   dev vs prod entry; app.dart = MaterialApp + theme
  core/                        cross-feature infrastructure
    ble/      BleService (port) + ble_service_impl (flutter_blue_plus) + ble_protocol + ble_providers
    wifi/     WifiService (port) + impl + wifi_p2p_channel + wifi_handoff + wifi_providers
    db/       Drift AppDatabase; tables/ (clips, teams, users, sport_presets,
              streaming_destinations, team_matches, thumbnails) + daos/ (+ generated *.g.dart)
    models/   Plain Dart view models — app compiles without generated protos:
              command, device, telemetry, wifi, match, recording, overlay,
              overlay_layout, team, user, sport_preset, streaming
    services/ backup_service, clip_service, gallery_service, video_path_service
    state/    db_providers, last_camera (cross-feature Riverpod providers)
    config/   env, app_config, dev_config, dev_navigation, dev_reseeder
    shell/    app_shell — tabbed NavigationBar shell
    theme/    tokens — colors/spacing tokens (app.dart wires them into ThemeData)
    widgets/  shared widgets (wf_button/card/chip, wf_filter_bar, indicators, live_preview_view)
  features/                    one folder per user-facing feature; *_state.dart = its Riverpod
    camera/    main_page, camera_state
    discovery/ discovery_page, diagnostics_page, debug_page
    match/     landing/setup/match_page + session/ (session_screen, session_state,
               event_sheet, overlay_renderer)
    teams/     teams_page, team_detail_page, roster/ matches/ stats/ + form sheets
    settings/  settings_page + sport_presets/ streaming/ users/ data/ developer/
    video/     video_page, video_state, overlay_helper, playback/ (detail, download_sheet)
  mock/                        test doubles for the dev backend
    emulator/  mock_ble_service, mock_wifi_service (+ fixtures) — emulated firmware
    internal/  mock_data_service (+ fixtures) — seed app data
    mock_video_fetcher
  models/proto/                (gitignored) generated bindings; only *_impl uses them
test/                          mirrors lib/ (core/, features/, mock/, integration/, wifi/)
```

A **feature** owns its UI + `*_state.dart` (Riverpod). Anything two features
share moves to `core/`. New cross-feature provider → `core/state/`.

### Ports & mocks

`BleService` and `WifiService` are abstract ports — the only BLE/WiFi surface the
UI touches. `*_impl` wire the real packages and are the **provider defaults**; the
`mock/emulator/` doubles back the dev backend via the **`main.dart` Riverpod
override** (and tests override the same way with `ProviderScope(overrides: [...])`).
`main_prod.dart` adds no overrides, so prod gets the real impls.

### Proto vs. Dart models

- `proto/*.proto` — wire format; source of truth (shared submodule).
- `lib/core/models/*.dart` — plain Dart view models; the whole app uses these.
- `lib/models/proto/` — gitignored generated bindings; only `BleServiceImpl` touches them.

The app compiles and runs from plain Dart models. `just gen-proto` regenerates the
bindings for use inside `BleServiceImpl`.

### Database

Drift over SQLite. Tables in `core/db/tables/`, DAOs in `core/db/daos/`, both with
generated `*.g.dart` (`just gen-db`). `BackupService` exports/imports the full DB as JSON.

### Theme

Dark by default. Tokens live in `lib/core/theme/tokens.dart`; `lib/app.dart` builds
`ThemeData` from them. Change a token, not a hardcoded color in a widget.

## CI/CD & releasing

PR-gated, Conventional-Commit driven. Two workflows:

- `.github/workflows/ci.yml` — **pull requests only**. Required status check on `main`: `Analyze & Test (Linux)` = `dart format` check → generate protos (pinned `protoc_plugin 21.1.2`) → `flutter analyze` → `flutter test`. Plus a non-required debug-APK smoke build.
- `.github/workflows/release.yml` — on **push to `main`** (a merge) + manual `workflow_dispatch`. Conventional-commit bump (`feat:` → minor, `fix:`/`perf:` → patch, `BREAKING`/`type!:` → major, docs/chore-only → **skip**) → tag `vX.Y.Z` + GitHub Release, then builds and uploads **two APKs**: production (`-t lib/main_prod.dart --dart-define=APP_ENV=prod`) and developer (`--dart-define=APP_ENV=stage`). Signing comes from `ANDROID_*` secrets when set, else falls back to debug signing. Default `GITHUB_TOKEN` only — no PAT/App.

### Branch + commit + tag rules
- `main` is protected: no direct push; PR + 1 approval + green `Analyze & Test` to merge.
- Tags `v*` are immutable semver (no delete/move/force-push).
- Use Conventional Commits. The **squash-merge subject** is what `release.yml` reads to choose the bump — a non-conventional subject cuts no release.

### Releasing
- Normal: merge a `feat:`/`fix:`/… PR → release auto-cuts on merge with both APKs.
- Manual: `gh workflow run release.yml -f bump=minor` (or `-f version=vX.Y.Z`).
- For release-signed (not debug) APKs, set repo secrets: `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`, `ANDROID_STORE_PASSWORD`.

## Documented solutions

`docs/solutions/` — solutions to past problems (architecture patterns, bugs,
conventions) with YAML frontmatter (`module`, `tags`, `problem_type`). Read the
relevant ones before implementing or debugging in a documented area (e.g. BLE
contract alignment). `docs/brainstorms/` and `docs/plans/` hold requirements and
implementation plans.

## Firmware spec

This repo also owns `docs/firmware-spec.md` — the implementation contract for the
firmware team (session lifecycle, required commands, overlay authoring, file
layout). Keep it in sync when the app's expectations of the firmware change.
