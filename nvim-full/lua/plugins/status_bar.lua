local colors = {
  blue = "#80a0ff",
  cyan = "#79dac8",
  none = "none",
  white = "#c6c6c6",
  red = "#ff5189",
  violet = "#d183e8",
}

local bubbles_theme = {
  normal = {
    a = { fg = colors.violet, bg = colors.none },
    b = { fg = colors.white, bg = colors.none },
    c = { fg = colors.white, bg = colors.none },
  },
  insert = {
    a = { fg = colors.blue, bg = colors.none },
    b = { fg = colors.white, bg = colors.none },
    c = { fg = colors.white, bg = colors.none },
  },
  visual = {
    a = { fg = colors.cyan, bg = colors.none },
    b = { fg = colors.white, bg = colors.none },
    c = { fg = colors.white, bg = colors.none },
  },
  replace = {
    a = { fg = colors.red, bg = colors.none },
    b = { fg = colors.white, bg = colors.none },
    c = { fg = colors.white, bg = colors.none },
  },
  inactive = {
    a = { fg = colors.white, bg = colors.none },
    b = { fg = colors.white, bg = colors.none },
    c = { fg = colors.white, bg = colors.none },
  },
}

local function set_transparent_statusline()
  vim.api.nvim_set_hl(0, "StatusLine", { bg = "none" })
  vim.api.nvim_set_hl(0, "StatusLineNC", { bg = "none" })
  vim.api.nvim_set_hl(0, "StatusLineTerm", { bg = "none" })
  vim.api.nvim_set_hl(0, "StatusLineTermNC", { bg = "none" })
end

return {
  {
    "nvim-lualine/lualine.nvim",
    event = "VeryLazy",
    init = function()
      local group = vim.api.nvim_create_augroup("transparent-lualine", { clear = true })
      vim.api.nvim_create_autocmd("ColorScheme", {
        group = group,
        callback = set_transparent_statusline,
      })
    end,
    opts = function(_, opts)
      opts = opts or {}
      opts.options = opts.options or {}
      opts.options.theme = bubbles_theme
      opts.options.component_separators = ""
      opts.options.section_separators = { left = "", right = "" }

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
      set_transparent_statusline()
      vim.schedule(set_transparent_statusline)
    end,
  },
}
