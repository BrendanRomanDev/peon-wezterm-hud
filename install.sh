#!/bin/bash
# peon-wezterm-hud installer
# Prerequisites: Claude Code, WezTerm, peon-ping
set -euo pipefail

HUD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
PEON_DIR="$CLAUDE_DIR/hooks/peon-ping"
PEON_CONFIG="$PEON_DIR/config.json"

echo "=== peon-wezterm-hud installer ==="
echo "Install dir: $HUD_DIR"
echo ""

# --- Validate prerequisites ---
errors=0
if ! command -v claude &>/dev/null && [ ! -f "$CLAUDE_DIR/settings.json" ]; then
  echo "ERROR: Claude Code not found. Install it first: brew install claude-code"
  errors=1
fi
if ! command -v wezterm &>/dev/null; then
  echo "ERROR: WezTerm not found. Install it first: brew install --cask wezterm"
  errors=1
fi
if [ ! -d "$PEON_DIR" ]; then
  echo "ERROR: peon-ping not found at $PEON_DIR"
  echo "       Install it first: https://github.com/anthropics/peon-ping"
  errors=1
fi
[ "$errors" -gt 0 ] && exit 1

# --- Make scripts executable ---
chmod +x "$HUD_DIR/scripts/"*.sh

# --- Symlink custom overlay into peon-ping ---
OVERLAY_TARGET="$PEON_DIR/scripts/mac-overlay-compact.js"
if [ -L "$OVERLAY_TARGET" ]; then
  echo "Overlay symlink already exists, updating..."
  rm "$OVERLAY_TARGET"
elif [ -f "$OVERLAY_TARGET" ]; then
  echo "Backing up existing overlay to mac-overlay-compact.js.bak"
  mv "$OVERLAY_TARGET" "${OVERLAY_TARGET}.bak"
fi
ln -s "$HUD_DIR/scripts/mac-overlay-compact.js" "$OVERLAY_TARGET"
echo "OK: Overlay symlinked"

# --- Copy /tabn Claude Code command ---
mkdir -p "$CLAUDE_DIR/commands"
cp "$HUD_DIR/tabn-command.md" "$CLAUDE_DIR/commands/tabn.md"
echo "OK: /tabn command installed"

# --- Merge hooks into settings.json ---
SETTINGS="$CLAUDE_DIR/settings.json"
if [ ! -f "$SETTINGS" ]; then
  echo "{}" > "$SETTINGS"
fi

# Use python to safely merge hooks without clobbering existing config
python3 -c "
import json, sys

settings_path = '$SETTINGS'
hud_dir = '$HUD_DIR'

with open(settings_path) as f:
    settings = json.load(f)

hooks = settings.setdefault('hooks', {})

# Hook definitions: (event, matcher, script, timeout, async)
hud_hooks = [
    ('Stop', '', f'{hud_dir}/scripts/peon-alert-marker.sh', 3, True),
    ('Stop', '', f'{hud_dir}/scripts/session-namer.sh', 5, True),
    ('Notification', '', f'{hud_dir}/scripts/peon-alert-marker.sh', 3, True),
    ('PermissionRequest', '', f'{hud_dir}/scripts/peon-alert-marker.sh', 3, True),
    ('PostToolUseFailure', 'Bash', f'{hud_dir}/scripts/peon-alert-marker.sh', 3, True),
]

for event, matcher, command, timeout, is_async in hud_hooks:
    event_hooks = hooks.setdefault(event, [])
    # Find or create the matcher group
    group = None
    for g in event_hooks:
        if g.get('matcher', '') == matcher:
            group = g
            break
    if not group:
        group = {'matcher': matcher, 'hooks': []}
        event_hooks.append(group)
    # Check if this hook already exists
    exists = any(h.get('command') == command for h in group['hooks'])
    if not exists:
        hook = {'type': 'command', 'command': command, 'timeout': timeout}
        if is_async:
            hook['async'] = True
        group['hooks'].append(hook)

with open(settings_path, 'w') as f:
    json.dump(settings, f, indent=2)

print('OK: Claude Code hooks merged into settings.json')
"

# --- Point peon-ping at title-topic.sh so tab titles show "project - topic" ---
if [ -f "$PEON_CONFIG" ]; then
  python3 - "$PEON_CONFIG" "$HUD_DIR/scripts/title-topic.sh" <<'PY'
import json, sys
cfg_path, script_path = sys.argv[1], sys.argv[2]
with open(cfg_path) as f:
    cfg = json.load(f)
existing = cfg.get('notification_title_script')
if existing == script_path:
    print('OK: peon-ping notification_title_script already pointed at title-topic.sh')
else:
    cfg['notification_title_script'] = script_path
    with open(cfg_path, 'w') as f:
        json.dump(cfg, f, indent=2)
    if existing:
        print(f'OK: notification_title_script repointed (was: {existing})')
    else:
        print('OK: notification_title_script set to title-topic.sh')
PY
else
  echo "WARN: $PEON_CONFIG not found — skipping notification_title_script wiring."
  echo "      After peon-ping creates it, add this line manually:"
  echo "        \"notification_title_script\": \"$HUD_DIR/scripts/title-topic.sh\""
fi

echo ""
echo "=== Automated setup complete ==="
echo ""
echo "=== Manual steps remaining ==="
echo ""
echo "1. Add tabn to your shell (add to .zshrc or .bashrc):"
echo ""
echo "   source \"$HUD_DIR/tabn.sh\""
echo ""
echo "2. Add WezTerm snippets to your wezterm.lua:"
echo "   See the files in $HUD_DIR/wezterm-snippets/"
echo ""
echo "   - tab-colors.lua  — Colored tab text (catppuccin palette)"
echo "   - tab-titles.lua  — Smart tab titles (Claude summary + tabn override + cwd)"
echo "   - keybindings.lua — CTRL+CMD+. (focus) and CTRL+CMD+, (recall)"
echo ""
echo "   NOTE: In tab-titles.lua, replace /path/to/peon-wezterm-hud with:"
echo "   $HUD_DIR"
echo ""
echo "3. (Optional) Global hotkeys via skhd — add to your skhdrc:"
echo ""
echo "   ctrl + alt - p : $HUD_DIR/scripts/peon-recall.sh"
echo "   ctrl + alt - 0x2F : $HUD_DIR/scripts/peon-focus.sh"
echo ""
echo "4. Reload WezTerm config: CTRL+SHIFT+R"
echo ""
echo "Done! Start a Claude Code session and watch the magic."
echo ""
echo "Note: HUD_DIR for the overlay is auto-resolved by peon-recall.sh and"
echo "by sourcing scripts/hud-dir.sh. If you invoke mac-overlay-compact.js"
echo "directly outside of peon-ping/peon-recall, export HUD_DIR=$HUD_DIR first."
