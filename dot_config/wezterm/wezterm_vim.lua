local wezterm = require("wezterm")

local M = {}
local shell_processes = {
	bash = true,
	fish = true,
	nu = true,
	sh = true,
	zsh = true,
}
local vim_processes = {
	nvim = true,
	vim = true,
	vi = true,
}

local function normalize_process_name(process)
	if not process or process == "" then
		return nil
	end

	local name = string.match(process, "^%S+")
	name = string.match(name, "([^/\\]+)$") or name
	name = string.lower(name)
	name = string.gsub(name, "%.exe$", "")

	return name
end

function M.current_process_name(pane)
	local user_vars = pane:get_user_vars()
	if user_vars.WEZTERM_PROG and user_vars.WEZTERM_PROG ~= "" then
		return normalize_process_name(user_vars.WEZTERM_PROG)
	end

	local ok, process = pcall(function()
		return pane:get_foreground_process_name()
	end)

	if ok then
		return normalize_process_name(process)
	end

	return nil
end

function M.is_shell_process(pane)
	local process = M.current_process_name(pane)
	return process ~= nil and shell_processes[process] == true
end

local function cursor_shape_mode(pane)
	local ok, cursor = pcall(function()
		return pane:get_cursor_position()
	end)

	if ok and cursor and cursor.shape then
		local shape = tostring(cursor.shape)
		if string.find(shape, "Block", 1, true) then
			return "N"
		end
		if string.find(shape, "Bar", 1, true) or string.find(shape, "Underline", 1, true) then
			return "I"
		end
	end

	return nil
end

function M.current_vi_mode(pane)
	local process = M.current_process_name(pane)
	if process ~= nil and vim_processes[process] == true then
		return cursor_shape_mode(pane) or "N"
	end

	local user_vars = pane:get_user_vars()
	if user_vars.VI_MODE == "N" or user_vars.VI_MODE == "I" then
		return user_vars.VI_MODE
	end

	return cursor_shape_mode(pane) or "I"
end

function M.is_normal_mode(pane)
	return M.current_vi_mode(pane) == "N"
end

function M.setup(config)
	local act = wezterm.action

	local leader_action = wezterm.action_callback(function(window, pane)
		if M.is_shell_process(pane) and M.is_normal_mode(pane) then
			window:perform_action(act.ActivateKeyTable({
				name = "leader",
				timeout_milliseconds = 1000,
				one_shot = true,
			}), pane)
		else
			window:perform_action(act.SendKey({ key = " " }), pane)
		end
	end)

	local force_leader_action = wezterm.action_callback(function(window, pane)
		window:perform_action(act.ActivateKeyTable({
			name = "leader",
			timeout_milliseconds = 1800,
			one_shot = true,
		}), pane)
	end)

	table.insert(config.keys, 1, { key = "Space", mods = "NONE", action = leader_action })
	table.insert(config.keys, 2, { key = "g", mods = "CTRL", action = force_leader_action })

	config.key_tables = config.key_tables or {}
	config.key_tables.leader = {
		{ key = "h", mods = "NONE", action = act.ActivatePaneDirection("Left") },
		{ key = "j", mods = "NONE", action = act.ActivatePaneDirection("Down") },
		{ key = "k", mods = "NONE", action = act.ActivatePaneDirection("Up") },
		{ key = "l", mods = "NONE", action = act.ActivatePaneDirection("Right") },
		{ key = "s", mods = "NONE", action = act.SplitVertical({ domain = "CurrentPaneDomain" }) },
		{ key = "v", mods = "NONE", action = act.SplitHorizontal({ domain = "CurrentPaneDomain" }) },
		{ key = "H", mods = "SHIFT", action = act.ActivateTabRelative(-1) },
		{ key = "L", mods = "SHIFT", action = act.ActivateTabRelative(1) },
		{ key = "Escape", mods = "NONE", action = act.PopKeyTable },
	}
end

return M
