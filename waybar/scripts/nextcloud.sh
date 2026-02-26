#!/usr/bin/env bash
# ~/.config/waybar/scripts/nextcloud.sh
# Matchar nextcloud_part() i dwm-status.sh
# Ikoner:  (online)  (syncing)  (offline)

state="offline"

nc_pid=$(pgrep -x nextcloud 2>/dev/null | head -n1 || true)

if [ -n "$nc_pid" ]; then
  nc_log="$HOME/.local/share/Nextcloud/logs/nextcloud.log"

  if [ -f "$nc_log" ] && [ -r "$nc_log" ]; then
    last_line=$(tail -n 50 "$nc_log" 2>/dev/null | grep -i "sync\|upload\|download" | tail -n1 || true)

    if [ -n "$last_line" ]; then
      if echo "$last_line" | grep -qi "starting\|running\|progress"; then
        state="syncing"
      else
        state="online"
      fi
    else
      state="online"
    fi
  else
    state="online"
  fi
fi

case "$state" in
  offline) echo " offline" ;;
  syncing) echo " syncing" ;;
  *)       echo " online"  ;;
esac
