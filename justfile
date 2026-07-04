# SST Cam app — task runner.
#
# Every recipe runs natively when you're INSIDE the dev container, and
# transparently delegates to the container via the `devcontainer` CLI when you
# run it from the HOST. You never have to think about which — `just test` works
# the same in both places.
#
# Requirements:
#   - Host:         `just` + the `devcontainer` CLI on PATH (or at ~/.devcontainers/bin).
#   - In-container: `just` (installed via the devcontainer `just` feature).
# Start the container once from the host with `just up` before delegating.

set shell := ["bash", "-uc"]

# --- version defines (U4) -------------------------------------------------
# In-app version display is git-derived, never a hardcoded literal. APP_VERSION
# is `git describe`; APP_CHANNEL maps the branch onto the maturity ladder
# (development→alpha, release/*→beta, main→stable, else dev); PROTO_VERSION is
# the proto submodule's tag. CI overrides these with resolve-version.sh values.
app_version := `git describe --tags --always --dirty 2>/dev/null || echo dev`
app_channel := `b=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo dev); case "$b" in development) echo alpha;; release/*) echo beta;; main) echo stable;; *) echo dev;; esac`
proto_version := `git -C proto describe --tags --always 2>/dev/null || echo dev`
version_defines := "--dart-define=APP_VERSION=" + app_version + " --dart-define=APP_CHANNEL=" + app_channel + " --dart-define=PROTO_VERSION=" + proto_version

# List recipes.
default:
    @just --list

# --- container lifecycle (host-side) --------------------------------------

# Start the dev container (no-op if already running).
up:
    @_DC="$(command -v devcontainer || echo "$HOME/.devcontainers/bin/devcontainer")"; "$_DC" up --workspace-folder "{{justfile_directory()}}"

# Open an interactive shell in the dev container.
shell:
    @_DC="$(command -v devcontainer || echo "$HOME/.devcontainers/bin/devcontainer")"; "$_DC" exec --workspace-folder "{{justfile_directory()}}" bash

# --- dev recipes (auto native-or-delegated) -------------------------------

# Install/update dependencies.
get:
    @just _run "flutter pub get"

# Run unit + widget tests. Extra args pass through: `just test test/wifi/`.
test *args:
    @just _run "flutter test {{args}}"

# Integration tests (needs a connected device/emulator).
test-integration:
    @just _run "flutter test test/integration/"

# Unit + integration tests.
test-all: test test-integration

# Static analysis.
analyze:
    @just _run "flutter analyze"

# Format sources.
format:
    @just _run "dart format lib test integration_test"

# Format check (CI — non-zero exit on diff).
format-check:
    @just _run "dart format --set-exit-if-changed lib test integration_test"

# Full CI gate: format-check + analyze + test.
ci: format-check analyze test

# Three canonical builds, one per env, all on the single entry (lib/main.dart);
# backend + tooling are selected by APP_ENV, the flavor gives each its own
# applicationId + icon + name:
#   dev   → debug,   --flavor dev   APP_ENV=dev    mock backend
#   stage → release, --flavor stage APP_ENV=stage  real backend + dev tooling
#   prod  → release, --flavor prod  APP_ENV=prod   shipped (tooling compiled out)
# Mode (debug/profile/release) is orthogonal — profile any env on demand.

# build-<env>-app → build that env's APK in the dev container; the APK lands in
# build/app/outputs/flutter-apk/app-<flavor>-<mode>.apk. No device needed.
# EMULATE (mock backend) + SEED (dev fixtures) are two orthogonal flags read only
# by the dev env — stage/prod force both false. Both are ORTHOGONAL to MODE: a
# debug build is debuggable regardless.
[private]
_build-app MODE FLAVOR ENV EMULATE SEED: gen-icons
    @just _run "flutter build apk --{{MODE}} --flavor {{FLAVOR}} --dart-define=APP_ENV={{ENV}} --dart-define=EMULATE={{EMULATE}} --dart-define=SEED={{SEED}} {{version_defines}}"

# dev   → debug, REAL backend, no seed (flags off) — debuggable, on hardware.
#         Flip mock/seed via the in-app Developer switches, or EMULATE/SEED=true.
build-dev-app: (_build-app "debug" "dev" "dev" "false" "false")
# stage → release, real backend + dev tooling (CI's developer APK; NOT debuggable).
build-stage-app: (_build-app "release" "stage" "stage" "false" "false")
# prod  → release, real backend, tooling compiled out (the shipped artifact).
build-prod-app: (_build-app "release" "prod" "prod" "false" "false")

# Run the dev build on a local emulator — mock backend + seed data (no hardware).
run: gen-icons
    @just _run "flutter run --flavor dev --dart-define=APP_ENV=dev --dart-define=EMULATE=true --dart-define=SEED=true {{version_defines}}"

