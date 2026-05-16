#!/bin/bash
# session-namer: Sets the WezTerm tab name based on Claude Code's conversation topic.
# Fires once per session (on first Stop event), then never again unless topic changes drastically.
set -uo pipefail

# Only fire on Stop (task complete) — that's when we have context
event="${CLAUDE_HOOK_EVENT:-}"
[ "$event" = "Stop" ] || exit 0

# --- Tmux path: rename tmux window directly ---
if [ -n "${TMUX:-}" ]; then
  TMUX_WIN_ID=$(tmux display-message -p '#{window_id}' 2>/dev/null || true)
  SESSION_MARKER="/tmp/peon-session-named-tmux-${TMUX_WIN_ID}"

  [ -f "$SESSION_MARKER" ] && exit 0

  input=""
  if [ ! -t 0 ]; then
    input=$(head -c 10000 2>/dev/null || true)
  fi

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

# Resolve WEZTERM_PANE
PANE_ID="${WEZTERM_PANE:-}"
if [ -z "$PANE_ID" ]; then
  walk_pid="$PPID"
  last_tty=""
  while [ "$walk_pid" -gt 1 ] 2>/dev/null; do
    walk_tty=$(ps -p "$walk_pid" -o tty= 2>/dev/null | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' || true)
    if [ -n "$walk_tty" ] && [ "$walk_tty" != "??" ]; then
      last_tty="/dev/$walk_tty"
    fi
    walk_pid=$(ps -p "$walk_pid" -o ppid= 2>/dev/null | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' || true)
  done
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

[ -f "$SESSION_MARKER" ] && exit 0

input=""
if [ ! -t 0 ]; then
  input=$(head -c 10000 2>/dev/null || true)
fi

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

summary = ''
for key in ('last_assistant_message', 'message', 'transcript_summary', 'prompt_response', 'stop_ts_reason'):
    val = data.get(key, '')
    if isinstance(val, str) and val.strip():
        summary = val.strip()
        break

if not summary and pane_id:
    try:
        r = subprocess.run(['/opt/homebrew/bin/wezterm', 'cli', 'list', '--format', 'json'],
                          capture_output=True, text=True, timeout=3)
        panes = json.loads(r.stdout)
        for p in panes:
            if str(p.get('pane_id')) == pane_id:
                title = p.get('title', '')
                import re
                title = re.sub(r'^[^\x20-\x7e]+\s*', '', title)
                title = re.sub(r':\s*(done|working|ready|needs approval|question)\s*$', '', title, flags=re.I)
                if title.strip():
                    summary = title.strip()
                break
    except:
        pass

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
" "$input" "$PANE_ID" 2>/dev/null)

[ -z "$topic" ] && exit 0

printf '%s' "$topic" > "$MARKER"
touch "$SESSION_MARKER"
