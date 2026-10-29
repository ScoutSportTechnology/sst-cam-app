# AGENTS.md

Guidance for coding agents (any harness) working in this repository.

## What this is

Flutter companion app for the SST Cam — open-source sports camera on NVIDIA Jetson.
Controls firmware over BLE (command/control) and WiFi Direct (live preview + downloads).
Built **contract-first** against a test-double BLE/WiFi layer — the whole app runs
and is tested without hardware.

## Commands

```bash
just get              # flutter pub get
just run              # dev build on a local device/emulator (mock backend)
just test             # unit + widget tests
just test-integration # integration tests (needs device/emulator)
just test-all         # test + test-integration
just analyze          # flutter analyze
just format           # dart format
just format-check     # CI format check (exits non-zero on diff)
just gen-proto        # regenerate lib/models/proto/ from proto/*.proto (devcontainer)
just gen-db           # regenerate Drift *.g.dart from tables/daos (devcontainer)
just gen-icons        # regenerate per-flavor launcher icons (dev/stage/prod)
just build-dev-app    # dev APK: debug + real backend (mock = EMULATE_CAMERA flag / in-app toggle)
just build-stage-app  # stage APK: release + real backend + dev tooling
just build-prod-app   # prod APK: release + real backend, tooling compiled out (shipped)
just deploy-dev-app ADDR   # build + install on phone (dev/stage/prod variants)
just deploy-stage-app ADDR # ADDR = adb serial (USB) or ip:port (wireless)
just deploy-prod-app ADDR
just iterate-app ADDR      # phone hot-reload loop (stage, real backend)
just ci               # format-check + analyze + test (mirrors CI)
```

## Dev container

Open in VS Code → "Reopen in Container". Docker Compose
(`.devcontainer/docker-compose.yml`), two services:

- **app** — Flutter SDK, Android SDK, `protoc`, Dart protoc plugin, Node.js 22.
  All `just` commands run inside this container.
- **mock-camera-wifi** — RTSP H.264 preview on `:8554` (mediamtx + ffmpeg loop) and
  HTTP recording download on `:8080` (Bearer auth + Range). Simulates the camera's
  WiFi Direct data plane for dev without real hardware.

**iOS builds require macOS + Xcode.** The devcontainer is Linux-only.

## Entry points & backends

**One entry (`lib/main.dart`), three env-mapped builds.** `main()` selects the
backend + tooling from the compile-time `kAppEnv` (`--dart-define=APP_ENV=…`) —
there is no second `main`:

| Build (`just`)                    | Mode    | Flavor  | `APP_ENV` | applicationId          | Backend            | Debuggable | Dev tooling |
|-----------------------------------|---------|---------|-----------|------------------------|--------------------|------------|-------------|
| `build-dev-app` / `deploy-dev-app`     | debug   | `dev`   | `dev`     | `com.sst.sstcam.dev`   | real (mock = flag) | yes        | yes         |
| `build-stage-app` / `deploy-stage-app` | release | `stage` | `stage`   | `com.sst.sstcam.stage` | real               | no         | yes         |
| `build-prod-app` / `deploy-prod-app`   | release | `prod`  | `prod`    | `com.sst.sstcam`       | real               | no         | no          |

**Three orthogonal axes** — the table just names the common combos:
- **Mode** (debug/profile/release) = **debuggability** (hot reload, DevTools, assertions). `dev` is debug; stage/prod are release.
- **Backend + seed** = two *flags* independent of mode: `--dart-define=EMULATE=true|false` (mock vs real BLE/WiFi) and `--dart-define=SEED=true|false` (dev fixtures in the DB). Both default **off** and seed `DevConfig.defaults`; the in-app Developer switches override them at runtime. Only the `dev` env reads them — a stage/prod build skips the dev bootstrap, so both are forced false. `just run` (offline) sets both on; `deploy-dev-app` (on hardware) leaves both off.
- **Dev tooling** = the in-app debug page + developer settings (`kAppEnv.showsDevTooling`, != prod). Distinct from Flutter DevTools, which come from debug **mode**.

