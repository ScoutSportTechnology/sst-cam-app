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

# Reverse-forward mappings: "device_port:host_port"
# RTSP uses 8555 on the host to avoid QEMU virtualscene which binds host:8554.
# The device-side port stays 8554 so RTSP URLs need no change.
REVERSE_MAP=("8554:8555" "8080:8080")

declare -A bridged
declare -A reversed  # device_id -> "1" once reverse ports are confirmed set up

while true; do
  for hp in $(adb forward --list 2>/dev/null | awk '{print $2}' | sed 's/tcp://' | sort -u); do
    [ -z "$hp" ] && continue
    if [ -z "${bridged[$hp]:-}" ]; then
      bridged[$hp]=1
      socat "TCP-LISTEN:$hp,bind=127.0.0.1,fork,reuseaddr" "TCP:host.docker.internal:$hp" >/dev/null 2>&1 &
      echo "[$(date -Is)] bridge 127.0.0.1:$hp -> host.docker.internal:$hp"
    fi
  done

  # Ensure reverse ports are active for every connected device. Runs on every
  # iteration so newly connected or reconnected devices are handled automatically.
  while IFS= read -r dev; do
    [ -z "$dev" ] && continue
    current=$(adb -s "$dev" reverse --list 2>/dev/null | awk '{print $2}' | sort | tr '\n' ',')
    needed=""
    for mapping in "${REVERSE_MAP[@]}"; do
      dev_port="${mapping%%:*}"
      echo "$current" | grep -q "tcp:$dev_port" || needed="$needed $mapping"
    done
    if [ -n "$needed" ]; then
      for mapping in $needed; do
        dev_port="${mapping%%:*}"
        host_port="${mapping##*:}"
        adb -s "$dev" reverse "tcp:$dev_port" "tcp:$host_port" >/dev/null 2>&1 && \
          echo "[$(date -Is)] reverse $dev tcp:$dev_port -> host tcp:$host_port"
      done
      reversed[$dev]=1
    fi
  done < <(adb devices 2>/dev/null | awk '/\tdevice$/{print $1}')

  sleep 1
done
