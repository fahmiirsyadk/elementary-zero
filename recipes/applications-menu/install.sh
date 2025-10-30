#!/usr/bin/env bash
set -euo pipefail

RECIPE_DIR=$(cd "$(dirname "$0")" && pwd)
WORKDIR="${RECIPE_DIR}/_work"
SRC_DIR="${WORKDIR}/src"
BUILD_DIR="${SRC_DIR}/build"

log() { echo "--- $*"; }

log "Installing to /usr"  
ninja -C "$BUILD_DIR" install

log "Done. Installation complete."

# Restart /usr/bin/io.elementary.wingpanel by killing the process
killall io.elementary.wingpanel
