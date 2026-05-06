#!/bin/sh
set -eu

target=/root/.claude/claude.json
link=/root/.claude.json

mkdir -p /root/.claude

# If Claude wrote /root/.claude.json directly (e.g. an atomic-rename replaced
# the symlink with a regular file), fold its content back into the volume.
if [ -f "$link" ] && [ ! -L "$link" ]; then
  cp -p "$link" "$target.new"
  mv -f "$target.new" "$target"
fi

[ -e "$target" ] || : > "$target"

# Recreate the symlink atomically via rename(2) so there is never a moment
# where $link is missing — the Claude Code extension may launch the CLI in
# parallel with this script.
ln -sf "$target" "$link.new"
mv -f "$link.new" "$link"

echo "[claude] config symlink ok."
