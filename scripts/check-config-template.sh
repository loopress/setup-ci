#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCHEMA="$SCRIPT_DIR/../node_modules/@loopress/cli/global-config.schema.json"

if [ ! -f "$SCHEMA" ]; then
  echo "Schema not found at $SCHEMA. Run 'npm install' in setup-ci/ first." >&2
  exit 1
fi

RENDERED=$(mktemp)
trap 'rm -f "$RENDERED"' EXIT

SITE_ID=ci ADDED_AT=2024-01-01T00:00:00Z APP_PASSWORD="xxxx xxxx xxxx xxxx xxxx xxxx" WP_HOST=localhost WP_PORT=8080 \
  envsubst '${SITE_ID} ${WP_HOST} ${WP_PORT} ${APP_PASSWORD} ${ADDED_AT}' \
  < "$SCRIPT_DIR/../templates/loopress-config.json" > "$RENDERED"

npx --yes ajv-cli validate -s "$SCHEMA" -d "$RENDERED" --strict=true
