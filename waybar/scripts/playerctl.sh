#!/usr/bin/env bash
# ~/.config/waybar/scripts/playerctl.sh
# Matchar music_part() i dwm-status.sh
# Visar: ♫ Artist - Titel (bara när Playing, max 40 tecken)
# Hanterar Spotify, spotifyd, mpv, cmus m.fl.

command -v playerctl >/dev/null 2>&1 || exit 0

# Hitta första spelare som faktiskt spelar
# Itererar alla tillgängliga spelare (hanterar Spotify's privacyläge bättre)
status=""
title=""
artist=""

while IFS= read -r player; do
  s=$(playerctl --player="$player" status 2>/dev/null || true)
  if [ "$s" = "Playing" ]; then
    t=$(playerctl --player="$player" metadata title 2>/dev/null | \
        sed 's/^[[:space:]]*//;s/[[:space:]]*$//' || true)
    # Spotify i privacy-mode returnerar tom titel — hoppa över
    [ -z "$t" ] && continue
    a=$(playerctl --player="$player" metadata artist 2>/dev/null | \
        sed 's/^[[:space:]]*//;s/[[:space:]]*$//' || true)
    status="Playing"
    title="$t"
    artist="$a"
    break
  fi
done < <(playerctl -l 2>/dev/null || true)

[ "$status" != "Playing" ] && exit 0
[ -z "$title" ] && exit 0

if [ -n "$artist" ]; then
  out="$artist - $title"
else
  out="$title"
fi

[ ${#out} -gt 40 ] && out="${out:0:37}..."

echo "♫ $out"
