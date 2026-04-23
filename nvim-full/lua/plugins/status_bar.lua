local function bubbles_theme()
  local ok, tn_colors = pcall(require, "tokyonight.colors")
  local colors = ok and tn_colors.setup() or nil

  if not colors then
    colors = {
      none = "NONE",
      bg_dark = "#1e2030",
      fg = "#c8d3f5",
      fg_dark = "#828bb8",
      fg_gutter = "#3b4261",
      blue = "#82aaff",
      cyan = "#86e1fc",
      magenta = "#c099ff",
      red = "#ff757f",
    }
  end

  return {
    normal = {
      a = { fg = colors.bg_dark, bg = colors.magenta, gui = "bold" },
      b = { fg = colors.fg, bg = colors.fg_gutter },
      c = { fg = colors.fg_dark, bg = colors.none },
    },
    insert = {
      a = { fg = colors.bg_dark, bg = colors.blue, gui = "bold" },
      b = { fg = colors.fg, bg = colors.fg_gutter },
      c = { fg = colors.fg_dark, bg = colors.none },
    },
    visual = {
      a = { fg = colors.bg_dark, bg = colors.cyan, gui = "bold" },
      b = { fg = colors.fg, bg = colors.fg_gutter },
      c = { fg = colors.fg_dark, bg = colors.none },
    },
    replace = {
      a = { fg = colors.bg_dark, bg = colors.red, gui = "bold" },
      b = { fg = colors.fg, bg = colors.fg_gutter },
      c = { fg = colors.fg_dark, bg = colors.none },
    },
    inactive = {
      a = { fg = colors.fg_dark, bg = colors.none },
      b = { fg = colors.fg_dark, bg = colors.none },
      c = { fg = colors.fg_dark, bg = colors.none },
    },
  }
end

local function set_hl_bg_none(name)
  local hl = vim.api.nvim_get_hl(0, { name = name, link = false })
  hl.bg = "none"
  vim.api.nvim_set_hl(0, name, hl)
end

local function set_transparent_statusline()
  set_hl_bg_none("StatusLine")
  set_hl_bg_none("StatusLineNC")
  set_hl_bg_none("StatusLineTerm")
  set_hl_bg_none("StatusLineTermNC")
end

return {
  {
    "nvim-lualine/lualine.nvim",
    event = "VeryLazy",
    init = function()
      local group = vim.api.nvim_create_augroup("transparent-lualine", { clear = true })

      vim.api.nvim_create_autocmd("ColorScheme", {
        group = group,
        callback = function()
          vim.schedule(set_transparent_statusline)
        end,
      })
    end,
    opts = function(_, opts)
      opts = opts or {}
      opts.options = opts.options or {}
      opts.options.theme = bubbles_theme()
      opts.options.component_separators = ""
      opts.options.section_separators = { left = "", right = "" }
      opts.options.disabled_filetypes = opts.options.disabled_filetypes or {}
      opts.options.disabled_filetypes.statusline = opts.options.disabled_filetypes.statusline or {}

      vim.list_extend(opts.options.disabled_filetypes.statusline, {
        "neo-tree",
        "snacks_layout_box",
      })

      opts.sections = {
        lualine_a = { { "mode", separator = { left = "" }, right_padding = 2 } },
        lualine_b = { "filename", "branch" },
        lualine_c = { "%=" },
        lualine_x = {},
        lualine_y = { "filetype", "progress" },
        lualine_z = { { "location", separator = { right = "" }, left_padding = 2 } },
      }

      opts.inactive_sections = {
        lualine_a = { "filename" },
        lualine_b = {},
        lualine_c = {},
        lualine_x = {},
        lualine_y = {},
        lualine_z = { "location" },
      }

      return opts
    end,
    config = function(_, opts)
      require("lualine").setup(opts)
      vim.schedule(set_transparent_statusline)
    end,
  },
}
