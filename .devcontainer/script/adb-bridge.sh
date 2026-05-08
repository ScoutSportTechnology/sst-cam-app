#!/bin/bash
# Bridge container 127.0.0.1:<port> -> host.docker.internal:<port> for every
# port the host's adb server is forwarding. Required because adb forwards live
# on the host (ADB_SERVER_SOCKET points to host.docker.internal:5037) but the
# Flutter tool inside the container connects to 127.0.0.1.
set -u

LOG=/tmp/adb-bridge.log
PIDFILE=/tmp/adb-bridge.pid

if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
  echo "adb-bridge already running (pid $(cat "$PIDFILE"))"
  exit 0
fi
echo $$ > "$PIDFILE"
exec >>"$LOG" 2>&1
echo "[$(date -Is)] adb-bridge starting (pid $$)"

trap 'pkill -P $$ 2>/dev/null; rm -f "$PIDFILE"' EXIT

declare -A bridged
while true; do
  for hp in $(adb forward --list 2>/dev/null | awk '{print $2}' | sed 's/tcp://' | sort -u); do
    [ -z "$hp" ] && continue
    if [ -z "${bridged[$hp]:-}" ]; then
      bridged[$hp]=1
      socat "TCP-LISTEN:$hp,bind=127.0.0.1,fork,reuseaddr" "TCP:host.docker.internal:$hp" >/dev/null 2>&1 &
      echo "[$(date -Is)] bridge 127.0.0.1:$hp -> host.docker.internal:$hp"
    fi
  done
  sleep 1
done
