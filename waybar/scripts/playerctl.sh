#!/usr/bin/env bash
# ~/.config/waybar/scripts/playerctl.sh
# Matchar music_part() i dwm-status.sh
# Visar: ♫ Artist - Titel (bara när Playing, max 40 tecken)

command -v playerctl >/dev/null 2>&1 || exit 0

status=$(playerctl status 2>/dev/null || true)
[ "$status" != "Playing" ] && exit 0

title=$(playerctl metadata title 2>/dev/null | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' || true)
[ -z "$title" ] && exit 0

artist=$(playerctl metadata artist 2>/dev/null | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' || true)

if [ -n "$artist" ]; then
  out="$artist - $title"
else
  out="$title"
fi

[ ${#out} -gt 40 ] && out="${out:0:37}..."

echo "♫ $out"