So "a debuggable build against the real camera" = **dev flavor** (`deploy-dev-app` / `iterate-app`), not stage. `build-*-app` produces the APK; `deploy-*-app ADDR` builds then installs on a phone via host adb (`ADDR` = USB serial or wireless `ip:port`); `iterate-app ADDR` is the dev hot-reload loop against the Jetson.

- `main.dart` branches on `kAppEnv.isDevBackend`: **dev** runs `_bootstrapDev()`
  (overrides `bleServiceProvider`/`wifiServiceProvider` with mocks + seedable dev
  data + dev nav); **stage/prod** use `shippedOverrides(kAppEnv)` only (real
  `BleServiceImpl`/`WifiServiceImpl` defaults; dev nav for stage, nothing for prod).
- **Mock never ships.** `APP_ENV` is a compile-time const, so a `stage`/`prod`
  build evaluates the `isDevBackend` branch as statically false — `_bootstrapDev`
  and everything it references (mock services, `MockDataSeeder`, seed sync) is
  dead code and **tree-shaken** out of the release binary. Same mechanism
  `shippedOverrides` uses to compile out dev tooling for prod.
- **Mode is orthogonal.** The three recipes pick a mode, but `debug`/`profile`/
  `release` remain available for any env on demand (e.g. profile a stage build).
  The Gradle flavor exists only to give each env its own applicationId + launcher
  icon + name so builds install side-by-side and are told apart at a glance.
- `lib/core/config/env.dart` — `kAppEnv.isDevBackend` (== dev) selects the mock
  backend branch; `showsDevTooling` (!= prod) gates diagnostics/seeding + the
  `shippedOverrides` tooling. Both are const, so prod tree-shakes both branches.

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
  main.dart                    single entry; branches on kAppEnv (see below). app.dart = MaterialApp + theme
  core/                        cross-feature infrastructure
    ble/      BleService (port) + ble_service_impl (flutter_blue_plus) + ble_protocol + ble_providers
    wifi/     WifiService (port) + impl + wifi_p2p_channel + wifi_handoff + wifi_providers
    db/       Drift AppDatabase; tables/ (clips, teams, users, sport_presets,
              streaming_destinations, team_matches, thumbnails) + daos/ (+ generated *.g.dart)
    models/   Plain Dart view models — app compiles without generated protos:
              command, device, telemetry, wifi, match, recording, overlay,
              overlay_layout, team, user, sport_preset, streaming
    services/ backup_service, clip_service, gallery_service, log_service,
              video_path_service
    state/    cross-feature Riverpod providers/controllers: db_providers,
              camera_selection (active camera/tab/output), last_camera,
              connect_controller, reconnect_controller, device_health,
              auto_stop, persisted_match_store
    config/   env, app_config, dev_config, dev_navigation, dev_reseeder
    shell/    app_shell — tabbed NavigationBar shell
    theme/    tokens — colors/spacing tokens (app.dart wires them into ThemeData)
    widgets/  shared widgets (wf_button/card/chip, wf_filter_bar, indicators,
              live_preview_view, preview_controls_row, preview_layout_toggle,
              output_camera_toggle, device_health_banner, reconnect_notice, borders)
  features/                    one folder per user-facing feature; *_state.dart = its Riverpod
    camera/    main_page, camera_state (re-exports core camera_selection)
    discovery/ discovery_page, diagnostics_page, debug_page
    match/     landing/setup/match_page + session/ (session_screen + widgets/
               controls/modals/actions splits, session_state, live_match_models,
               event_sheet)
    teams/     teams_page, team_detail_page, roster/ matches/ stats/ + form sheets
    settings/  settings_page + camera_card + connect_camera_banner +
               sport_presets/ streaming/ users/ data/ developer/ calibration/ network/
    video/     video_page, video_state, playback/ (detail, download_sheet + views)
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
`mock/emulator/` doubles back the dev backend via the **Riverpod override installed
in `main.dart`'s `isDevBackend` branch** (and tests override the same way with
`ProviderScope(overrides: [...])`). The stage/prod branch adds no BLE/WiFi override,
so shipped builds get the real impls.

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

