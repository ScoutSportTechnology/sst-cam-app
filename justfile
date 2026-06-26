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

# Build a debug APK (mock backend, lib/main.dart) on the dev flavor.
build-android: gen-icons
    @just _run "flutter build apk --debug --flavor dev"

# Build the dev variant APK (real backend + tooling): dev flavor + APP_ENV=stage.
build-android-dev: gen-icons
    @just _run "flutter build apk --release --flavor dev --target=lib/main_prod.dart --dart-define=APP_ENV=stage"

# Build the prod variant APK (real backend, tooling compiled out): prod flavor + APP_ENV=prod.
build-android-prod: gen-icons
    @just _run "flutter build apk --release --flavor prod --target=lib/main_prod.dart --dart-define=APP_ENV=prod"

# Run the app on a connected device (mock backend, dev flavor).
run: gen-icons
    @just _run "flutter run --flavor dev"

# --- phone iteration loop (real backend, hot reload) ----------------------
# adb runs on the HOST: the container's adb crashes during the Android-11+ TLS
# pair, so pairing/connection live in the host adb (keys persist in ~/.android).
# flutter still runs in the container, sharing the host adb server via
# `--network host`. Requires `adb` on the host PATH (platform-tools); pairing is
# one-time. `host_adb` defaults to PATH but can be overridden:
#   just host_adb=./.devtools/platform-tools/adb run-phone 10.10.1.121:46273
host_adb := "adb"
fl_img := "flutter4android"

# Pair the phone ONCE (host adb). From the phone: Wireless debugging -> "Pair
# device with pairing code" gives <ip:pair-port> and a 6-digit CODE.
#   just pair-phone 10.10.1.121:37123 123456
pair-phone ADDR CODE:
    @{{host_adb}} start-server >/dev/null 2>&1; sleep 1; {{host_adb}} pair {{ADDR}} {{CODE}}

# Iterate on a real phone with hot reload/restart (debug build, prod flavor =
# real BLE/WiFi backend). ADDR is the CONNECT ip:port from the main wireless-
# debugging screen. Run from a terminal (TTY) so r=hot-reload / R=hot-restart /
# q=quit work. Pair once first with `just pair-phone`. flutter (container) reaches
# the host-connected device via --network host.
#   just run-phone 10.10.1.121:46273
run-phone ADDR: gen-icons
    @{{host_adb}} connect {{ADDR}} >/dev/null 2>&1 || true; \
     docker run --rm -it --network host -u vscode -e HOME=/home/vscode \
       -v "{{justfile_directory()}}":/workspaces/sst-cam-app -w /workspaces/sst-cam-app \
       {{fl_img}} /home/vscode/flutter/bin/flutter \
         run --flavor prod -t lib/main_prod.dart --dart-define=APP_ENV=prod -d {{ADDR}}

# Final-check loop — build the SAME prod RELEASE artifact CI ships (AOT, no hot
# reload) and install it, WITHOUT pushing or minting a release tag. Use
# `run-phone` for fast iteration; use this once before a PR to validate the real
# shipped artifact. Builds in the container; installs via host adb. ADDR is the
# CONNECT ip:port. Pair once via `just pair-phone`.
#   just deploy-phone 10.10.1.121:46273
#
# The prod APK is debug-signed (no keystore), same as CI, so `install -r` upgrades
# in place. On a signature mismatch, `adb uninstall com.sst.sstcam` once, re-run.
deploy-phone ADDR: build-android-prod
    @APK="build/app/outputs/flutter-apk/app-prod-release.apk"; \
     [ -f "$APK" ] || { echo "APK not found: $APK" >&2; exit 1; }; \
     {{host_adb}} connect {{ADDR}} >/dev/null 2>&1 || true; \
     {{host_adb}} -s {{ADDR}} install -r "$APK" && \
     echo "Installed app-prod-release (com.sst.sstcam) to {{ADDR}}"

# Clean build artifacts.
clean:
    @just _run "flutter clean"

# Generate per-flavor launcher icons into android/app/src/<flavor>/res from the
# flutter_launcher_icons-<flavor>.yaml configs. Run before building a flavored APK.
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
