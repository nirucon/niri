#!/usr/bin/env bash
# ~/.config/waybar/scripts/clipboard.sh
# Matchar clipboard_part() i dwm-status.sh
# Format:  (ingen aktivitet) |  3 (textklipp) |  3/2 (text + screenshots)

text_count=0
screenshot_count=0

[ -f "$HOME/.cache/clip-text.log" ] && \
  text_count=$(wc -l < "$HOME/.cache/clip-text.log" 2>/dev/null || echo 0)

[ -d "$HOME/Pictures/Screenshots" ] && \
  screenshot_count=$(find -L "$HOME/Pictures/Screenshots" -maxdepth 1 -type f -name "*.png" -mtime -1 2>/dev/null | wc -l)

if [ "$text_count" -eq 0 ] && [ "$screenshot_count" -eq 0 ]; then
  echo ""
elif [ "$screenshot_count" -eq 0 ]; then
  echo " $text_count"
else
  echo " $text_count/$screenshot_count"
fi
