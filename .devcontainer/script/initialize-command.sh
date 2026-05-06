#!/bin/bash
set -e

ADB=~/Android/Sdk/platform-tools/adb

if [ ! -f "$ADB" ]; then
  echo "ADB not found at $ADB — skipping host ADB restart"
  exit 0
fi

echo "Restarting ADB server to listen on all interfaces..."
$ADB kill-server
setsid $ADB -a nodaemon server start &
ss -tlnp | grep 5037
echo "ADB server started"

