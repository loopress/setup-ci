#!/usr/bin/env bash
set -euo pipefail

COMPOSE_FILE="${LOOPRESS_COMPOSE_FILE:-/tmp/loopress-compose.yml}"
SNAPSHOT_PATH="${LOOPRESS_SNAPSHOT_PATH:-/tmp/loopress-snapshot-clean.sql}"

CONTAINER=$(docker compose -f "$COMPOSE_FILE" ps -q wordpress)

if [ ! -f "$SNAPSHOT_PATH" ]; then
  echo "::error::No snapshot found at $SNAPSHOT_PATH. Did setup-wordpress.sh run first (it writes the snapshot as its last step)?" >&2
  exit 1
fi

# `wp db import` replaces every table from the dump, so this brings the site straight back to
# the clean, working state setup-wordpress.sh captured, undoing anything the previous group of
# e2e tests changed (created/edited snippets, plugin toggles, etc.) in one shot.
docker cp "$SNAPSHOT_PATH" "$CONTAINER":/tmp/loopress-snapshot-clean.sql
docker exec "$CONTAINER" wp db import /tmp/loopress-snapshot-clean.sql --allow-root
