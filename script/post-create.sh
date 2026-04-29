#!/bin/sh
set -eu

git config --global --add safe.directory /workspace

flutter pub get

echo "Post-create script executed successfully."