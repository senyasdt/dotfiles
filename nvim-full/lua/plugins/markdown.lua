return {
  {
    "MeanderingProgrammer/render-markdown.nvim",
    opts = function(_, opts)
      opts = opts or {}
      opts.enabled = false
      return opts
    end,
  },
}
