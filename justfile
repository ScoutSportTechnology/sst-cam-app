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

# Local validation loop — build the SAME prod artifact CI ships and install it
# straight to a phone over adb wireless, WITHOUT pushing or minting a release
# tag. The build runs in the container; adb runs on the HOST (which holds the
# phone pairing), so you need `adb` on the host PATH.
#
# One-time pairing from the host (Android 11+ wireless debugging):
#   adb pair <ip>:<pair-port>     # code shown on the phone
#   adb connect <ip>:5555
# Then iterate: just deploy-phone 192.168.1.42   (or 192.168.1.42:5555)
#
# Note: the prod APK is debug-signed (no keystore configured), same as CI, so
# `install -r` upgrades in place. On a signature mismatch, run
# `adb uninstall com.sst.sstcam` once, then re-run.
deploy-phone IP: build-android-prod
    @APK="build/app/outputs/flutter-apk/app-prod-release.apk"; \
     ADDR="{{IP}}"; case "$ADDR" in *:*) ;; *) ADDR="${ADDR}:5555";; esac; \
     command -v adb >/dev/null || { echo "adb not found on host PATH" >&2; exit 1; }; \
     [ -f "$APK" ] || { echo "APK not found: $APK" >&2; exit 1; }; \
     echo "Connecting adb to ${ADDR} ..."; adb connect "$ADDR"; \
     echo "Installing ${APK} -> ${ADDR} ..."; adb -s "$ADDR" install -r "$APK"; \
     echo "Installed app-prod-release (com.sst.sstcam) to ${ADDR}"

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
