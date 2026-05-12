local wezterm = require("wezterm")

local act = wezterm.action
local M = {}

local theme_file = wezterm.home_dir .. "/.config/wezterm/theme"
local active_scheme_file = wezterm.home_dir .. "/.config/wezterm/active_scheme.toml"
local theme_dir = wezterm.home_dir .. "/.config/wezterm/themes"
local generate_theme_script = wezterm.home_dir .. "/.config/wezterm/generate-theme-from-wallpaper.sh"
local generate_theme_script_wsl = "~/.config/wezterm/generate-theme-from-wallpaper.sh"
local default_color_scheme = "Catppuccin Macchiato"

local function theme_name_from_path(path)
	local filename = path:match("([^/\\]+)$") or path
	return filename:gsub("%.[^.]+$", "")
end

function M.read()
	local active_scheme = io.open(active_scheme_file, "r")
	if active_scheme then
		for line in active_scheme:lines() do
			local theme_name = line:match('^%s*theme%s*=%s*"(.-)"%s*$')
			if theme_name and theme_name ~= "" then
				active_scheme:close()
				return theme_name
			end
		end
		active_scheme:close()
	end

	local file = io.open(theme_file, "r")
	if not file then
		return default_color_scheme
	end

	local theme_name = file:read("*l")
	file:close()

	if not theme_name or theme_name == "" then
		return default_color_scheme
	end

	return theme_name
end

function M.write(theme_name)
	local active_scheme = io.open(active_scheme_file, "w")
	if active_scheme then
		active_scheme:write('theme = "', theme_name, '"\n')
		active_scheme:close()
	end

	local file = io.open(theme_file, "w")
	if not file then
		return false
	end

	file:write(theme_name, "\n")
	file:close()
	return true
end

function M.load_custom_schemes()
	local schemes = {}
	local ok, theme_paths = pcall(wezterm.glob, theme_dir .. "/*.toml")

	if not ok or not theme_paths then
		return schemes
	end

	for _, path in ipairs(theme_paths) do
		local load_ok, scheme = pcall(wezterm.color.load_scheme, path)
		if load_ok and scheme then
			local name = scheme.metadata and scheme.metadata.name or theme_name_from_path(path)
			schemes[name] = scheme
		else
			wezterm.log_error("failed to load theme: " .. path)
		end
	end

	return schemes
end

function M.resolve(theme_name, custom_schemes)
	if custom_schemes[theme_name] then
		return theme_name
	end

	if wezterm.get_builtin_color_schemes()[theme_name] then
		return theme_name
	end

	return default_color_scheme
end

function M.apply(config)
	local custom_schemes = M.load_custom_schemes()
	if next(custom_schemes) ~= nil then
		config.color_schemes = custom_schemes
	end

	local requested_theme_name = M.read()
	local theme_name = M.resolve(requested_theme_name, custom_schemes)
	if theme_name ~= requested_theme_name then
		M.write(theme_name)
	end

	config.color_scheme = theme_name
	wezterm.GLOBAL.current_theme_name = theme_name

	local colors = custom_schemes[theme_name] or wezterm.get_builtin_color_schemes()[theme_name] or {}
	return {
		name = theme_name,
		colors = colors,
		custom_schemes = custom_schemes,
		default_color_scheme = default_color_scheme,
	}
end

function M.set_theme_action(theme_name)
	return wezterm.action_callback(function(window, pane)
		if not M.write(theme_name) then
			window:toast_notification("wezterm", "failed to write theme", nil, 3000)
			return
		end

		window:perform_action(act.ReloadConfiguration, pane)
		window:toast_notification("wezterm", "theme: " .. theme_name, nil, 2000)
	end)
end

function M.generate_from_wallpaper_action()
	return wezterm.action_callback(function(window, pane)
		local cmd

		if wezterm.target_triple:find("windows") then
			cmd = {
				"wsl.exe",
				"sh",
				"-lc",
				generate_theme_script_wsl,
			}
		else
			cmd = {
				"sh",
				"-lc",
				generate_theme_script,
			}
		end

		local ok, success, stdout, stderr = pcall(wezterm.run_child_process, cmd)
		if not ok then
			window:toast_notification("wezterm", "failed to spawn wallpaper theme generator", nil, 4000)
			wezterm.log_error("wallpaper theme generator spawn failed: " .. tostring(success))
			return
		end

		if not success then
			local details = stderr ~= "" and stderr or stdout
			window:toast_notification("wezterm", "wallpaper theme generator failed", details ~= "" and details or nil, 5000)
			if details and details ~= "" then
				wezterm.log_error(details)
			end
			return
		end

		if stderr and stderr ~= "" then
			wezterm.log_error(stderr)
		end

		window:perform_action(act.ReloadConfiguration, pane)
		window:toast_notification("wezterm", "theme: generated from wallpaper", stdout ~= "" and stdout or nil, 3000)
	end)
end

function M.palette_entries(state)
	local entries = {
		{
			brief = "Theme | " .. state.default_color_scheme .. (state.name == state.default_color_scheme and " (current)" or ""),
			icon = "md_palette",
			action = M.set_theme_action(state.default_color_scheme),
		},
		{
			brief = "Theme | Generate from wallpaper" .. (state.name == "generated" and " (current)" or ""),
			icon = "md_image_auto_adjust",
			action = M.generate_from_wallpaper_action(),
		},
	}

	local theme_names = {}
	for name, _ in pairs(state.custom_schemes) do
		if name ~= "generated" then
			table.insert(theme_names, name)
		end
	end
	table.sort(theme_names)

	for _, name in ipairs(theme_names) do
		table.insert(entries, {
			brief = "Theme | " .. name .. (state.name == name and " (current)" or ""),
			icon = "md_palette_swatch",
			action = M.set_theme_action(name),
		})
	end

	return entries
end

return M
