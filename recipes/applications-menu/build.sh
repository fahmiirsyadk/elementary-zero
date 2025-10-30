#!/usr/bin/env bash
set -euo pipefail

RECIPE_DIR=$(cd "$(dirname "$0")" && pwd)
WORKDIR="${RECIPE_DIR}/_work"
SRC_DIR="${WORKDIR}/src"
BUILD_DIR="${SRC_DIR}/build"

log() { echo "--- $*"; }

rm -rf "$WORKDIR"
mkdir -p "$WORKDIR" "$SRC_DIR"

UPSTREAM_GIT=$(grep -E '^\s*git:' "$RECIPE_DIR/recipe.yaml" | awk '{print $2}')
UPSTREAM_BRANCH=$(grep -E '^\s*branch:' "$RECIPE_DIR/recipe.yaml" | awk '{print $2}')
RECIPE_SHA=$(grep -E '^\s*pinned_sha:' "$RECIPE_DIR/recipe.yaml" | awk '{print $2}')
RECIPE_SHA="${RECIPE_SHA%\"}"; RECIPE_SHA="${RECIPE_SHA#\"}"

if [[ ! -d "$SRC_DIR/.git" ]]; then
  log "Cloning $UPSTREAM_GIT"
  git clone "$UPSTREAM_GIT" "$SRC_DIR"
fi

pushd "$SRC_DIR" >/dev/null
  log "Syncing upstream $UPSTREAM_BRANCH"
  git fetch origin "$UPSTREAM_BRANCH"
  git checkout "$UPSTREAM_BRANCH"
  git pull --ff-only origin "$UPSTREAM_BRANCH"
  if [[ -n "$RECIPE_SHA" && "$RECIPE_SHA" != '""' && "$RECIPE_SHA" != '"' && "$RECIPE_SHA" != "''" ]]; then
    git checkout "$RECIPE_SHA"
  fi

  git reset --hard HEAD
  git clean -fdx
  for p in "$RECIPE_DIR"/patches/*.patch; do
    log "Applying patch: $p"
    if git apply --check "$p"; then
      git apply "$p"
    else
      log "Patch did not apply cleanly, retrying with --3way..."
      if ! git apply --3way "$p"; then
        echo "ERROR: Patch failed with --3way. Aborting." >&2
        echo "       Rebase the patch or pin a compatible commit (pinned_sha)." >&2
        exit 1
      fi
    fi
  done

  log "Configuring with Meson"
  rm -rf "$BUILD_DIR"
  meson setup "$BUILD_DIR"
  log "Compiling with Ninja"
  ninja -C "$BUILD_DIR"

popd >/dev/null

log "Done."


