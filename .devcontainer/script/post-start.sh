#!/bin/bash
set -eu

# Bridge host adb-forward ports into the container's loopback so Flutter's
# 127.0.0.1 connections reach the emulator's VM service. Detached so post-start
# can exit; survives until container shutdown.
setsid -f "$(dirname "$0")/adb-bridge.sh" </dev/null

echo "Post-start script executed successfully."
