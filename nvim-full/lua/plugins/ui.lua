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
