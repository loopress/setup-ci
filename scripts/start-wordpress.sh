#!/usr/bin/env bash
set -euo pipefail

COMPOSE_FILE="${LOOPRESS_COMPOSE_FILE:-/tmp/loopress-compose.yml}"
WP_PORT="${LOOPRESS_WP_PORT:-8080}"
WP_HOST="${LOOPRESS_WP_HOST:-localhost}"

docker compose -f "$COMPOSE_FILE" up -d

echo "Waiting for WordPress to be reachable..."
timeout 90 bash -c \
  "until curl -so /dev/null --connect-timeout 5 http://${WP_HOST}:${WP_PORT}/; do sleep 3; done"
echo "WordPress is ready"
