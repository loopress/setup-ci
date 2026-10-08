#!/usr/bin/env bash
set -euo pipefail

COMPOSE_FILE="${LOOPRESS_COMPOSE_FILE:-/tmp/loopress-compose.yml}"

docker compose -f "$COMPOSE_FILE" up -d --wait --wait-timeout 180
echo "WordPress is ready"
