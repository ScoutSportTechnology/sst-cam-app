#!/bin/sh
set -eu

"$(dirname "$0")/install-claude.sh"

git config --global --add safe.directory /workspace

flutter config --no-enable-linux-desktop

flutter pub get

echo "Post-create script executed successfully."