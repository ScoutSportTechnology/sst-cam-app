#!/usr/bin/env bash
# =============================================================================
# check-proto-pin.sh — the proto/ submodule must pin a MERGED proto commit.
#
#   scripts/ci/check-proto-pin.sh <proto-branch> [proto-url]
#
# <proto-branch> is the sst-cam-proto branch with the same name as this PR's
# base (development or release/X.Y.Z): cross-repo work uses the same branch
# names in every repo, so a consumer PR into release/0.2.0 must pin a commit
# that is on proto's release/0.2.0. A commit from a proto feat/* branch fails:
# squash merges change the SHA, so that pin would dangle after the merge.
# =============================================================================
set -euo pipefail

branch="${1:?usage: check-proto-pin.sh <proto-branch> [proto-url]}"
url="${2:-https://github.com/ScoutSportTechnology/sst-cam-proto.git}"

pin="$(git ls-tree HEAD proto | awk '$2 == "commit" { print $3 }')"
if [ -z "$pin" ]; then
  echo "::error::proto/ is not a submodule in HEAD"
  exit 1
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
git init -q "$tmp"
if ! git -C "$tmp" fetch -q --filter=blob:none "$url" \
    "+refs/heads/${branch}:refs/remotes/proto/${branch}" 2>/dev/null; then
  echo "::error::sst-cam-proto has no branch '${branch}'. Use the same branch name in proto (create it there first)."
  exit 1
fi

if git -C "$tmp" merge-base --is-ancestor "$pin" "refs/remotes/proto/${branch}" 2>/dev/null; then
  echo "proto/ pin ${pin:0:7} is merged into sst-cam-proto ${branch}"
else
  echo "::error::proto/ pins ${pin}, which is not merged into sst-cam-proto ${branch}. Pin a merged proto commit (squash merges change the SHA; never pin a feat/* commit)."
  exit 1
fi
