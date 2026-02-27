#!/usr/bin/env bash
set -euo pipefail

LOCK="/usr/bin/swaylock -f -c 000000"

exec /usr/bin/swayidle -w \
  timeout 600 "$LOCK" \
  timeout 780 '/usr/bin/niri msg action power-off-monitors' \
  resume      '/usr/bin/niri msg action power-on-monitors' \
  timeout 900 '/usr/bin/systemctl suspend' \
  before-sleep "$LOCK"
