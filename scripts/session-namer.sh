#!/bin/bash
# session-namer: Sets the WezTerm tab name based on Claude Code's conversation topic.
# Fires once per session (on first Stop event), then never again unless topic changes drastically.
# Uses the same tabn marker file mechanism as the shell function.
set -uo pipefail

# Claude Code 2.1.x passes hook data as JSON on stdin (`hook_event_name`);
# older convention used a CLAUDE_HOOK_EVENT env var. Buffer stdin once so
# we can both gate on the event and pass the same payload to the parsers
# below.
STDIN_JSON=""
if [ ! -t 0 ]; then
  STDIN_JSON=$(head -c 65536 2>/dev/null || true)
fi
event="${CLAUDE_HOOK_EVENT:-}"
if [ -z "$event" ] && [ -n "$STDIN_JSON" ]; then
  event=$(printf '%s' "$STDIN_JSON" | python3 -c "
import json, sys
try:
    print(json.loads(sys.stdin.read()).get('hook_event_name', ''))
except Exception:
    pass
" 2>/dev/null)
fi

# Only fire on Stop (task complete) — that's when we have context
[ "$event" = "Stop" ] || exit 0

# --- Tmux path: rename tmux window directly ---
if [ -n "${TMUX:-}" ]; then
  TMUX_WIN_ID=$(tmux display-message -p '#{window_id}' 2>/dev/null || true)
  SESSION_MARKER="/tmp/peon-session-named-tmux-${TMUX_WIN_ID}"

  # One-shot per window
  [ -f "$SESSION_MARKER" ] && exit 0

  input="$STDIN_JSON"

  topic=$(python3 -c "
import json, sys

data = {}
raw = sys.argv[1] if len(sys.argv) > 1 else ''
if raw:
    try:
        data = json.loads(raw)
    except:
        pass

summary = ''
for key in ('last_assistant_message', 'message', 'transcript_summary', 'prompt_response', 'stop_ts_reason'):
    val = data.get(key, '')
    if isinstance(val, str) and val.strip():
        summary = val.strip()
        break

if not summary:
    sys.exit(1)

first_line = summary[:200].split('\n')[0].split('. ')[0]
for prefix in ('I ', 'Let me ', 'Here ', 'OK ', 'Sure ', 'Got it', 'The ', 'This '):
    if first_line.startswith(prefix):
        first_line = first_line[len(prefix):]
        break

if len(first_line) > 30:
    first_line = first_line[:30].rsplit(' ', 1)[0]

first_line = first_line.strip(' .,;:-')
if first_line:
    print(first_line)
else:
    sys.exit(1)
" "$input" 2>/dev/null)

  [ -z "$topic" ] && exit 0

  tmux rename-window "$topic"
  touch "$SESSION_MARKER"
  exit 0
fi
# --- End tmux path ---

# Resolve WEZTERM_PANE — hooks may not inherit it from the terminal env.
# Walk the process tree to find the TTY, then match it to a WezTerm pane.
PANE_ID="${WEZTERM_PANE:-}"
if [ -z "$PANE_ID" ]; then
  # Find our TTY by walking the process tree
  walk_pid="$PPID"
  last_tty=""
  while [ "$walk_pid" -gt 1 ] 2>/dev/null; do
    walk_tty=$(ps -p "$walk_pid" -o tty= 2>/dev/null | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' || true)
    if [ -n "$walk_tty" ] && [ "$walk_tty" != "??" ]; then
      last_tty="/dev/$walk_tty"
    fi
    walk_pid=$(ps -p "$walk_pid" -o ppid= 2>/dev/null | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' || true)
  done
  # Match TTY to WezTerm pane
  if [ -n "$last_tty" ]; then
    PANE_ID=$(/opt/homebrew/bin/wezterm cli list --format json 2>/dev/null | python3 -c "
import json, sys
target = '$last_tty'
panes = json.load(sys.stdin)
for p in panes:
    if p.get('tty_name') == target:
        print(p['pane_id'])
        break
" 2>/dev/null)
  fi
fi

[ -n "$PANE_ID" ] || exit 0

MARKER="/tmp/wezterm-tabn-${PANE_ID}"
SESSION_MARKER="/tmp/peon-session-named-${PANE_ID}"

# If we've already named this session, skip (one-shot per pane)
[ -f "$SESSION_MARKER" ] && exit 0

# Try to get a topic name. Strategy:
# 1. Use the buffered hook stdin (Claude Code event data with conversation context)
# 2. Fallback: read the WezTerm pane title (Claude Code sets this to conversation summary)
input="$STDIN_JSON"

topic=$(python3 -c "
import json, sys, subprocess

data = {}
raw = sys.argv[1] if len(sys.argv) > 1 else ''
pane_id = sys.argv[2] if len(sys.argv) > 2 else ''

if raw:
    try:
        data = json.loads(raw)
    except:
        pass

# Strategy 1: event data
summary = ''
for key in ('last_assistant_message', 'message', 'transcript_summary', 'prompt_response', 'stop_ts_reason'):
    val = data.get(key, '')
    if isinstance(val, str) and val.strip():
        summary = val.strip()
        break

# Strategy 2: WezTerm pane title (Claude Code sets this)
if not summary and pane_id:
    try:
        r = subprocess.run(['/opt/homebrew/bin/wezterm', 'cli', 'list', '--format', 'json'],
                          capture_output=True, text=True, timeout=3)
        panes = json.loads(r.stdout)
        for p in panes:
            if str(p.get('pane_id')) == pane_id:
                title = p.get('title', '')
                # Strip PeonPing markers
                import re
                title = re.sub(r'^[^\x20-\x7e]+\s*', '', title)
                # Strip 'project: status' suffix
                title = re.sub(r':\s*(done|working|ready|needs approval|question)\s*$', '', title, flags=re.I)
                if title.strip():
                    summary = title.strip()
                break
    except:
        pass

if not summary:
    sys.exit(1)

# Trim to a clean ~30 char topic
first_line = summary[:200].split('\n')[0].split('. ')[0]
for prefix in ('I ', 'Let me ', 'Here ', 'OK ', 'Sure ', 'Got it', 'The ', 'This '):
    if first_line.startswith(prefix):
        first_line = first_line[len(prefix):]
        break

if len(first_line) > 30:
    first_line = first_line[:30].rsplit(' ', 1)[0]

first_line = first_line.strip(' .,;:-')
if first_line:
    print(first_line)
else:
    sys.exit(1)
" "$input" "$PANE_ID" 2>/dev/null)

[ -z "$topic" ] && exit 0

# Write the tabn marker (WezTerm's update-status handler picks this up)
printf '%s' "$topic" > "$MARKER"

# Mark this session as named so we don't overwrite
touch "$SESSION_MARKER"
