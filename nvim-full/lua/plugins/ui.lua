local function random_logo_builder()
  local ok, ascii = pcall(require, "ascii")
  if not ok then
    return {
      "  One Piece",
      "  ascii.nvim unavailable",
    }
  end

  -- local art = ascii.get_random("anime", "onepiece")
  local art = ascii.get_random("text", "neovim")
  if type(art) == "table" and #art > 0 then
    return table.concat(art, "\n")
  end

  return "  One Piece\n  no art found"
end

return {
  -- {
  --   "catppuccin/nvim",
  --   name = "catppuccin",
  --   opts = {
  --     transparent_background = true,
  --   },
  -- },
  --
  -- {
  --   "LazyVim/LazyVim",
  --   opts = {
  --     colorscheme = "catppuccin",
  --   },
  -- },

  {
    "MaximilianLloyd/ascii.nvim",
    dependencies = { "MunifTanjim/nui.nvim" },
  },

  {
    "folke/snacks.nvim",
    opts = function(_, opts)
      opts.dashboard = opts.dashboard or {}
      opts.dashboard.preset = opts.dashboard.preset or {}
      opts.dashboard.preset.header = random_logo_builder()
      return opts
    end,
  },
}
