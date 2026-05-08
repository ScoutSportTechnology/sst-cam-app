#!/bin/sh
set -eu

git config --global --add safe.directory /workspace
git config --global --add safe.directory /opt/flutter

dart pub global activate protoc_plugin

flutter config --no-enable-linux-desktop

flutter pub get

echo "Post-create script executed successfully."
