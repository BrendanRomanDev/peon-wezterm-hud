-- peon-wezterm-hud: Per-tab color identity (catppuccin-mocha accents)
-- Paste this into your wezterm.lua (after `local wezterm = require("wezterm")`)

local tab_palette = {
	{ r = 0.80, g = 0.65, b = 0.97 },  -- mauve
	{ r = 0.54, g = 0.71, b = 0.98 },  -- blue
	{ r = 0.65, g = 0.89, b = 0.63 },  -- green
	{ r = 0.98, g = 0.70, b = 0.53 },  -- peach
	{ r = 0.95, g = 0.55, b = 0.66 },  -- pink
	{ r = 0.58, g = 0.89, b = 0.83 },  -- teal
	{ r = 0.98, g = 0.89, b = 0.69 },  -- yellow
	{ r = 0.46, g = 0.78, b = 0.93 },  -- sapphire
}

wezterm.on("format-tab-title", function(tab, tabs, panes, config, hover, max_width)
	local idx = (tab.tab_index % #tab_palette) + 1
	local c = tab_palette[idx]
	local title = tab.active_pane.title
	if tab.tab_title and tab.tab_title ~= "" then
		title = tab.tab_title
	end
	return {
		{ Foreground = { Color = string.format("rgb(%d,%d,%d)", math.floor(c.r * 255), math.floor(c.g * 255), math.floor(c.b * 255)) } },
		{ Text = " " .. title .. " " },
	}
end)
