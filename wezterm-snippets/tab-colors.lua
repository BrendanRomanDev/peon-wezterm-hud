-- peon-wezterm-hud: Per-tab color identity
-- Reads palette from config.json. Paste into your wezterm.lua.
-- NOTE: Set hud_config_path to your actual config.json path.

local hud_config_path = os.getenv("HOME") .. "/.peon-wezterm-hud/config.json"

local function load_tab_palette()
	local defaults = { "#cba6f7", "#89b4fa", "#a6e3a1", "#fab387", "#f38ba8", "#94e2d5", "#f9e2af", "#74c7ec" }
	local ok, result = pcall(function()
		local f = io.open(hud_config_path, "r")
		if not f then return defaults end
		local content = f:read("*a")
		f:close()
		local palette = {}
		for hex in content:gmatch('"(#%x%x%x%x%x%x)"') do
			table.insert(palette, hex)
		end
		if #palette > 0 then return palette end
		return defaults
	end)
	return ok and result or defaults
end

local function hex_to_rgb(hex)
	hex = hex:gsub("#", "")
	return {
		r = tonumber(hex:sub(1, 2), 16),
		g = tonumber(hex:sub(3, 4), 16),
		b = tonumber(hex:sub(5, 6), 16),
	}
end

local tab_palette_hexes = load_tab_palette()
local tab_palette = {}
for _, hex in ipairs(tab_palette_hexes) do
	table.insert(tab_palette, hex_to_rgb(hex))
end

wezterm.on("format-tab-title", function(tab, tabs, panes, config, hover, max_width)
	local idx = (tab.tab_index % #tab_palette) + 1
	local c = tab_palette[idx]
	local title = tab.active_pane.title
	if tab.tab_title and tab.tab_title ~= "" then
		title = tab.tab_title
	end
	return {
		{ Foreground = { Color = string.format("rgb(%d,%d,%d)", c.r, c.g, c.b) } },
		{ Text = " " .. title .. " " },
	}
end)