# --- phone (real hardware) -------------------------------------------------
# adb runs on the HOST: the container's adb crashes during the Android-11+ TLS
# pair, so pairing/connection live in the host adb (keys persist in ~/.android).
# `host_adb` defaults to PATH but can be overridden:
#   just host_adb=./.devtools/platform-tools/adb deploy-stage-app 10.10.1.121:46273
host_adb := justfile_directory() / "../.devtools/platform-tools/adb"
fl_img := "flutter4android"
# Persist the Android SDK + Gradle cache across the ephemeral iterate-app
# containers so the second run onward is fast (named volumes survive --rm).
fl_cache := "-v sst_android_sdk:/home/vscode/android-sdk -v sst_gradle_cache:/home/vscode/.gradle -v sst_pub_cache:/home/vscode/.pub-cache"

# Pair the phone ONCE (host adb). Phone: Wireless debugging -> "Pair device with
# pairing code" gives <ip:pair-port> and a 6-digit CODE.
#   just pair-phone 10.10.1.121:37123 123456
pair-phone ADDR CODE:
    @{{host_adb}} start-server >/dev/null 2>&1; sleep 1; {{host_adb}} pair {{ADDR}} {{CODE}}

# deploy-<env>-app ADDR → build that env's APK in the container, then install it on
# the phone via host adb. ADDR = the CONNECT ip:port (wireless) or the USB serial
# (from `adb devices`). APKs are debug-signed (no keystore), so `install -r`
# upgrades in place; on a signature mismatch `adb uninstall <applicationId>` once,
# then re-run. The three flavors have distinct applicationIds → install side-by-side.
[private]
_deploy-app MODE FLAVOR ENV EMULATE SEED ADDR: (_build-app MODE FLAVOR ENV EMULATE SEED)
    @APK="build/app/outputs/flutter-apk/app-{{FLAVOR}}-{{MODE}}.apk"; \
     [ -f "$APK" ] || { echo "APK not found: $APK" >&2; exit 1; }; \
     {{host_adb}} connect {{ADDR}} >/dev/null 2>&1 || true; \
     {{host_adb}} -s {{ADDR}} install -r "$APK" \
       && echo "Installed $APK on {{ADDR}}"

# dev   → debug, REAL backend + debuggability (your daily driver on hardware).
#   just deploy-dev-app R5GYB5J72CT
deploy-dev-app ADDR: (_deploy-app "debug" "dev" "dev" "false" "false" ADDR)
# stage → release, real backend + dev tooling (device-test the release artifact).
#   just deploy-stage-app R5GYB5J72CT
deploy-stage-app ADDR: (_deploy-app "release" "stage" "stage" "false" "false" ADDR)
# prod  → release, the shipped artifact (final pre-PR check).
#   just deploy-prod-app R5GYB5J72CT
deploy-prod-app ADDR: (_deploy-app "release" "prod" "prod" "false" "false" ADDR)

# Fast iteration on the phone with hot reload/restart — dev flavor, debug mode,
# REAL backend (debuggable, against the Jetson). Run from a TTY so r=hot-reload /
# R=hot-restart / q=quit work. flutter runs in a one-shot container sharing the
# host adb server via --network host.
#   just iterate-app 10.10.1.121:46273
iterate-app ADDR:
    @{{host_adb}} connect {{ADDR}} >/dev/null 2>&1 || true; \
     docker run --rm -it --network host -u vscode -e HOME=/home/vscode \
       {{fl_cache}} \
       -v "{{justfile_directory()}}":/workspaces/sst-cam-app -w /workspaces/sst-cam-app \
       {{fl_img}} bash -c 'FL=/home/vscode/flutter/bin/flutter; \
         $FL pub get && dart run flutter_launcher_icons && \
         $FL run --flavor dev --dart-define=APP_ENV=dev --dart-define=EMULATE=false --dart-define=SEED=false {{version_defines}} -d {{ADDR}}'

# Clean build artifacts.
clean:
    @just _run "flutter clean"

# Generate per-flavor launcher icons into android/app/src/<flavor>/res from every
# flutter_launcher_icons-<flavor>.yaml config (dev/stage/prod — auto-discovered).
# Run before building a flavored APK.
gen-icons:
    @just _run "dart run flutter_launcher_icons"

# Regenerate Dart proto bindings (needs protoc in the container).
gen-proto:
    @just _run "mkdir -p lib/models/proto && protoc --dart_out=lib/models/proto -I proto proto/*.proto && echo 'Proto bindings written to lib/models/proto/'"

# Regenerate Drift database bindings.
gen-db:
    @just _run "dart run build_runner build --delete-conflicting-outputs"

# --- internals ------------------------------------------------------------

# Run CMD natively inside the container, else delegate to it via the CLI.
[private]
_run +cmd:
    @if [ -f /.dockerenv ]; then \
        bash -lc "{{cmd}}"; \
    else \
        _DC="$(command -v devcontainer || echo "$HOME/.devcontainers/bin/devcontainer")"; \
        "$_DC" exec --workspace-folder "{{justfile_directory()}}" bash -lc "{{cmd}}"; \
    fi
