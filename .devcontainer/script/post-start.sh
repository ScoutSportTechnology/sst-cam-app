#!/bin/bash
set -eu

# Bridge host adb-forward ports into the container's loopback so Flutter's
# 127.0.0.1 connections reach the emulator's VM service. Detached so post-start
# can exit; survives until container shutdown.
setsid -f "$(dirname "$0")/adb-bridge.sh" </dev/null

# Bridge mock-camera-wifi ports to attached Android device (no-op if no device connected).
# RTSP maps device:8554 -> host:8555 to avoid QEMU virtualscene which owns host:8554.
adb reverse tcp:8554 tcp:8555 2>/dev/null || true
adb reverse tcp:8080 tcp:8080 2>/dev/null || true

echo "Post-start script executed successfully."
