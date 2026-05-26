# peon-wezterm-hud

A WezTerm HUD layer for [peon-ping](https://github.com/anthropics/peon-ping) that adds per-tab color identity, smart tab naming, click-to-focus notifications, and notification recall.

<img width="486" height="300" alt="image" src="https://github.com/user-attachments/assets/4d249d59-1ce8-4c7c-baa6-d092d8d5ea59" />

## What You Get

- **Colored tabs** — Each WezTerm tab gets a unique color from the catppuccin-mocha palette (mauve, blue, green, peach, pink, teal, yellow, sapphire)
- **Smart tab titles** — Claude Code conversations auto-name tabs based on what you're working on. Notification titles render as `<project> - <topic>` (e.g. `dotfiles - Understand git dirty status`)
- **Per-tab notification dots** — The accent dot on each notification matches the originating tab's color
- **Click-to-focus** — Click a notification to jump to WezTerm and the correct tab (even across workspaces)
- **Notification recall** — CTRL+CMD+, to resurface recent notifications as a stack
- **Manual tab rename** — `tabn "name"` in shell or `/tabn name` in Claude Code
- **Tmux support** — `tabn` and session-namer work in tmux too

## Prerequisites

- [WezTerm](https://wezfurlong.org/wezterm/)
- [Claude Code](https://claude.ai/code) (`brew install claude-code`)
- [peon-ping](https://github.com/anthropics/peon-ping) (installed at `~/.claude/hooks/peon-ping/`)
- Python 3 (for hook scripts)

## Install

```bash
git clone <this-repo> ~/.peon-wezterm-hud
cd ~/.peon-wezterm-hud
./install.sh
```

The install script will:
1. Symlink the custom overlay into peon-ping's scripts directory
2. Install the `/tabn` Claude Code command
3. Merge notification hooks into your Claude Code `settings.json`
4. Point peon-ping's `notification_title_script` at `scripts/title-topic.sh` so notification titles render as `<project> - <topic>`
5. Print manual steps for WezTerm config and shell setup

## Manual Steps (after install.sh)

### 1. Shell function

Add to your `.zshrc` or `.bashrc`:

```bash
source ~/.peon-wezterm-hud/tabn.sh
```

### 2. WezTerm config

Merge the snippets from `wezterm-snippets/` into your `wezterm.lua`:

| File | What it does |
|------|-------------|
| `tab-colors.lua` | Colored tab text using catppuccin palette |
| `tab-titles.lua` | Smart tab naming (Claude summary > tabn override > cwd) |
| `keybindings.lua` | CTRL+CMD+. (focus) and CTRL+CMD+, (recall) |

In `tab-titles.lua`, replace `/path/to/peon-wezterm-hud` with your actual install path.

### 3. Global hotkeys (optional — recommended)

By default, the focus and recall hotkeys (`ctrl+cmd+.` and `ctrl+cmd+,`) only work when WezTerm is focused. If you want them to work **from any app or workspace** — e.g. you hear a notification while in your browser and want to jump straight to the right tab — you can add [skhd](https://github.com/koekeishiya/skhd) as a global hotkey layer.

**Why this matters:** Without global hotkeys, you have to manually switch to WezTerm first, then use the hotkey. With skhd, the same hotkey works everywhere — it pulls WezTerm to the foreground and lands on the correct tab in one keystroke.

#### Setup

1. Install skhd:

```bash
brew install koekeishiya/formulae/skhd
skhd --start-service
```

2. Create or edit `~/.config/skhd/skhdrc` and add:

```
# peon-wezterm-hud: global notification hotkeys
# These mirror WezTerm's native keybindings but work system-wide.
# "WezTerm" ~ passes the keypress through when WezTerm is focused.
# * catches all other apps and runs the script.

# recall recent notifications (ctrl+cmd+,)
ctrl + cmd - 0x2B [
  "WezTerm" ~
  *           : ~/.peon-wezterm-hud/scripts/peon-recall.sh
]

# focus last alerting tab (ctrl+cmd+.)
ctrl + cmd - 0x2F [
  "WezTerm" ~
  *           : ~/.peon-wezterm-hud/scripts/peon-focus.sh
]
```

3. Reload skhd:

```bash
skhd --restart-service
```

#### How it works

| Context | `ctrl+cmd+.` handled by | Result |
|---------|------------------------|--------|
| WezTerm focused | WezTerm (native) | Switches to alerting tab |
| Any other app focused | skhd (global) | Activates WezTerm + switches to alerting tab |
| Different macOS workspace | skhd (global) | Pulls you to WezTerm's workspace + correct tab |

One set of hotkeys, zero context switching. skhd's `"WezTerm" ~` filter means the bindings are excluded when WezTerm is the frontmost app, so the native WezTerm handlers always take priority — no conflicts.

## Config

Edit `config.json`:

```json
{
  "recall_count": 5,
  "click_activates_wezterm": true,
  "tab_palette": [
    "#cba6f7",
    "#89b4fa",
    "#a6e3a1",
    "#fab387",
    "#f38ba8",
    "#94e2d5",
    "#f9e2af",
    "#74c7ec"
  ]
}
```

- `recall_count` — How many recent notifications to show on recall
- `click_activates_wezterm` — Whether clicking a notification brings WezTerm to the foreground (set `false` to only highlight the tab without switching workspaces)
- `tab_palette` — Array of hex colors for per-tab identity. The default is catppuccin-mocha accents. Swap these out to match your terminal theme. Both the WezTerm tab text color and the notification accent bar use this palette. Supports any number of colors (cycles when you have more tabs than colors).

## How It Works

```
Claude Code fires hook events (Stop, Notification, PermissionRequest, etc.)
    |
    ├── peon-ping (peon.sh) → sound + overlay notification
    │                             |
    │                             └── mac-overlay-compact.js
    │                                   ├── resolves TTY → tab via wezterm cli
    │                                   ├── colors accent bar by tab position (from config palette)
    │                                   └── click → peon-focus.sh → activate tab
    │
    ├── peon-alert-marker.sh → writes /tmp/peon-ping-last-alert-tty + recall history
    │
    ├── session-namer.sh → extracts topic → writes /tmp/wezterm-tabn-{pane}
    │                                                  |
    │  WezTerm update-status handler reads marker files┘
    │
    └── title-topic.sh (peon-ping notification_title_script)
           → reads tabn marker + git/cwd → emits "<project> - <topic>"
           → peon-ping uses this as the notification title
    ├── tabn override? → use it
    ├── Claude running? → use conversation summary
    └── fallback → cwd basename

format-tab-title handler colors tab text by position using shared palette
```

## Repo Structure

```
scripts/
  hud-dir.sh              # Path resolver (sourced by other scripts)
  mac-overlay-compact.js   # Custom notification overlay
  peon-alert-marker.sh     # Claude Code hook: tracks alerting tab + recall history
  peon-focus.sh            # Activate WezTerm tab + optional app focus
  peon-recall.sh           # Show recent notifications as overlay stack
  session-namer.sh         # Auto-name tabs from conversation topic
  title-topic.sh           # peon-ping notification_title_script: "<project> - <topic>"
wezterm-snippets/
  tab-colors.lua           # format-tab-title with catppuccin palette
  tab-titles.lua           # update-status + peon-focus/recall handlers
  keybindings.lua          # CTRL+CMD keybindings
config.json                # User config (recall count, activation toggle)
tabn.sh                    # Shell function (source in .zshrc)
tabn-command.md            # Claude Code /tabn slash command
install.sh                 # Automated installer
```
