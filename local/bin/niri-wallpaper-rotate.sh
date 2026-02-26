#!/usr/bin/env bash
set -euo pipefail

WALLDIR="${HOME}/Pictures/Wallpapers"
FALLBACK_COLOR="#0f0f10"

# Pick a random image (common extensions)
mapfile -t imgs < <(find "$WALLDIR" -type f \( \
  -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp" \
\) | sort)

if [ ${#imgs[@]} -eq 0 ]; then
  echo "No wallpapers found in: $WALLDIR" >&2
  exit 1
fi

img="${imgs[RANDOM % ${#imgs[@]}]}"

# Restart swaybg with the chosen wallpaper
pkill -x swaybg 2>/dev/null || true
nohup swaybg -i "$img" -m fill -c "$FALLBACK_COLOR" >/dev/null 2>&1 &
disown
