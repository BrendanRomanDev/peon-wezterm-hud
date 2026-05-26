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
# Read each history line. New schema is tab-separated 4-field:
#   <ts>\t<tty>\t<ntype>\t<title_label>
# Legacy schema was space-separated 3-field:
#   <ts> <tty> <ntype>
# Detect by checking whether the line contains a tab.
while IFS= read -r line; do
  case "$line" in
    *$'\t'*)
      IFS=$'\t' read -r ts tty ntype title_label <<<"$line"
      ;;
    *)
      IFS=' ' read -r ts tty ntype <<<"$line"
      title_label=""
      ;;
  esac
  [ -z "$tty" ] && continue

  # Write slot mapping (1-indexed)
  echo "$((slot + 1)) $tty" >> "$SLOTS_FILE"

  # Resolve tab name from the live pane list (still useful as a fallback and
  # for the click target, even when we have a stored title_label).
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

  # Split the stored title_label into project + topic. title-topic.sh joins
  # them with ' - ' when both are present; emits project alone otherwise.
  topic=""
  project=""
  if [ -n "$title_label" ]; then
    case "$title_label" in
      *" - "*)
        project="${title_label%% - *}"
        topic="${title_label#* - }"
        ;;
      *)
        project="$title_label"
        ;;
    esac
  fi
  # Fallback: project from the live tab name if title-topic wasn't around
  # at fire time (legacy entries) — tab title is usually "<project> - <topic>"
  # too, but we can't trust it to be from the same moment; leave topic empty.
  [ -z "$project" ] && project="$tab_name"

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

  # Topic-first layout: message line shows the topic (what differentiates
  # notifications), subtitle shows "<project> · <age>". When no topic was
  # captured (legacy lines or sessions without a tabn marker), fall back to
  # project as the message line so the recall stack stays useful.
  if [ -n "$topic" ]; then
    msg_line="$topic"
    sub_line="$project · $age"
  else
    msg_line="$project"
    sub_line="$age"
  fi

  HUD_DIR="$HUD_DIR" \
  PEON_CLICK_COMMAND="$HUD_DIR/scripts/peon-focus.sh" \
  osascript -l JavaScript "$OVERLAY" \
    "$msg_line" "$color" "" "$slot" "6" \
    "com.github.wez.wezterm" "0" "$tty" \
    "$sub_line" "top-right" "${ntype:-complete}" "false" "" "false" &

  slot=$((slot + 1))
done < "$TMPLINES"

rm -f "$TMPLINES"
wait
