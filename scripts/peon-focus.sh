#!/bin/bash
# peon-focus: Switch to the WezTerm tab/pane that last triggered a PeonPing notification.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/hud-dir.sh"

MARKER="/tmp/peon-ping-last-alert-tty"

if [ ! -f "$MARKER" ]; then
  exit 0
fi

target_tty=$(cat "$MARKER" 2>/dev/null)
[ -z "$target_tty" ] && exit 0

# Match the TTY to a WezTerm pane
pane_info=$(/opt/homebrew/bin/wezterm cli list --format json 2>/dev/null | python3 -c "
import json, sys
target = '$target_tty'
panes = json.load(sys.stdin)
for p in panes:
    if p.get('tty_name') == target:
        print(f\"{p['tab_id']} {p['pane_id']}\")
        break
" 2>/dev/null)

[ -z "$pane_info" ] && exit 0

tab_id="${pane_info%% *}"
pane_id="${pane_info##* }"

/opt/homebrew/bin/wezterm cli activate-tab --tab-id "$tab_id" 2>/dev/null
/opt/homebrew/bin/wezterm cli activate-pane --pane-id "$pane_id" 2>/dev/null

# Optionally bring WezTerm to foreground (pulls across workspaces)
CONFIG="$HUD_DIR/config.json"
activate=$(python3 -c "import json; print(json.load(open('$CONFIG')).get('click_activates_wezterm', True))" 2>/dev/null || echo "True")
[ "$activate" = "True" ] && osascript -e 'tell application "WezTerm" to activate' 2>/dev/null
