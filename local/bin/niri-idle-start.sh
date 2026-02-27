#!/usr/bin/env bash
set -euo pipefail
sleep 10
pgrep -x swayidle >/dev/null 2>&1 && exit 0
exec /home/niru/.local/bin/niri-idle.sh
