# tabn: rename terminal tab (tmux or WezTerm)
# Source this file in your .zshrc or .bashrc:
#   source ~/.peon-wezterm-hud/tabn.sh
#
# Usage: tabn "Server"  |  tabn (no args = clear, back to auto)
tabn() {
  if [ -n "${TMUX:-}" ]; then
    if [ -z "$1" ]; then
      tmux set-window-option automatic-rename on
      echo "Tab name cleared (back to auto)"
    else
      tmux rename-window "$1"
      echo "Tab renamed: $1"
    fi
  else
    local marker="/tmp/wezterm-tabn-${WEZTERM_PANE}"
    if [ -z "$1" ]; then
      rm -f "$marker"
      echo "Tab name cleared (back to auto)"
    else
      printf '%s' "$1" > "$marker"
      echo "Tab renamed: $1"
    fi
  fi
}
