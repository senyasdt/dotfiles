local function apply_transparent_highlights()
  local ok_palette, palette = pcall(require, "catppuccin.palettes")
  local colors = ok_palette and palette.get_palette("mocha") or {}

  local groups = {
    "Normal",
    "NormalNC",
    "SignColumn",
    "EndOfBuffer",
    "LineNr",
    "FoldColumn",
    "CursorLineNr",
    "NormalFloat",
    "FloatBorder",
    "FloatTitle",
    "Pmenu",
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

  -- Keep picker/search overlays dimmed by the theme instead of falling back to black.
  vim.api.nvim_set_hl(0, "FloatShadow", {
    bg = colors.mantle or colors.base or "#181825",
    blend = 60,
  })
  vim.api.nvim_set_hl(0, "FloatShadowThrough", {
    bg = colors.mantle or colors.base or "#181825",
    blend = 85,
  })
  vim.api.nvim_set_hl(0, "SnacksBackdrop", {
    bg = colors.mantle or colors.base or "#181825",
    blend = 60,
  })
end

return {
  {
    "catppuccin/nvim",
    name = "catppuccin",
    priority = 1000,
    opts = {
      flavour = "mocha",
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
          NormalFloat = { bg = c.none },
          FloatBorder = { bg = c.none },
          FloatTitle = { bg = c.none },
          Pmenu = { bg = c.none },
          PmenuSel = { bg = c.surface0 },
          WinSeparator = { bg = c.none },
          VertSplit = { bg = c.none },
        }
      end,
    },
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
      require("catppuccin").setup(opts)
      vim.cmd.colorscheme("catppuccin")
      apply_transparent_highlights()
    end,
  },
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = "catppuccin",
    },
  },
}
