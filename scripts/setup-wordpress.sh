#!/usr/bin/env bash
set -euo pipefail

WP_PORT="${LOOPRESS_WP_PORT:-8080}"
WP_HOST="${LOOPRESS_WP_HOST:-localhost}"
SITE_ID="${LOOPRESS_SITE_ID:-ci}"
COMPOSE_FILE="${LOOPRESS_COMPOSE_FILE:-/tmp/loopress-compose.yml}"

CONTAINER=$(docker compose -f "$COMPOSE_FILE" ps -q wordpress)

docker exec "$CONTAINER" curl -fsSL -o /usr/local/bin/wp \
  https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
docker exec "$CONTAINER" chmod +x /usr/local/bin/wp

# WP-CLI uses the internal port (80): the external port is not accessible from inside the container.
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

# Only Loopress Full is installed: any other plugin a project depends on (WPCode, ACF, WPForms,
# an SEO plugin...) belongs in its loopress.json, and `lps push` installs it before anything else.
# Preinstalling them here would make every CI site differ from the real one it stands in for.

# Authenticated when a token is available (the GitHub action passes github.token): anonymous
# calls share a 60 requests/hour limit per IP, which shared CI runners regularly exhaust.
LOOPRESS_FULL_PLUGIN_ZIP_URL=$(curl -fsS ${GITHUB_TOKEN:+-H "Authorization: Bearer $GITHUB_TOKEN"} \
  "https://api.github.com/repos/loopress/loopress/releases" \
  | jq -r '[.[] | select(.tag_name | startswith("wordpress-plugin@"))][0].assets[] | select(.name == "loopress-full.zip") | .browser_download_url')

if [ -z "$LOOPRESS_FULL_PLUGIN_ZIP_URL" ]; then
  echo "Could not find a wordpress-plugin release asset on loopress/loopress" >&2
  exit 1
fi

docker exec "$CONTAINER" wp plugin install "$LOOPRESS_FULL_PLUGIN_ZIP_URL" --activate --allow-root
# A throwaway CI site isn't an active install: without this, every run would ping
# api.loopress.dev with a fresh install id. Before the snapshot below, so restores keep it.
docker exec "$CONTAINER" wp option update loopress_usage_stats_enabled 0 --allow-root

APP_PASSWORD=$(docker exec "$CONTAINER" wp user application-password create admin "Loopress CI" \
  --porcelain --allow-root)

# Every wp-cli call above runs via 'docker exec' with no '-u', i.e. as root, while Apache (and
# every Loopress REST write under wp-content/loopress/) serves requests as www-data. Whatever
# those calls created under wp-content is root's: plugin installs, and wp-content/loopress/
# itself, which Loopress Full creates once it is active and wp-cli boots WordPress with it.
# Hence after the last of them, not before the first: run first, it left wp-content/loopress/
# root-owned and every `lps composer push` answered 500 ("Cannot rename ... Permission denied").
docker exec "$CONTAINER" chown -R www-data:www-data /var/www/html/wp-content

# Captures a working site (plugin active, app password already issued) so `restore-wordpress.sh`
# can reset the database between groups of e2e tests without re-running the whole setup above.
# Respawning the Docker stack per group is too slow, but leaving residual state between groups
# (snippets created by one group leaking into the next) makes tests order-dependent and flaky.
SNAPSHOT_PATH="${LOOPRESS_SNAPSHOT_PATH:-/tmp/loopress-snapshot-clean.sql}"
# Dumped from the mysql container itself: it ships the client tools, so the wordpress container
# needs no mysql client installed (and no TLS workaround for mysql:8.0's self-signed cert).
docker compose -f "$COMPOSE_FILE" exec -T -e MYSQL_PWD=loopress mysql \
  mysqldump -uroot wordpress > "$SNAPSHOT_PATH"

ADDED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Callers that only fetch this script standalone (e.g. the GitLab template
# curl scripts/ into /tmp without their sibling templates/ directory) must set
# LOOPRESS_CONFIG_TEMPLATE to where they downloaded loopress-config.json themselves.
CONFIG_TEMPLATE="${LOOPRESS_CONFIG_TEMPLATE:-$SCRIPT_DIR/../templates/loopress-config.json}"

# @loopress/cli now sources its config dir from oclif's native, per-platform default
# (oclif.dirname "loopress" in its package.json) instead of a hardcoded ~/.loopress, so the
# seed file must land wherever `lps` will actually look for it: $XDG_CONFIG_HOME/loopress, or
# ~/.config/loopress if that's unset (see @oclif/core's Config#dir('config')).
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/loopress"

mkdir -p "$CONFIG_DIR"
export SITE_ID WP_HOST WP_PORT APP_PASSWORD ADDED_AT
# Restrict substitution to these variables only: a bare `envsubst` also expands any
# other `$NAME` pattern it finds (e.g. the literal "$schema" JSON key) to an empty string.
envsubst '${SITE_ID} ${WP_HOST} ${WP_PORT} ${APP_PASSWORD} ${ADDED_AT}' \
  < "$CONFIG_TEMPLATE" > "$CONFIG_DIR/config.json"
