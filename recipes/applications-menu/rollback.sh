#!/usr/bin/env bash
set -euo pipefail

echo "Reinstalling upstream slingshot-launcher (system package)"
if command -v apt >/dev/null 2>&1; then
  sudo apt update -y || true
  sudo apt install -y --reinstall slingshot-launcher || true
fi

echo "Restarting wingpanel"
# Try systemd user unit names first
systemctl --user restart io.elementary.wingpanel.service 2>/dev/null || \
systemctl --user restart wingpanel.service 2>/dev/null || {
  # Fallback to binary if no systemd user unit present
  killall io.elementary.wingpanel 2>/dev/null || true
  if command -v io.elementary.wingpanel >/dev/null 2>&1; then
    nohup io.elementary.wingpanel >/dev/null 2>&1 &
  elif [ -x /usr/bin/io.elementary.wingpanel ]; then
    nohup /usr/bin/io.elementary.wingpanel >/dev/null 2>&1 &
  fi
}

echo "Rollback complete. Restored upstream slingshot-launcher."


