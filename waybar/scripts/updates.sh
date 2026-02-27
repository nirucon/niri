#!/usr/bin/env bash
# ~/.config/waybar/scripts/updates.sh
# Matchar updates_part() i dwm-status.sh
# Visar:  antal (bara när > 0)
# Waybar kör scriptet var 900:e sekund (cache hanteras av intervallet)

command -v checkupdates >/dev/null 2>&1 || exit 0

count=$(checkupdates 2>/dev/null | wc -l || echo 0)
count=$(echo "$count" | tr -d ' \n')

# Kolla AUR med yay om tillgängligt
if command -v yay >/dev/null 2>&1; then
  aur_count=$(yay -Qua 2>/dev/null | wc -l || echo 0)
  aur_count=$(echo "$aur_count" | tr -d ' \n')
  count=$((count + aur_count))
fi

[ "$count" -gt 0 ] && echo $'\uf303'" $count"
