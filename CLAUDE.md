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

PR-gated, Conventional-Commit driven, on the SST branch model
`feat/* → develop → release/X.Y.Z → main` with a test-fidelity **maturity
ladder**:

- **alpha** (`vX.Y.Z-alpha.N`) — automated tests vs **mock + emulator**; minted on every `develop` merge.
- **beta** (`vX.Y.Z-beta.N`) — release candidate, manually validated vs **real firmware**; built on `release/*`.
- **stable** (`vX.Y.Z`) — shipped; the promoted beta artifact (same bytes), cut on merge to `main`.

Two non-negotiables: **build-in-PR / tag-on-merge**, and **`main` never builds**
(it only promotes an already-built beta APK).

Four workflows, trigger-separated:

- `.github/workflows/ci.yml` — **PRs into `develop` / `release/*`**. Required checks: `Analyze & Test (Linux)` (`dart format` → generate protos (pinned `protoc_plugin 21.1.2`) → `flutter analyze` → `flutter test`) and `Build Android APK`. The build is in the gate — this is what keeps `main` from ever needing to build.
- `.github/workflows/alpha.yml` — **push to `develop`** + `workflow_dispatch`. `resolve-version.sh alpha` (conventional-commit bump from the latest *stable* tag + `-alpha.(N+1)`; docs/chore-only → **skip**) → builds the **developer** APK (`--dart-define=APP_ENV=stage`) → publishes a `--prerelease` Release.
- `.github/workflows/release-beta.yml` — **push to `release/**`** + `workflow_dispatch`. Base = the branch name `X.Y.Z`; `resolve-version.sh beta X.Y.Z` → `-beta.(N+1)` → builds **both** APKs (production `-t lib/main_prod.dart --dart-define=APP_ENV=prod`, developer `--dart-define=APP_ENV=stage`) → publishes a `--prerelease` Release carrying both.
- `.github/workflows/promote.yml` — **push to `main`** + `workflow_dispatch`. Derives `X.Y.Z` from the merged `release/X.Y.Z` branch, picks the highest `vX.Y.Z-beta.N` tag (fail fast if none), tags `vX.Y.Z`, **downloads the beta APK assets and re-uploads them renamed** (bytes preserved). **No `flutter`/Gradle step exists** — the structural "main never builds" guarantee.

Version math lives in `scripts/ci/resolve-version.sh` (single source for all
three release workflows; `scripts/ci/resolve-version-test.sh` covers it).
Signing comes from `ANDROID_*` secrets when set, else falls back to debug
signing. Default `GITHUB_TOKEN` only — no PAT/App. Operational runbooks:
`docs/ci/rulesets.md` (branch/tag rulesets), `docs/ci/version-reset-runbook.md`.

### Branch + commit + tag rules
- `develop` is the default branch; target `feat/*` / `fix/*` PRs at it.
- `release/X.Y.Z` is cut from `develop` to stabilize a version; betas iterate on it.
- `main` is promote-only: no direct push; PR (from `release/*`) + 1 approval + green required checks. **No build runs on `main`.**
- Tags `v*` are immutable semver (`-alpha.N` < `-beta.N` < stable; no delete/move/force-push).
- Use Conventional Commits. The merged commit subjects since the last stable tag drive the alpha base bump (`feat:` → minor, `fix:`/`perf:` → patch, `BREAKING`/`type!:` → major, docs/chore-only → **skip**).

### Releasing
- Alpha: merge a `feat:`/`fix:`/… PR into `develop` → `alpha.yml` auto-tags `vX.Y.Z-alpha.N` + publishes the developer APK (docs/chore-only → no release).
- Beta: cut `release/X.Y.Z` from `develop` and push → `release-beta.yml` builds both APKs + tags `vX.Y.Z-beta.N`; push fixes to iterate `-beta.(N+1)`.
- Stable: after beta sign-off, PR `release/X.Y.Z → main` and merge → `promote.yml` tags `vX.Y.Z` and copies the beta APKs to the stable Release (no rebuild). Then delete the release branch and merge `main` back to `develop`.
- Manual: `gh workflow run alpha.yml -f version=v0.1.0` (seed) or `-f bump=minor`; `gh workflow run release-beta.yml`; `gh workflow run promote.yml -f version=X.Y.Z`.
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
