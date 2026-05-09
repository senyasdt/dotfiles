return {
  {
    "mfussenegger/nvim-dap",
    keys = {
      { "<F5>", function() require("dap").continue() end, desc = "Debug Continue" },
      { "<F7>", function() require("dap").step_into() end, desc = "Debug Step Into" },
      { "<F8>", function() require("dap").step_over() end, desc = "Debug Step Over" },
      { "<S-F8>", function() require("dap").step_out() end, desc = "Debug Step Out" },
      { "<F9>", function() require("dap").toggle_breakpoint() end, desc = "Debug Toggle Breakpoint" },
      { "<S-F9>", function() require("dap").terminate() end, desc = "Debug Terminate" },
    },
  },
}
