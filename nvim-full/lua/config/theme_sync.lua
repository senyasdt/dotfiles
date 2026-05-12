local M = {}

local default_theme_name = "Catppuccin Macchiato"
local active_scheme_path = vim.fn.expand("~/.config/wezterm/active_scheme.toml")
local generated_palette_path = vim.fn.expand("~/.config/wezterm/generated_palette.json")

local forest_palette = {
  rosewater = "#d8e2e5",
  flamingo = "#c7d0d3",
  pink = "#a398b4",
  mauve = "#8a7f99",
  red = "#b87878",
  maroon = "#9b5f5f",
  peach = "#b0a06a",
  yellow = "#c7b87a",
  green = "#8fae98",
  teal = "#7fa6a8",
  sky = "#9bbfc0",
  sapphire = "#8faec1",
  blue = "#6f8fa3",
  lavender = "#a398b4",
  text = "#c7d0d3",
  subtext1 = "#9bbfc0",
  subtext0 = "#8fae98",
  overlay2 = "#7a8d94",
  overlay1 = "#5f7077",
  overlay0 = "#46545b",
  surface2 = "#334047",
  surface1 = "#263238",
  surface0 = "#1b252a",
  base = "#0b1114",
  mantle = "#10181c",
  crust = "#070c0f",
  none = "NONE",
}

local theme_mapping = {
  ["catppuccin latte"] = { colorscheme = "catppuccin", flavour = "latte" },
  ["catppuccin frappe"] = { colorscheme = "catppuccin", flavour = "frappe" },
  ["catppuccin macchiato"] = { colorscheme = "catppuccin", flavour = "macchiato" },
  ["catppuccin mocha"] = { colorscheme = "catppuccin", flavour = "mocha" },
  ["forest"] = {
    colorscheme = "catppuccin",
    flavour = "macchiato",
    palette = forest_palette,
    color_overrides = { all = forest_palette },
  },
  ["generated"] = {
    colorscheme = "catppuccin",
    flavour = "macchiato",
  },
}

local watcher = nil

function M.active_scheme_path()
  return active_scheme_path
end

function M.read_active_scheme()
  local file = io.open(active_scheme_path, "r")
  if not file then
    return { theme = default_theme_name }
  end

  local state = { theme = default_theme_name }
  for line in file:lines() do
    local theme = line:match('^%s*theme%s*=%s*"(.-)"%s*$')
    if theme and theme ~= "" then
      state.theme = theme
    end
  end
  file:close()

  return state
end

function M.current()
  local state = M.read_active_scheme()
  local key = vim.trim(string.lower(state.theme or default_theme_name))
  local selected = vim.deepcopy(theme_mapping[key] or theme_mapping[string.lower(default_theme_name)])
  if key == "generated" then
    local palette_lines = nil
    if vim.fn.filereadable(generated_palette_path) == 1 then
      local read_ok, lines = pcall(vim.fn.readfile, generated_palette_path)
      if read_ok and type(lines) == "table" then
        palette_lines = lines
      end
    end

    if palette_lines then
      local ok, decoded = pcall(vim.fn.json_decode, table.concat(palette_lines, "\n"))
      if ok and type(decoded) == "table" then
        selected.palette = decoded
        selected.color_overrides = { all = decoded }
      end
    end
  end
  selected.wezterm_theme = state.theme
  return selected
end

function M.get_palette()
  local selected = M.current()
  if selected.palette then
    return selected.palette
  end

  local ok, cp = pcall(require, "catppuccin.palettes")
  if not ok then
    return nil
  end

  return cp.get_palette(selected.flavour)
end

function M.watch(callback)
  if watcher then
    return watcher
  end

  local ok, fs_event = pcall(vim.uv.new_fs_event)
  if not ok or not fs_event then
    return nil
  end

  local path = active_scheme_path
  fs_event:start(path, {}, vim.schedule_wrap(function(err)
    if err then
      return
    end
    callback()
  end))

  watcher = fs_event
  return watcher
end

return M
