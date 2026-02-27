#!/usr/bin/env bash
# ~/.config/waybar/scripts/disk.sh
# Matchar disk_part() i dwm-status.sh
# Outputtar ingenting när disk är OK — visas bara vid varning/kritiskt
# Varning:  >85% använt (< 15% fritt)
# Kritiskt: >95% använt (<  5% fritt)

DISK_WARN=15  # % fritt som triggar varning
DISK_CRIT=5   # % fritt som triggar kritiskt

usage=$(df / 2>/dev/null | awk 'NR==2 {print $5}' | tr -d '%' || echo 0)
free_pct=$((100 - usage))

if [ "$free_pct" -le "$DISK_CRIT" ]; then
  echo $'\u26a0'" Disk: ${free_pct}%"
elif [ "$free_pct" -le "$DISK_WARN" ]; then
  echo $'\u26a0'" Disk: ${free_pct}%"
fi
# Annars: ingen output → modulen döljs automatiskt