PR-gated, Conventional-Commit driven. Same Git Flow model in all three sst-cam
repos (proto, firmware, app); **levels are tags, not branches**:

| Branch | Lives | Receives | Tag minted |
|---|---|---|---|
| `development` | long, default | `feat/*`, `fix/*` PRs | `vX.Y.Z-alpha.N` on each releasable merge |
| `release/X.Y.Z` | until X.Y.Z ships | cut from `development` at feature freeze, then `fix/*` PRs only | `vX.Y.Z-beta.N`; `vX.Y.Z-rc.N` once promoted to rc |
| `main` | long | only `release/X.Y.Z` (and `hotfix/*`) | `vX.Y.Z` by promotion, no rebuild |
| `feat/*`, `fix/*`, `hotfix/*` | short, deleted after merge | | |

- **alpha** (`vX.Y.Z-alpha.N`) — construction; automated tests vs **mock + emulator**; developer APK.
- **beta** (`vX.Y.Z-beta.N`) — feature freeze for X.Y.Z, fixes only; production + developer APK.
- **rc** (`vX.Y.Z-rc.N`) — after the hardware test (real Jetson + real firmware + this app on a phone): `promote-rc.yml` re-tags the newest beta as `rc.1` on the **same commit** (same APKs); later merges to `release/X.Y.Z` mint `rc.N`.
- **stable** (`vX.Y.Z`) — merge `release/X.Y.Z → main`: the last rc's production APK promoted unchanged (SHA-256 verified).
- **hotfix** — `hotfix/X.Y.Z+1` from `main` → PR to `main` → `vX.Y.(Z+1)` → PR `main → development`.

Two non-negotiables: **gate-in-PR / build-and-tag-on-merge** (the APK is built
only on push, not in the PR — the PR gate is `Analyze & Test` + `CI Scripts`),
and **`main` never builds** (it only promotes an already-built rc APK).

Branch-scoped workflows — each owns one branch class and folds its PR gate in
(gated to `pull_request`); there is no standalone `ci.yml`:

- `.github/workflows/release-alpha.yml` (name `release-alpha`) — **owns `development`.** `pull_request:[development]` runs the gate checks `CI Scripts (shellcheck + version tests)` (shellcheck, actionlint, **proto pin check**) and `Analyze & Test (Linux)` (`dart format` → generate protos (pinned `protoc_plugin 21.1.2`) → `flutter analyze` → `flutter test`). `push:[development]` (+ `workflow_dispatch`) → `resolve-version` (`mode: alpha`; docs/chore-only → **skip**) → builds the **developer** APK (`--flavor stage --dart-define=APP_ENV=stage`) → `publish-release` prerelease.
- `.github/workflows/release-beta.yml` (name `release-beta`) — **owns `release/**`.** Same two gate checks on PRs. `push:[release/**]` (+ `workflow_dispatch`) → `resolve-version` (`mode: release`, X.Y.Z from the branch name: `beta.N`, or `rc.N` after promote-rc) → builds **both** APKs (production `--flavor prod --dart-define=APP_ENV=prod`, developer `--flavor stage`) → `publish-release` prerelease carrying both, with their SHA-256.
- `.github/workflows/promote-rc.yml` (name `promote-rc`) — `workflow_dispatch` on `release/X.Y.Z` after the hardware sign-off: newest beta → `rc.1`.
- `.github/workflows/release.yml` (name `release`) — **owns `main`.** `push:[main]` (+ dispatch) → `promote` (`to: stable`, `assets: "*-production.apk"`): highest `vX.Y.Z-rc.N` → `vX.Y.Z`, APK SHA-256 verified, same bytes renamed. **No `flutter`/Gradle step exists.**

