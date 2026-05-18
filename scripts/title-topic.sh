#!/bin/bash
# title-topic: peon-ping notification_title_script hook.
# Returns "<project> - <topic>" if session-namer has identified a topic for
# this WezTerm pane, otherwise just "<project>". Peon-ping sanitizes the
# return value to [a-zA-Z0-9 ._-]; colons/parens/slashes get stripped.
#
# Wired in via ~/.claude/hooks/peon-ping/config.json:
#   "notification_title_script": "<absolute path to this file>"
# install.sh sets this automatically for new installs.
set -uo pipefail

cwd="${PEON_CWD:-$PWD}"

# Project name: prefer git repo name, fall back to cwd basename.
# Strip leading dot from dotdir names so ~/.dotfiles renders as "dotfiles".
project=$(cd "$cwd" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null | xargs -I{} basename {} 2>/dev/null)
[ -z "$project" ] && project=$(basename "$cwd" 2>/dev/null)
[ -z "$project" ] && project="claude"
project="${project#.}"

# Topic: written by session-namer.sh into /tmp/wezterm-tabn-<pane_id>.
# Locate the current pane by walking our process tree to the TTY, then
# matching that TTY to a WezTerm pane.
topic=""
walk_pid="$PPID"
last_tty=""
while [ "$walk_pid" -gt 1 ] 2>/dev/null; do
  walk_tty=$(ps -p "$walk_pid" -o tty= 2>/dev/null | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' || true)
  if [ -n "$walk_tty" ] && [ "$walk_tty" != "??" ]; then
    last_tty="/dev/$walk_tty"
  fi
  walk_pid=$(ps -p "$walk_pid" -o ppid= 2>/dev/null | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' || true)
done

if [ -n "$last_tty" ] && command -v /opt/homebrew/bin/wezterm >/dev/null 2>&1; then
  pane_id=$(/opt/homebrew/bin/wezterm cli list --format json 2>/dev/null | python3 -c "
import json, sys
target = '$last_tty'
try:
    for p in json.load(sys.stdin):
        if p.get('tty_name') == target:
            print(p.get('pane_id', ''))
            break
except Exception:
    pass
" 2>/dev/null)
  if [ -n "$pane_id" ] && [ -f "/tmp/wezterm-tabn-$pane_id" ]; then
    topic=$(head -c 200 "/tmp/wezterm-tabn-$pane_id" 2>/dev/null | tr -d '\n\r')
  fi
fi

if [ -n "$topic" ]; then
  printf '%s - %s' "$project" "$topic"
else
  printf '%s' "$project"
fi
