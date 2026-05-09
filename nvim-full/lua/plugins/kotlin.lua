local root_files = {
  "settings.gradle",
  "settings.gradle.kts",
  "build.xml",
  "pom.xml",
  "build.gradle",
  "build.gradle.kts",
}

return {
  {
    "mason-org/mason.nvim",
    opts = function(_, opts)
      opts = opts or {}
      opts.ensure_installed = opts.ensure_installed or {}
      vim.list_extend(opts.ensure_installed, {
        "kotlin-language-server",
        "kotlin-debug-adapter",
      })
    end,
  },

  {
    "nvim-treesitter/nvim-treesitter",
    opts = function(_, opts)
      opts = opts or {}
      opts.ensure_installed = opts.ensure_installed or {}
      vim.list_extend(opts.ensure_installed, { "kotlin" })
    end,
  },

  {
    "neovim/nvim-lspconfig",
    opts = function(_, opts)
      local mason_bin = vim.fn.stdpath("data") .. "/mason/bin"

      opts = opts or {}
      opts.servers = opts.servers or {}
      opts.servers.kotlin_language_server = vim.tbl_deep_extend("force", opts.servers.kotlin_language_server or {}, {
        cmd = { mason_bin .. "/kotlin-language-server" },
        filetypes = { "kotlin" },
        root_markers = root_files,
        init_options = {
          storagePath = vim.fn.stdpath("cache") .. "/kotlin-language-server",
        },
        on_attach = function(client, _)
          client.server_capabilities.documentHighlightProvider = false
        end,
      })
    end,
  },

  {
    "mfussenegger/nvim-lint",
    optional = true,
    opts = function(_, opts)
      opts = opts or {}
      opts.linters_by_ft = opts.linters_by_ft or {}
      opts.linters_by_ft.kotlin = { "ktlint" }
    end,
  },

  {
    "mfussenegger/nvim-dap",
    optional = true,
    opts = function()
      local dap = require("dap")
      local mason_bin = vim.fn.stdpath("data") .. "/mason/bin"

      if not dap.adapters.kotlin then
        dap.adapters.kotlin = {
          type = "executable",
          command = mason_bin .. "/kotlin-debug-adapter",
          options = { auto_continue_if_many_stopped = false },
        }
      end

      dap.configurations.kotlin = {
        {
          type = "kotlin",
          request = "launch",
          name = "This file",
          mainClass = function()
            local root = vim.fs.find("src", { path = vim.uv.cwd(), upward = true, stop = vim.env.HOME })[1] or ""
            local fname = vim.api.nvim_buf_get_name(0)
            return fname:gsub(root, ""):gsub("main/kotlin/", ""):gsub(".kt", "Kt"):gsub("/", "."):sub(2, -1)
          end,
          projectRoot = "${workspaceFolder}",
          jsonLogFile = "",
          enableJsonLogging = false,
        },
        {
          type = "kotlin",
          request = "attach",
          name = "Attach to debugging session",
          port = 5005,
          args = {},
          projectRoot = vim.fn.getcwd,
          hostName = "127.0.0.1",
          timeout = 2000,
        },
      }
    end,
  },

  {
    "stevearc/conform.nvim",
    optional = true,
    opts = function(_, opts)
      opts = opts or {}
      opts.formatters_by_ft = opts.formatters_by_ft or {}
      opts.formatters_by_ft.kotlin = { "ktlint" }
    end,
  },
}
