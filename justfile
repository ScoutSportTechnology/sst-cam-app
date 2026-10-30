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
    @docker image inspect flutter4android >/dev/null

# Open an interactive shell in the dev container.
shell:
    @just _run 'exec bash'

# --- dev recipes (auto native-or-delegated) -------------------------------

# Install/update dependencies.
get:
    @just _run "flutter pub get"

# Run unit + widget tests and script checks.
test *args:
    @just _run 'flock /tmp/sst-cam-app-setup.lock just _prepare && flutter test --concurrency="$(nproc)" {{args}} && bash -n scripts/ci/*.sh'

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

lint:
    @just _run 'flock /tmp/sst-cam-app-setup.lock just _prepare && git ls-files -z -- "*.dart" | xargs -0 -r dart format --set-exit-if-changed && flutter analyze && shellcheck scripts/ci/*.sh && scripts/ci/check-proto-pin.sh "${BASE:-development}"'

fmt:
    @just _run 'dirs="lib test"; [ ! -d integration_test ] || dirs="$dirs integration_test"; dart format $dirs'

compile:
    @just _run 'flock /tmp/sst-cam-app-setup.lock just _prepare && flutter build apk --debug --flavor dev --dart-define=APP_ENV=dev'

test-device:
    @just _run 'flutter test test/integration/ -d "${DEVICE_ID:?DEVICE_ID is required}"'

build:
    @just _run 'flock /tmp/sst-cam-app-setup.lock just _prepare && TAG="${TAG:-$(git describe --tags --always)}" && CHANNEL="${CHANNEL:-$(case "$TAG" in *-alpha.*) printf alpha;; *-beta.*) printf beta;; *) printf rc;; esac)}" && if [ -z "${ANDROID_KEYSTORE_BASE64:-}" ]; then printf "%s\n" "Warning: release APK uses debug signing" >&2; fi && if [ -n "${ANDROID_KEYSTORE_BASE64:-}" ]; then umask 077 && printf "%s" "$ANDROID_KEYSTORE_BASE64" | base64 --decode > android/app/upload-keystore.jks && printf "storeFile=upload-keystore.jks\nstorePassword=%s\nkeyAlias=%s\nkeyPassword=%s\n" "$ANDROID_STORE_PASSWORD" "$ANDROID_KEY_ALIAS" "$ANDROID_KEY_PASSWORD" > android/key.properties; fi && dart run flutter_launcher_icons && mkdir -p dist && flutter build apk --release --flavor stage --dart-define=APP_ENV=stage --dart-define=APP_VERSION="${TAG:?TAG is required}" --dart-define=APP_CHANNEL="${CHANNEL:?CHANNEL is required}" --dart-define=PROTO_VERSION="$(git -C proto describe --tags --always 2>/dev/null || echo dev)" --target-platform android-arm64 && cp build/app/outputs/apk/stage/release/app-stage-release.apk "dist/sst-cam-app-${TAG}-developer.apk" && if [ "$CHANNEL" != alpha ]; then flutter build apk --release --flavor prod --dart-define=APP_ENV=prod --dart-define=APP_VERSION="$TAG" --dart-define=APP_CHANNEL="$CHANNEL" --dart-define=PROTO_VERSION="$(git -C proto describe --tags --always 2>/dev/null || echo dev)" --target-platform android-arm64 && cp build/app/outputs/apk/prod/release/app-prod-release.apk "dist/sst-cam-app-${TAG}-production.apk"; fi'

ci:
    @just lint & lint_pid=$!; just compile && just test; result=$?; wait "$lint_pid" || exit $?; exit "$result"

[private]
_prepare:
    @flutter pub get && dart pub global activate protoc_plugin 21.1.2 && export PATH="$HOME/.pub-cache/bin:$PATH" && mkdir -p lib/models/proto && protoc --dart_out=lib/models/proto -I proto proto/*.proto

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

# Run CMD inside the container, or use the existing image from the host.
[private]
_run +cmd:
    @if [ -f /.dockerenv ] && [ -d /workspaces/sst-cam-app ]; then \
        bash -uc {{ quote(cmd) }}; \
    else \
        docker run --rm -u "$(id -u):$(id -g)" \
            -e HOME=/home/vscode -e BASE="${BASE:-development}" -e TAG="${TAG:-}" -e CHANNEL="${CHANNEL:-}" \
            -e ANDROID_KEYSTORE_BASE64 -e ANDROID_KEY_ALIAS -e ANDROID_KEY_PASSWORD -e ANDROID_STORE_PASSWORD \
            -e GIT_CONFIG_COUNT=3 -e GIT_CONFIG_KEY_0=safe.directory -e GIT_CONFIG_VALUE_0=/workspaces/sst-cam-app \
            -e GIT_CONFIG_KEY_1=safe.directory -e GIT_CONFIG_VALUE_1=/workspaces/sst-cam-app/proto \
            -e GIT_CONFIG_KEY_2=safe.directory -e GIT_CONFIG_VALUE_2=/home/vscode/flutter \
            -v "{{justfile_directory()}}:/workspaces/sst-cam-app" \
            -v "{{justfile_directory()}}:{{justfile_directory()}}" \
            -v "$(git rev-parse --path-format=absolute --git-common-dir):$(git rev-parse --path-format=absolute --git-common-dir)" \
            -w /workspaces/sst-cam-app flutter4android bash -uc {{ quote(cmd) }}; \
    fi
