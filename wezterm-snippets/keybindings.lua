-- peon-wezterm-hud: WezTerm keybindings
-- Add these to your config.keys table in wezterm.lua

-- PeonPing: jump to the tab that most recently needed attention
{ key = ".", mods = "CTRL | CMD", action = wezterm.action.EmitEvent("peon-focus") },
-- PeonPing: show recent notification history
{ key = ",", mods = "CTRL | CMD", action = wezterm.action.EmitEvent("peon-recall") },
