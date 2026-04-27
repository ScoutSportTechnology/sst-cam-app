default:
    @just --list

# Generate Dart bindings from proto files
gen-proto:
    mkdir -p lib/models/proto
    protoc \
      --dart_out=lib/models/proto \
      -I proto \
      proto/*.proto
    @echo "Proto bindings written to lib/models/proto/"

# Install/update dependencies
get:
    flutter pub get

# Run all unit + widget tests
test:
    flutter test

# Run integration tests (requires connected device/emulator)
test-integration:
    flutter test test/integration/

# Run all tests (unit + integration)
test-all: test test-integration

# Lint
analyze:
    flutter analyze

# Format
format:
    dart format lib test integration_test

# Format check (CI)
format-check:
    dart format --set-exit-if-changed lib test integration_test

# Build Android APK (debug)
build-android:
    flutter build apk --debug

# Build Android APK (release)
build-android-release:
    flutter build apk --release

# Run app on connected device
run:
    flutter run

# Clean build artifacts
clean:
    flutter clean

# Full CI check
ci: format-check analyze test
