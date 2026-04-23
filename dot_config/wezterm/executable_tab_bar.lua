local wezterm = require("wezterm")

local nerdfonts = wezterm.nerdfonts
local F = dofile(wezterm.home_dir .. "/.config/wezterm/functions.lua")

local M = {}

local function normalize_process_name(process)
	if not process or process == "" then
		return nil
	end

	local name = string.match(process, "^%S+")
	name = F.basename(name)
	name = string.lower(name)
	name = string.gsub(name, "%.exe$", "")

	return name
end

local function process_name_from_pane(pane)
	local program = pane.user_vars and pane.user_vars.WEZTERM_PROG or nil

	if program and program ~= "" then
		return normalize_process_name(program)
	end

	local ok, foreground = pcall(function()
		return pane:get_foreground_process_name()
	end)

	if ok and foreground and foreground ~= "" then
		return normalize_process_name(foreground)
	end

	return nil
end

local function pane_has_ssh_connection(pane)
	local process = process_name_from_pane(pane)
	if process == "ssh" or process == "mosh" or process == "mosh-client" then
		return true
	end

	local title = string.lower(pane.title or "")
	if title:match("(^|%s)ssh(%s|$)") or title:match("mosh") then
		return true
	end

	return false
end

function M.setup(config)
	local colors = wezterm.get_builtin_color_schemes()[config.color_scheme] or {}
	local transparent = "rgba(0, 0, 0, 0)"
	local username = os.getenv("USER") or os.getenv("LOGNAME") or os.getenv("USERNAME") or "user"
	local hostname = string.lower(wezterm.hostname())
	local active_tab_color = "#a6da95"

	config.enable_tab_bar = true
	config.hide_tab_bar_if_only_one_tab = false
	config.show_new_tab_button_in_tab_bar = false
	config.show_tab_index_in_tab_bar = false
	config.tab_bar_at_bottom = false
	config.tab_max_width = 35
	config.use_fancy_tab_bar = false

	config.colors = config.colors or {}
	config.colors.tab_bar = {
		background = transparent,
		active_tab = {
			bg_color = transparent,
			fg_color = active_tab_color,
			italic = true,
		},
		inactive_tab = {
			bg_color = transparent,
			fg_color = colors.foreground or "#cad3f5",
		},
		inactive_tab_hover = {
			bg_color = transparent,
			fg_color = colors.foreground or "#cad3f5",
			italic = false,
		},
		new_tab = {
			bg_color = transparent,
			fg_color = colors.foreground or "#cad3f5",
		},
		new_tab_hover = {
			bg_color = transparent,
			fg_color = (colors.indexed and colors.indexed[16]) or colors.foreground or "#cad3f5",
			italic = false,
		},
	}

	wezterm.on("update-status", function(window, pane)
		local active_key_table = window:active_key_table()
		local stat = "local"
		local workspace_color = (colors.ansi and colors.ansi[3]) or "#eed49f"
		local time = wezterm.strftime("%Y-%m-%d %H:%M")

		if pane_has_ssh_connection(pane) then
			stat = "ssh"
			workspace_color = (colors.ansi and colors.ansi[4]) or "#8aadf4"
		end

		if active_key_table then
			stat = active_key_table
			workspace_color = (colors.ansi and colors.ansi[4]) or "#8aadf4"
		elseif window:leader_is_active() then
			stat = "leader"
			workspace_color = (colors.ansi and colors.ansi[2]) or "#a6da95"
		end

		local cwd = pane:get_current_working_dir()
		if cwd then
			if type(cwd) == "userdata" then
				if string.len(cwd.path) > config.tab_max_width then
					cwd = ".." .. string.sub(cwd.path, config.tab_max_width * -1, -1)
				else
					cwd = cwd.path
				end
			end
		else
			cwd = ""
		end

		window:set_right_status(wezterm.format({
			{ Text = " " },
			{ Background = { Color = transparent } },
			{ Foreground = { Color = "#ee99a0" } },
			{ Text = nerdfonts.ple_left_half_circle_thick },
			-- { Background = { Color = (colors.ansi and colors.ansi[4]) or "#8aadf4" } },
			{ Background = { Color = "#ee99a0" } },
			{ Foreground = { Color = colors.background or "#1e2030" } },
			{ Text = nerdfonts.md_folder .. " " },
			{ Background = { Color = (colors.ansi and colors.ansi[1]) or "#494d64" } },
			{ Foreground = { Color = colors.foreground or "#cad3f5" } },
			{ Text = " " .. cwd },
			{ Background = { Color = transparent } },
			{ Foreground = { Color = (colors.ansi and colors.ansi[1]) or "#494d64" } },
			{ Text = nerdfonts.ple_right_half_circle_thick },

			{ Text = " " },
			{ Background = { Color = transparent } },
			{ Foreground = { Color = (colors.ansi and colors.ansi[7]) or "#91d7e3" } },
			{ Text = nerdfonts.ple_left_half_circle_thick },
			{ Background = { Color = (colors.ansi and colors.ansi[7]) or "#91d7e3" } },
			{ Foreground = { Color = colors.background or "#1e2030" } },
			{ Text = nerdfonts.fa_user .. " " },
			{ Background = { Color = (colors.ansi and colors.ansi[1]) or "#494d64" } },
			{ Foreground = { Color = colors.foreground or "#cad3f5" } },
			{ Text = " " .. username },
			{ Background = { Color = transparent } },
			{ Foreground = { Color = (colors.ansi and colors.ansi[1]) or "#494d64" } },
			{ Text = nerdfonts.ple_right_half_circle_thick },

			{ Text = " " },
			{ Background = { Color = transparent } },
			{ Foreground = { Color = (colors.indexed and colors.indexed[16]) or "#b7bdf8" } },
			{ Text = nerdfonts.ple_left_half_circle_thick },
			{ Background = { Color = (colors.indexed and colors.indexed[16]) or "#b7bdf8" } },
			{ Foreground = { Color = (colors.ansi and colors.ansi[1]) or "#494d64" } },
			{ Text = nerdfonts.cod_server .. " " },
			{ Background = { Color = (colors.ansi and colors.ansi[1]) or "#494d64" } },
			{ Foreground = { Color = colors.foreground or "#cad3f5" } },
			{ Text = " " .. hostname },
			{ Background = { Color = transparent } },
			{ Foreground = { Color = (colors.ansi and colors.ansi[1]) or "#494d64" } },
			{ Text = nerdfonts.ple_right_half_circle_thick },

			{ Text = " " },
			{ Background = { Color = transparent } },
			{ Foreground = { Color = workspace_color } },
			{ Text = nerdfonts.ple_left_half_circle_thick },
			{ Background = { Color = workspace_color } },
			{ Foreground = { Color = colors.background or "#1e2030" } },
			{ Text = nerdfonts.md_remote_desktop .. " " },
			{ Background = { Color = (colors.ansi and colors.ansi[1]) or "#494d64" } },
			{ Foreground = { Color = colors.foreground or "#cad3f5" } },
			{ Text = " " .. stat },
			{ Background = { Color = transparent } },
			{ Foreground = { Color = (colors.ansi and colors.ansi[1]) or "#494d64" } },
			{ Text = nerdfonts.ple_right_half_circle_thick },

			{ Text = " " },
			{ Background = { Color = transparent } },
			{ Foreground = { Color = (colors.brights and colors.brights[1]) or "#f5bde6" } },
			{ Text = nerdfonts.ple_left_half_circle_thick },
			{ Background = { Color = (colors.brights and colors.brights[1]) or "#f5bde6" } },
			{ Foreground = { Color = colors.background or "#1e2030" } },
			{ Text = nerdfonts.md_calendar_clock .. " " },
			{ Background = { Color = (colors.ansi and colors.ansi[1]) or "#494d64" } },
			{ Foreground = { Color = colors.foreground or "#cad3f5" } },
			{ Text = " " .. time },
			{ Background = { Color = transparent } },
			{ Foreground = { Color = (colors.ansi and colors.ansi[1]) or "#494d64" } },
			{ Text = nerdfonts.ple_right_half_circle_thick },
		}))
	end)

	wezterm.on("format-tab-title", function(tab)
		local pane = tab.active_pane
		local title = F.tab_title(tab)
		local tab_number = tostring(tab.tab_index + 1)
		local command = process_name_from_pane(pane)

		if string.len(title) > config.tab_max_width - 3 then
			title = string.sub(title, 1, config.tab_max_width - 12) .. ".. "
		end

		if tab.is_active then
			title = nerdfonts.dev_terminal .. " " .. title
		end

		if pane.is_zoomed then
			title = nerdfonts.cod_zoom_in .. " " .. title
		end

		if string.match(pane.title, "^Copy mode:") then
			title = nerdfonts.md_content_copy .. " " .. title
		end

		if command then
			if command == "docker" or command == "podman" then
				title = nerdfonts.linux_docker .. " " .. title
			end

			if command == "kind" or command == "kubectl" then
				title = nerdfonts.md_kubernetes .. " " .. title
			end

			if command == "ssh" then
				title = nerdfonts.md_remote_desktop .. " " .. title
			end

			if string.match(command, "^([bh]?)top") then
				title = nerdfonts.md_monitor_eye .. " " .. title
			end

			if string.match(command, "^(n?)vi(m?)") then
				title = nerdfonts.dev_vim .. " " .. title
			end

			if command == "watch" then
				title = nerdfonts.md_eye_outline .. " " .. title
			end
		end

		local has_unseen_output = false
		if not tab.is_active then
			for _, tab_pane in ipairs(tab.panes) do
				if tab_pane.has_unseen_output then
					has_unseen_output = true
					break
				end
			end
		end

		if has_unseen_output then
			title = nerdfonts.md_bell_ring_outline .. " " .. title
		end

		if tab.is_active then
			return {
				{ Background = { Color = transparent } },
				{ Foreground = { Color = (colors.ansi and colors.ansi[3]) or "#494d64" } },
				{ Text = title .. " " },
				{ Background = { Color = (colors.ansi and colors.ansi[3]) or "#494d64" } },
				{ Foreground = { Color = colors.background or "#cad3f5" } },
				{ Text = " " .. tab_number },
				{ Background = { Color = transparent } },
				{ Foreground = { Color = active_tab_color } },
				{ Text = nerdfonts.ple_right_half_circle_thick .. " " },
			}
		end

		return {
			{ Background = { Color = transparent } },
			{ Foreground = { Color = (colors.ansi and colors.ansi[1]) or "#494d64" } },
			{ Text = nerdfonts.ple_left_half_circle_thick },
			{ Background = { Color = (colors.ansi and colors.ansi[1]) or "#494d64" } },
			{ Foreground = { Color = colors.foreground or "#cad3f5" } },
			{ Text = title .. " " },
			{ Background = { Color = (colors.ansi and colors.ansi[5]) or "#8aadf4" } },
			{ Foreground = { Color = colors.background or "#1e2030" } },
			{ Text = " " .. tab_number },
			{ Background = { Color = transparent } },
			{ Foreground = { Color = (colors.ansi and colors.ansi[5]) or "#8aadf4" } },
			{ Text = nerdfonts.ple_right_half_circle_thick .. " " },
		}
	end)
end

return M