Version math and publishing are the shared actions of
[`ScoutSportTechnology/.github`](https://github.com/ScoutSportTechnology/.github)
(`resolve-version`, `publish-release`, `promote`, pinned `@v1.1.0`): alpha base =
max(Conventional-Commit bump from the last stable, **release floor**
`X.(Y+1).0` while a `release/X.Y.Z` with beta/rc tags is open); breaking bumps the
minor while the major is 0 (`1.0.0` is cut with dispatch `bump: major`).
Signing comes from `ANDROID_*` secrets when set, else falls back to debug
signing. Default `GITHUB_TOKEN` only — no PAT/App. Operational runbooks:
`docs/ci/rulesets.md` (branch/tag rulesets), `docs/ci/version-reset-runbook.md`.

### Branch + commit + tag rules
- `development` is the default branch; target `feat/*` / `fix/*` PRs at it.
- `release/X.Y.Z` is cut from `development` at feature freeze (same X.Y.Z in proto, firmware and app) and takes `fix/*` PRs only. One release branch at a time.
- `main` is promote-only: no direct push; PR (from `release/*`) + 1 approval + green required checks. **No build runs on `main`** (`release.yml` only promotes).
- Tags `v*` are immutable semver (`-alpha.N` < `-beta.N` < `-rc.N` < stable; no delete/move/force-push); only workflows create them.
- Use Conventional Commits; the squash-merge subjects drive the alpha bump (`feat:` → minor, `fix:`/`perf:` → patch, `type(scope)!:`/`BREAKING CHANGE:` → major but minor while the major is 0, docs/chore-only → **skip**).
- A cross-repo change uses the same `feat/<slug>` branch name in every repo; proto merges first, then `proto/` is re-pinned to the **merged** proto commit (`CI Scripts` checks the pin is on the proto branch named like the PR base).

### Releasing
- Alpha: merge a `feat:`/`fix:`/… PR into `development` → `vX.Y.Z-alpha.N` + developer APK (docs/chore-only → no release).
- Beta: `git switch -c release/X.Y.Z development && git push` (same X.Y.Z in all three repos) → both APKs + `vX.Y.Z-beta.1`; `fix/*` PRs into the branch → `beta.N`.
- rc: test the newest beta APK on a phone against the real firmware on a Jetson; when it passes, run `promote-rc` on `release/X.Y.Z` (`gh workflow run promote-rc.yml --ref release/X.Y.Z`) in each repo → `rc.1`; later fixes → `rc.N`.
- Stable: PR `release/X.Y.Z → main` and merge → `release.yml` tags `vX.Y.Z` and copies the rc production APK (no rebuild). Then delete the release branch and PR `main → development`.
- Manual: `gh workflow run release-alpha.yml -f version=v0.2.0` or `-f bump=minor`; `gh workflow run release.yml -f version=X.Y.Z`.
- For release-signed (not debug) APKs, set repo secrets: `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`, `ANDROID_STORE_PASSWORD`.

## Release lifecycle

```
development:   alpha.1 → alpha.2 → alpha.3
                                     │ cut release/0.1.0 (feature freeze)
release/0.1.0:                       └► beta.1 → beta.2 ─► promote-rc ─► rc.1 → rc.2
                                                         (hardware OK)          │ merge → main
main:                                                                           └► v0.1.0
```

- With no stable tag yet, a `feat:` yields base `0.1.0` (pre-1.0: a breaking change also yields a minor); a `fix:`-only → `0.0.1`; docs/chore-only mints nothing.
- While `release/X.Y.Z` is open, `development` builds the next minor (`X.(Y+1).0-alpha.N`). A release branch deleted without shipping no longer counts; its tags stay and a re-cut continues their counters.
- After `v0.1.0` stable exists, the next `feat:` on `development` → `v0.2.0-alpha.1` (a `fix:` → `v0.1.1-alpha.1`).

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

## Scope guardrails

- CI/CD + docs changes here do **not** touch Flutter/Dart app code.
- Proto stays a git submodule consumed via `just gen-proto` (no Dart-package
  cutover). CI must keep `submodules: recursive` + the proto-gen steps with
  pinned `protoc_plugin 21.1.2`.
