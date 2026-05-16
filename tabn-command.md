---
description: Rename the current terminal tab (works in tmux and WezTerm)
argument-hint: <name> (omit to clear)
allowed-tools: ["Bash"]
---

Rename the current terminal tab by running a single bash command.

If `$ARGUMENTS` is not empty, rename the tab:

```bash
if [ -n "${TMUX:-}" ]; then tmux rename-window "$ARGUMENTS"; else printf '%s' "$ARGUMENTS" > "/tmp/wezterm-tabn-${WEZTERM_PANE}"; fi && echo "Tab renamed: $ARGUMENTS"
```

If `$ARGUMENTS` is empty, clear the tab name back to auto:

```bash
if [ -n "${TMUX:-}" ]; then tmux set-window-option automatic-rename on; else rm -f "/tmp/wezterm-tabn-${WEZTERM_PANE}"; fi && echo "Tab name cleared (back to auto)"
```

After running, confirm with the output message. Do not add any commentary.
