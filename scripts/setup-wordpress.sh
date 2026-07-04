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

# WordPress only allows Application Passwords over HTTPS unless WP_ENVIRONMENT_TYPE is
# 'local' (see wp_is_application_passwords_supported()). Without this, every request
# authenticated with the app password below silently fails with a 401.
docker exec "$CONTAINER" wp config set WP_ENVIRONMENT_TYPE local --allow-root

# WPCode provides the `wpcode` post type that the Loopress plugin's REST snippet
# endpoints read/write; the Loopress plugin provides the endpoints themselves.
# Neither ships with WordPress core, so both must be installed explicitly or
# `/wp-json/loopress/v1/wpcode/*` 404s on a fresh site.
docker exec "$CONTAINER" wp plugin install insert-headers-and-footers --activate --allow-root

LOOPRESS_PLUGIN_ZIP_URL=$(curl -s "https://api.github.com/repos/loopress/loopress/releases" \
  | jq -r '[.[] | select(.tag_name | startswith("wordpress-plugin@"))][0].assets[] | select(.name == "loopress.zip") | .browser_download_url')

if [ -z "$LOOPRESS_PLUGIN_ZIP_URL" ]; then
  echo "Could not find a wordpress-plugin release asset on loopress/loopress" >&2
  exit 1
fi

docker exec "$CONTAINER" wp plugin install "$LOOPRESS_PLUGIN_ZIP_URL" --activate --allow-root

APP_PASSWORD=$(docker exec "$CONTAINER" wp user application-password create admin "Loopress CI" \
  --porcelain --allow-root)

ADDED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Callers that only fetch this script standalone (e.g. the GitLab/CircleCI templates
# curl scripts/ into /tmp without their sibling templates/ directory) must set
# LOOPRESS_CONFIG_TEMPLATE to where they downloaded loopress-config.json themselves.
CONFIG_TEMPLATE="${LOOPRESS_CONFIG_TEMPLATE:-$SCRIPT_DIR/../templates/loopress-config.json}"

mkdir -p ~/.loopress
export SITE_ID WP_HOST WP_PORT APP_PASSWORD ADDED_AT
# Restrict substitution to these variables only — a bare `envsubst` also expands any
# other `$NAME` pattern it finds (e.g. the literal "$schema" JSON key) to an empty string.
envsubst '${SITE_ID} ${WP_HOST} ${WP_PORT} ${APP_PASSWORD} ${ADDED_AT}' \
  < "$CONFIG_TEMPLATE" > ~/.loopress/config.json
