-- peon-wezterm-hud: Smart tab titles
-- Paste this into your wezterm.lua
-- Priority: tabn override > Claude Code conversation summary > cwd basename
--
-- NOTE: Replace "/path/to/peon-wezterm-hud" with your actual install path

-- PeonPing focus: jump to the tab that most recently needed attention
wezterm.on("peon-focus", function(window, pane)
	local marker = io.open("/tmp/peon-ping-last-alert-tty", "r")
	if not marker then return end
	local target_tty = marker:read("*l")
	marker:close()
	if not target_tty or target_tty == "" then return end

	local success, stdout, stderr = wezterm.run_child_process({
		"/opt/homebrew/bin/wezterm", "cli", "list", "--format", "json",
	})
	if not success or not stdout or stdout == "" then return end

	local json = wezterm.json_parse(stdout)
	if not json then return end

	for _, p in ipairs(json) do
		if p.tty_name == target_tty then
			wezterm.run_child_process({
				"/opt/homebrew/bin/wezterm", "cli", "activate-tab", "--tab-id", tostring(p.tab_id),
			})
			wezterm.run_child_process({
				"/opt/homebrew/bin/wezterm", "cli", "activate-pane", "--pane-id", tostring(p.pane_id),
			})
			return
		end
	end
end)

-- PeonPing recall: show recent notification history
wezterm.on("peon-recall", function(window, pane)
	wezterm.run_child_process({ "/path/to/peon-wezterm-hud/scripts/peon-recall.sh" })
end)

-- Update tab titles based on cwd (with manual override and Claude Code support)
wezterm.on("update-status", function(window)
	local active_pane = window:active_tab():active_pane()
	if not active_pane then return end

	-- manual override via marker file (set with `tabn "name"` in shell)
	local pane_id = active_pane:pane_id()
	local marker = io.open("/tmp/wezterm-tabn-" .. tostring(pane_id), "r")
	if marker then
		local override = marker:read("*l")
		marker:close()
		if override and override ~= "" then
			local curr = active_pane:tab():get_title()
			if curr ~= override then
				window:active_tab():set_title(override)
			end
			return
		end
	end

	-- if Claude Code is running, use its conversation summary as tab title
	local pane_title = active_pane:get_title()
	local foreground = active_pane:get_foreground_process_name() or ""
	if foreground:find("claude") then
		local summary = pane_title:gsub("^[%s%p%c]+", "")
		if summary ~= "" then
			local curr = active_pane:tab():get_title()
			if curr ~= summary then
				window:active_tab():set_title(summary)
			end
			return
		end
	end

	-- default: derive from cwd
	local cwd = tostring(active_pane:get_current_working_dir())
	local curr_tab_title = active_pane:tab():get_title()
	local new_tab_title = cwd:match("/([^/]+)$")

	if curr_tab_title ~= new_tab_title then
		window:active_tab():set_title(new_tab_title)
	end
end)
