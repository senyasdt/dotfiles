local function random_onepiece_header()
  local ok, ascii = pcall(require, "ascii")
  if not ok then
    return {
      "  One Piece",
      "  ascii.nvim unavailable",
    }
  end

  local art = ascii.get_random("anime", "onepiece")
  if type(art) == "table" and #art > 0 then
    return art
  end

  return {
    "  One Piece",
    "  no art found",
  }
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

  -- {
  --   "snacks.nvim",
  --   opts = function(_, opts)
  --     opts.dashboard = opts.dashboard or {}
  --     opts.dashboard.preset = opts.dashboard.preset or {}
  --     opts.dashboard.preset.header = random_onepiece_header()
  --     return opts
  --   end,
  -- },
}
