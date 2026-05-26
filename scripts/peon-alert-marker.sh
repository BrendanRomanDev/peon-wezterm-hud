#!/bin/bash
# Write a marker with the current session's TTY so peon-focus.sh can
# switch to the correct WezTerm tab. Runs as a Claude Code hook alongside
# PeonPing — never touched by PeonPing updates.
set -uo pipefail

# shellcheck source=hud-dir.sh
source "$(dirname "${BASH_SOURCE[0]}")/hud-dir.sh"

# Claude Code 2.1.x passes hook event data as JSON on stdin with
# `hook_event_name`. Older convention used a CLAUDE_HOOK_EVENT env var;
# keep that as a fallback so this script survives version drift.
event="${CLAUDE_HOOK_EVENT:-}"
stdin_json=""
if [ -z "$event" ] && [ ! -t 0 ]; then
  stdin_json=$(head -c 65536 2>/dev/null || true)
  if [ -n "$stdin_json" ]; then
    event=$(printf '%s' "$stdin_json" | python3 -c "
import json, sys
try:
    print(json.loads(sys.stdin.read()).get('hook_event_name', ''))
except Exception:
    pass
" 2>/dev/null)
  fi
fi

# Only write for events that actually produce a notification
case "$event" in
  Stop|Notification|PermissionRequest|PostToolUseFailure) ;;
  *) exit 0 ;;
esac

# Walk the process tree to find the terminal TTY (same logic as PeonPing)
walk_pid="$PPID"
last_tty=""
while [ "$walk_pid" -gt 1 ] 2>/dev/null; do
  walk_tty=$(ps -p "$walk_pid" -o tty= 2>/dev/null | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' || true)
  if [ -n "$walk_tty" ] && [ "$walk_tty" != "??" ]; then
    last_tty="/dev/$walk_tty"
  fi
  walk_pid=$(ps -p "$walk_pid" -o ppid= 2>/dev/null | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' || true)
done

[ -n "$last_tty" ] && printf '%s' "$last_tty" > /tmp/peon-ping-last-alert-tty 2>/dev/null

# Append to recall history so ctrl+cmd+, can re-display recent notifications.
# Format: <unix_timestamp>\t<tty>\t<notification_type>\t<title_label>
#   - Tab-separated so title_label can contain spaces/punctuation safely.
#   - title_label is title-topic.sh's output captured at notification-fire time
#     (typically "<project> - <topic>" or just "<project>"). peon-recall.sh
#     splits on " - " to render topic-first with project as caption.
#   - Legacy lines without title_label are tolerated by peon-recall (empty topic).
if [ -n "$last_tty" ]; then
  case "$event" in
    Stop)               ntype="complete" ;;
    Notification)       ntype="question" ;;
    PermissionRequest)  ntype="permission" ;;
    PostToolUseFailure) ntype="error" ;;
    *)                  ntype="complete" ;;
  esac

  # Capture topic label via title-topic.sh. Pipe the buffered stdin JSON in
  # so title-topic can read the same Claude event payload if it ever needs to.
  # Strip any embedded tabs/newlines defensively so the record stays one line.
  title_label=""
  if [ -x "$HUD_DIR/scripts/title-topic.sh" ]; then
    title_label=$(printf '%s' "$stdin_json" | "$HUD_DIR/scripts/title-topic.sh" 2>/dev/null \
                  | tr -d '\t\n' | head -c 240)
  fi

  printf '%s\t%s\t%s\t%s\n' "$(date +%s)" "$last_tty" "$ntype" "$title_label" \
    >> /tmp/peon-ping-alert-history 2>/dev/null
fi

# If inside tmux, also write session:window for tmux-aware focus
if [ -n "${TMUX:-}" ]; then
  tmux_target=$(tmux display-message -p '#{session_name}:#{window_index}' 2>/dev/null || true)
  [ -n "$tmux_target" ] && printf '%s' "$tmux_target" > /tmp/peon-ping-last-alert-tmux 2>/dev/null
fi
