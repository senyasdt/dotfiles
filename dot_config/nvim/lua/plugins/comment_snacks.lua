return {
  "folke/snacks.nvim",
  opts = function(_, opts)
    Snacks.toggle({
      name = "Auto Comment",
      get = function()
        local fopt = vim.opt.formatoptions:get()
        return fopt.r ~= nil and fopt.o ~= nil
      end,
      set = function(state)
        local fo = vim.opt_local.formatoptions:get()
        if state then
          fo.r = true
          fo.o = true
        else
          fo.r = nil
          fo.o = nil
        end
        vim.opt_local.formatoptions = fo
      end,
    }):map("<leader>u/")
  end,
}
