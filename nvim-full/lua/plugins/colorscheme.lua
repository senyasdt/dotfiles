return {
  {
    "folke/tokyonight.nvim",
    opts = {
      transparent = true,
      on_highlights = function(hl, c)
        hl.CursorLine = {
          bg = "none",
          underline = true,
          sp = c.fg_gutter,
        }
      end,
      styles = {
        sidebars = "transparent",
        floats = "transparent",
      },
    },
  },
}
