#!/usr/bin/env bash
# Pre-deploy guard: fails when a deploy would overwrite an edit made on the site outside the repo.
#
# Usage: drift-guard.sh <env> <previous-commit-sha>   (run from the repository root, before `lps push`)
#
# Baseline: the previous commit, i.e. what the last deploy pushed. A site that differs from it was
# edited outside the repo. To avoid blocking the pull that brings that edit into the repo, an id
# only blocks when it also differs from the commit being deployed (same rule as the local
# `lps push` guard). Anything inconclusive only warns. LOOPRESS_SKIP_DRIFT_GUARD=1 skips it.
set -uo pipefail

ENV_NAME="${1:?usage: drift-guard.sh <env> <previous-commit-sha>}"
BASE="${2:-}"

warn() { echo "drift guard: $*" >&2; }

if [ -n "${LOOPRESS_SKIP_DRIFT_GUARD:-}" ]; then
  warn "skipped (LOOPRESS_SKIP_DRIFT_GUARD is set)."
  exit 0
fi

if [ -z "$BASE" ] || [[ "$BASE" =~ ^0+$ ]]; then
  warn "no previous commit (first push or new branch), skipping."
  exit 0
fi

if ! git cat-file -e "${BASE}^{commit}" 2>/dev/null; then
  git fetch --quiet --depth=1 origin "$BASE" 2>/dev/null || true
fi
if ! git cat-file -e "${BASE}^{commit}" 2>/dev/null; then
  warn "cannot fetch commit $BASE, skipping."
  exit 0
fi

WORK="$(mktemp -d)"
trap 'git worktree remove --force "$WORK/base" >/dev/null 2>&1; rm -rf "$WORK"' EXIT

if ! git worktree add --quiet --detach "$WORK/base" "$BASE"; then
  warn "cannot check out $BASE, skipping."
  exit 0
fi

# Site vs the previous commit, then site vs the commit being deployed.
(cd "$WORK/base" && lps diff --env "$ENV_NAME" --json >"$WORK/before.json" 2>"$WORK/before.err")
BEFORE_CODE=$?
lps diff --env "$ENV_NAME" --json >"$WORK/after.json" 2>"$WORK/after.err"
AFTER_CODE=$?

if { [ "$BEFORE_CODE" -ne 0 ] && [ "$BEFORE_CODE" -ne 1 ]; } || { [ "$AFTER_CODE" -ne 0 ] && [ "$AFTER_CODE" -ne 1 ]; } \
  || ! jq -e . "$WORK/before.json" >/dev/null 2>&1 || ! jq -e . "$WORK/after.json" >/dev/null 2>&1; then
  warn "comparison inconclusive (exit $BEFORE_CODE and $AFTER_CODE), not blocking."
  exit 0
fi
if [ "$(jq -s '[.[].resources[]? | select(.error != null)] | length' "$WORK/before.json" "$WORK/after.json")" -gt 0 ]; then
  warn "some resources could not be compared, those are not guarded."
fi

# Ids present on the site that differ from the compared files: changed, or only on the site.
# Ids missing on the site are ignored, pushing over a deletion loses nothing.
IDS='.resources | to_entries[] | .key as $r | ((.value.changed[]? | .id), (.value.removed[]?)) | "\($r)/\(.)"'
jq -r "$IDS" "$WORK/before.json" | sort -u >"$WORK/before.ids"
jq -r "$IDS" "$WORK/after.json" | sort -u >"$WORK/after.ids"
BLOCKING="$(comm -12 "$WORK/before.ids" "$WORK/after.ids")"

if [ -n "$BLOCKING" ]; then
  echo "drift guard: $ENV_NAME has edits made outside the repo that this deploy would overwrite:" >&2
  # shellcheck disable=SC2001
  echo "$BLOCKING" | sed 's/^/  - /' >&2
  echo "Run \`lps pull --env $ENV_NAME\` and commit the result, then deploy again." >&2
  echo "If the previous commit was never deployed (failed or skipped deploy) this can be a false alarm: set LOOPRESS_SKIP_DRIFT_GUARD=1 as a CI variable to skip the guard for one run." >&2
  exit 1
fi

echo "drift guard: no outside edit would be overwritten on $ENV_NAME."
