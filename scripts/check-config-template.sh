#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCHEMA="$SCRIPT_DIR/../node_modules/@loopress/cli/schemas/global-config.schema.json"

if [ ! -f "$SCHEMA" ]; then
  echo "Schema not found at $SCHEMA. Run 'npm install' in setup-ci/ first." >&2
  exit 1
fi

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT
# ajv-cli picks its parser (JSON/YAML/JSON5) from the file extension, so the
# rendered file needs a ".json" name: a bare `mktemp` file has none.
RENDERED="$TMP_DIR/loopress-config.json"

SITE_ID=ci ADDED_AT=2024-01-01T00:00:00Z APP_PASSWORD="xxxx xxxx xxxx xxxx xxxx xxxx" WP_HOST=localhost WP_PORT=8080 \
  envsubst '${SITE_ID} ${WP_HOST} ${WP_PORT} ${APP_PASSWORD} ${ADDED_AT}' \
  < "$SCRIPT_DIR/../templates/loopress-config.json" > "$RENDERED"

npx --yes ajv-cli validate -s "$SCHEMA" -d "$RENDERED" --strict=true

# The CLI refuses an environment without a "type" (assertTyped), but its schema
# keeps the field optional for hand-written configs, so the validation above
# passes without it. Fail here rather than in users' CI.
UNTYPED=$(jq -r '[.projects[].environments | to_entries[] | select((.value.type // "") == "") | .key] | join(", ")' "$RENDERED")
if [ -n "$UNTYPED" ]; then
  echo "Environment(s) without a type in templates/loopress-config.json: $UNTYPED" >&2
  exit 1
fi
