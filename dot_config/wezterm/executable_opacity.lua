local wezterm = require("wezterm")

local act = wezterm.action
local M = {}

local opacity_file = wezterm.home_dir .. "/.config/wezterm/opacity"
local default_window_background_opacity = 0.90

local function clamp_opacity(value)
	if value < 0.0 then
		return 0.0
	end

	if value > 1.0 then
		return 1.0
	end

	return value
end

function M.read()
	local file = io.open(opacity_file, "r")
	if not file then
		return default_window_background_opacity
	end

	local value = tonumber(file:read("*l"))
	file:close()

	if not value then
		return default_window_background_opacity
	end

	return clamp_opacity(value)
end

function M.write(value)
	local file = io.open(opacity_file, "w")
	if not file then
		return false
	end

	file:write(string.format("%.2f\n", clamp_opacity(value)))
	file:close()
	return true
end

function M.apply(config)
	local window_background_opacity = M.read()
	config.window_background_opacity = window_background_opacity
	wezterm.GLOBAL.window_background_opacity = window_background_opacity
	return window_background_opacity
end

function M.set_opacity_action(value)
	return wezterm.action_callback(function(window, pane)
		local normalized_value = clamp_opacity(value)
		if not M.write(normalized_value) then
			window:toast_notification("wezterm", "failed to write opacity", nil, 3000)
			return
		end

		window:perform_action(act.ReloadConfiguration, pane)
		window:toast_notification("wezterm", string.format("opacity: %.0f%%", normalized_value * 100), nil, 2000)
	end)
end

function M.custom_opacity_action()
	return act.PromptInputLine({
		description = "Enter opacity from 0.00 to 1.00",
		action = wezterm.action_callback(function(window, pane, line)
			if not line then
				return
			end

			local value = tonumber(line)
			if not value then
				window:toast_notification("wezterm", "invalid opacity value", nil, 3000)
				return
			end

			value = clamp_opacity(value)
			if not M.write(value) then
				window:toast_notification("wezterm", "failed to write opacity", nil, 3000)
				return
			end

			window:perform_action(act.ReloadConfiguration, pane)
			window:toast_notification("wezterm", string.format("opacity: %.0f%%", value * 100), nil, 2000)
		end),
	})
end

function M.palette_entries(current_opacity)
	local entries = {}
	local opacity_presets = { 1.00, 0.95, 0.90, 0.85, 0.80, 0.75, 0.70 }

	for _, value in ipairs(opacity_presets) do
		local current_marker = math.abs(current_opacity - value) < 0.001 and " (current)" or ""
		table.insert(entries, {
			brief = string.format("Opacity | %.0f%%%s", value * 100, current_marker),
			icon = "md_opacity",
			action = M.set_opacity_action(value),
		})
	end

	table.insert(entries, {
		brief = string.format("Opacity | Set custom... (current %.0f%%)", current_opacity * 100),
		icon = "md_tune",
		action = M.custom_opacity_action(),
	})

	return entries
end

return M
