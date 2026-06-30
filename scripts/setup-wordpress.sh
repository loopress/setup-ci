#!/usr/bin/env bash
set -euo pipefail

WP_PORT="${LOOPRESS_WP_PORT:-8080}"
WP_HOST="${LOOPRESS_WP_HOST:-localhost}"
SITE_ID="${LOOPRESS_SITE_ID:-ci}"
COMPOSE_FILE="${LOOPRESS_COMPOSE_FILE:-/tmp/loopress-compose.yml}"

CONTAINER=$(docker compose -f "$COMPOSE_FILE" ps -q wordpress)

docker exec "$CONTAINER" bash -c "
  curl -sO https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
  chmod +x wp-cli.phar && mv wp-cli.phar /usr/local/bin/wp
"

# WP-CLI uses the internal port (80) — the external port is not accessible from inside the container.
# siteurl/home are updated separately to the external port for Loopress REST API calls.
docker exec "$CONTAINER" wp core install \
  --url="http://localhost" \
  --title="Loopress CI" \
  --admin_user="admin" \
  --admin_password="admin" \
  --admin_email="ci@loopress.dev" \
  --skip-email \
  --allow-root

docker exec "$CONTAINER" wp option update siteurl "http://${WP_HOST}:${WP_PORT}" --allow-root
docker exec "$CONTAINER" wp option update home "http://${WP_HOST}:${WP_PORT}" --allow-root

APP_PASSWORD=$(docker exec "$CONTAINER" wp user application-password create admin "Loopress CI" \
  --porcelain --allow-root)

ADDED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mkdir -p ~/.loopress
export SITE_ID WP_HOST WP_PORT APP_PASSWORD ADDED_AT
envsubst < "$SCRIPT_DIR/../templates/loopress-config.json" > ~/.loopress/config.json
