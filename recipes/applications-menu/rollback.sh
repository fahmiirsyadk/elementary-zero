#!/usr/bin/env bash
set -euo pipefail

echo "Reinstalling upstream slingshot-launcher (system package)"
if command -v apt >/dev/null 2>&1; then
  sudo apt update -y || true
  sudo apt install -y --reinstall slingshot-launcher || true
fi

echo "Restarting wingpanel"
killall io.elementary.wingpanel 2>/dev/null || true

echo "Rollback complete. Restored upstream slingshot-launcher."


