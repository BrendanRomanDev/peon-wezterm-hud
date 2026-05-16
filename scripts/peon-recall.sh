#!/bin/bash
# peon-recall: Re-display recent PeonPing notifications as stacked compact overlays.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/hud-dir.sh"

HISTORY="/tmp/peon-ping-alert-history"
OVERLAY="$HUD_DIR/scripts/mac-overlay-compact.js"
CONFIG="$HUD_DIR/config.json"
SLOTS_FILE="/tmp/peon-ping-recall-slots"

[ -f "$HISTORY" ] || exit 0
[ -f "$OVERLAY" ] || exit 0

# Read recall_count from config (default 5)
COUNT=5
if [ -f "$CONFIG" ]; then
  COUNT=$(python3 -c "import json; print(json.load(open('$CONFIG')).get('recall_count', 5))" 2>/dev/null || echo 5)
fi

# Fetch pane list once
PANE_JSON=$(/opt/homebrew/bin/wezterm cli list --format json 2>/dev/null || echo "[]")

# Read history (most recent first) into temp file
TMPLINES=$(mktemp)
tail -r "$HISTORY" | head -"$COUNT" > "$TMPLINES"

# Clear slot mapping
> "$SLOTS_FILE"

slot=0
while IFS=' ' read -r ts tty ntype; do
  [ -z "$tty" ] && continue

  # Write slot mapping (1-indexed)
  echo "$((slot + 1)) $tty" >> "$SLOTS_FILE"

  # Get tab name
  tab_name=$(echo "$PANE_JSON" | python3 -c "
import json, sys
target = '$tty'
panes = json.load(sys.stdin)
for p in panes:
    if p.get('tty_name') == target:
        print(p.get('tab_title', 'Claude'))
        break
" 2>/dev/null)
  [ -z "$tab_name" ] && tab_name="Claude"

  # Map type to color
  color="blue"
  case "$ntype" in
    permission) color="red" ;;
    error) color="red" ;;
    idle) color="yellow" ;;
    question) color="yellow" ;;
  esac

  # Time ago
  now=$(date +%s)
  ago=$(( now - ts ))
  if [ "$ago" -lt 60 ]; then
    age="${ago}s ago"
  elif [ "$ago" -lt 3600 ]; then
    age="$(( ago / 60 ))m ago"
  else
    age="$(( ago / 3600 ))h ago"
  fi

  HUD_DIR="$HUD_DIR" \
  PEON_CLICK_COMMAND="$HUD_DIR/scripts/peon-focus.sh" \
  osascript -l JavaScript "$OVERLAY" \
    "$tab_name" "$color" "" "$slot" "6" \
    "com.github.wez.wezterm" "0" "$tty" \
    "$age" "top-right" "${ntype:-complete}" "false" "" "false" &

  slot=$((slot + 1))
done < "$TMPLINES"

rm -f "$TMPLINES"
wait
