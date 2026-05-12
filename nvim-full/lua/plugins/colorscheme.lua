local background_mode = require("config.background_mode")
local theme_sync = require("config.theme_sync")

local function catppuccin_opts()
  local selected_theme = theme_sync.current()
  return {
    flavour = selected_theme.flavour,
    color_overrides = selected_theme.color_overrides or {},
    transparent_background = true,
    auto_integrations = true,
    float = {
      transparent = true,
    },
    custom_highlights = function(c)
      return {
        Normal = { bg = c.none },
        NormalNC = { bg = c.none },
        SignColumn = { bg = c.none },
        EndOfBuffer = { bg = c.none },
        LineNr = { bg = c.none },
        FoldColumn = { bg = c.none },
        CursorLine = {
          bg = c.none,
          underline = true,
          sp = c.surface1,
        },
        CursorLineNr = { bg = c.none },
        NormalFloat = { bg = background_mode.is_solid() and c.mantle or c.none },
        FloatBorder = { bg = background_mode.is_solid() and c.mantle or c.none },
        FloatTitle = { bg = background_mode.is_solid() and c.mantle or c.none },
        Pmenu = { bg = background_mode.is_solid() and c.mantle or c.none },
        PmenuSel = { bg = c.surface0 },
        WinSeparator = { bg = c.none },
        VertSplit = { bg = c.none },
      }
    end,
  }
end

local function apply_selected_theme()
  local selected_theme = theme_sync.current()
  local ok, catppuccin = pcall(require, "catppuccin")
  if not ok then
    return
  end

  catppuccin.setup(catppuccin_opts())
  vim.cmd.colorscheme(selected_theme.colorscheme)
end

local function apply_transparent_highlights()
  local colors = theme_sync.get_palette() or {}
  local float_bg = background_mode.is_solid() and (colors.mantle or colors.base or "#181825") or "NONE"

  local groups = {
    "Normal",
    "NormalNC",
    "SignColumn",
    "EndOfBuffer",
    "LineNr",
    "FoldColumn",
    "CursorLineNr",
    "WinSeparator",
    "VertSplit",
  }

  for _, group in ipairs(groups) do
    local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = group, link = false })
    if ok then
      hl.bg = "NONE"
      hl.ctermbg = "NONE"
      vim.api.nvim_set_hl(0, group, hl)
    end
  end

  vim.api.nvim_set_hl(0, "CursorLine", {
    bg = "NONE",
    ctermbg = "NONE",
    underline = true,
    sp = vim.api.nvim_get_hl(0, { name = "Comment", link = false }).fg,
  })
  local float_hl = { bg = float_bg }
  if float_bg == "NONE" then
    float_hl.ctermbg = "NONE"
  end
  vim.api.nvim_set_hl(0, "NormalFloat", float_hl)
  vim.api.nvim_set_hl(0, "FloatBorder", float_hl)
  vim.api.nvim_set_hl(0, "FloatTitle", float_hl)
  vim.api.nvim_set_hl(0, "Pmenu", float_hl)
  background_mode.apply_highlights()
end

return {
  {
    "catppuccin/nvim",
    name = "catppuccin",
    priority = 1000,
    opts = catppuccin_opts(),
    init = function()
      local group = vim.api.nvim_create_augroup("ruantni-catppuccin-transparent", { clear = true })
      local function apply_later()
        vim.schedule(apply_transparent_highlights)
        vim.defer_fn(apply_transparent_highlights, 20)
        vim.defer_fn(apply_transparent_highlights, 100)
        vim.defer_fn(apply_transparent_highlights, 300)
      end

      vim.api.nvim_create_autocmd("ColorScheme", {
        group = group,
        callback = function()
          apply_later()
        end,
      })
      vim.api.nvim_create_autocmd("VimEnter", {
        group = group,
        callback = function()
          apply_later()
        end,
      })
      vim.api.nvim_create_autocmd("UIEnter", {
        group = group,
        callback = function()
          apply_later()
        end,
      })
      vim.api.nvim_create_autocmd("User", {
        group = group,
        pattern = "VeryLazy",
        callback = function()
          apply_later()
        end,
      })
    end,
    config = function(_, opts)
      apply_selected_theme()
      apply_transparent_highlights()

      theme_sync.watch(function()
        apply_selected_theme()
        apply_transparent_highlights()
        vim.api.nvim_exec_autocmds("User", { pattern = "ThemeSyncReload" })
      end)
    end,
  },
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = theme_sync.current().colorscheme,
    },
  },
}
