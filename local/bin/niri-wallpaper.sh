#!/bin/bash

WALLPAPER_DIR="$HOME/Pictures/Wallpapers"
FALLBACK_COLOR="#0f0f10"

# Hitta alla bildfiler
mapfile -t IMAGES < <(find "$WALLPAPER_DIR" -maxdepth 1 -type f \
  \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp" \) 2>/dev/null)

if [[ ${#IMAGES[@]} -gt 0 ]]; then
  RANDOM_IMG="${IMAGES[RANDOM % ${#IMAGES[@]}]}"
  exec swaybg -m fill -i "$RANDOM_IMG"
else
  exec swaybg -c "$FALLBACK_COLOR"
fi
