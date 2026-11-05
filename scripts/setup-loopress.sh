#!/usr/bin/env bash
set -euo pipefail

# LOOPRESS_INSTALL_CLI=false skips the install (e.g. a pipeline that builds the CLI from source).
if [ "${LOOPRESS_INSTALL_CLI:-true}" = "false" ]; then
  echo "LOOPRESS_INSTALL_CLI=false, skipping @loopress/cli install"
  exit 0
fi

npm install -g @loopress/cli
