local M = {}
local theme_sync = require("config.theme_sync")

local mode_file = vim.fn.expand("~/.config/wezterm/background_mode")
local fallback_bg = "#181825"

local function read_mode_file()
  local file = io.open(mode_file, "r")
  if not file then
    return "image"
  end

  local mode = file:read("*l")
  file:close()

  if mode == "solid" then
    return "solid"
  end

  return "image"
end

function M.mode()
  local mode = read_mode_file()
  vim.g.wezterm_background_mode = mode
  return mode
end

function M.is_solid()
  return M.mode() == "solid"
end

function M.backdrop(overrides)
  local defaults = {
    bg = fallback_bg,
    blend = M.is_solid() and 50 or 100,
    transparent = true,
  }

  return vim.tbl_extend("force", defaults, overrides or {})
end

function M.apply_highlights()
  local colors = theme_sync.get_palette() or {}
  local shade_bg = colors.mantle or colors.base or fallback_bg

  vim.api.nvim_set_hl(0, "FloatShadow", {
    bg = shade_bg,
    blend = M.is_solid() and 60 or 100,
  })
  vim.api.nvim_set_hl(0, "FloatShadowThrough", {
    bg = shade_bg,
    blend = M.is_solid() and 85 or 100,
  })
  vim.api.nvim_set_hl(0, "SnacksBackdrop", {
    bg = shade_bg,
    blend = M.is_solid() and 60 or 100,
  })
end

return M
