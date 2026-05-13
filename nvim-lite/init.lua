-- Sourced from https://github.com/nvim-lua/kickstart.nvim (master/init.lua)

--[[

=====================================================================
==================== READ THIS BEFORE CONTINUING ====================
=====================================================================
========                                    .-----.          ========
========         .----------------------.   | === |          ========
========         |.-""""""""""""""""""-.|   |-----|          ========
========         ||                    ||   | === |          ========
========         ||   KICKSTART.NVIM   ||   |-----|          ========
========         ||                    ||   | === |          ========
========         ||                    ||   |-----|          ========
========         ||:Tutor              ||   |:::::|          ========
========         |'-..................-'|   |____o|          ========
========         `"")----------------(""`   ___________      ========
========        /::::::::::|  |::::::::::\  \ no mouse \     ========
========       /:::========|  |==hjkl==:::\  \ required \    ========
========      '""""""""""""'  '""""""""""""'  '""""""""""'   ========
========                                                     ========
=====================================================================
=====================================================================

What is Kickstart?

  Kickstart.nvim is *not* a distribution.

  Kickstart.nvim is a starting point for your own configuration.
    The goal is that you can read every line of code, top-to-bottom, understand
    what your configuration is doing, and modify it to suit your needs.

    Once you've done that, you can start exploring, configuring and tinkering to
    make Neovim your own! That might mean leaving Kickstart just the way it is for a while
    or immediately breaking it into modular pieces. It's up to you!

    If you don't know anything about Lua, I recommend taking some time to read through
    a guide. One possible example which will only take 10-15 minutes:
      - https://learnxinyminutes.com/docs/lua/

    After understanding a bit more about Lua, you can use `:help lua-guide` as a
    reference for how Neovim integrates Lua.
    - :help lua-guide
    - (or HTML version): https://neovim.io/doc/user/lua-guide.html

Kickstart Guide:

  TODO: The very first thing you should do is to run the command `:Tutor` in Neovim.

    If you don't know what this means, type the following:
      - <escape key>
      - :
      - Tutor
      - <enter key>

    (If you already know the Neovim basics, you can skip this step.)

  Once you've completed that, you can continue working through **AND READING** the rest
  of the kickstart init.lua.

  Next, run AND READ `:help`.
    This will open up a help window with some basic information
    about reading, navigating and searching the builtin help documentation.

    This should be the first place you go to look when you're stuck or confused
    with something. It's one of my favorite Neovim features.

    MOST IMPORTANTLY, we provide a keymap "<space>sh" to [s]earch the [h]elp documentation,
    which is very useful when you're not exactly sure of what you're looking for.

  I have left several `:help X` comments throughout the init.lua
    These are hints about where to find more information about the relevant settings,
    plugins or Neovim features used in Kickstart.

   NOTE: Look for lines like this

    Throughout the file. These are for you, the reader, to help you understand what is happening.
    Feel free to delete them once you know what you're doing, but they should serve as a guide
    for when you are first encountering a few different constructs in your Neovim config.

If you experience any errors while trying to install kickstart, run `:checkhealth` for more info.

I hope you enjoy your Neovim journey,
- TJ

P.S. You can delete this when you're done too. It's your config now! :)
--]]

vim.g.mapleader = ' '
vim.g.maplocalleader = ' '
vim.g.have_nerd_font = false

vim.o.number = true
vim.o.mouse = 'a'
vim.o.showmode = true
vim.schedule(function() vim.o.clipboard = 'unnamedplus' end)
vim.o.breakindent = true
vim.o.undofile = true
vim.o.ignorecase = true
vim.o.smartcase = true
vim.o.signcolumn = 'yes'
vim.o.updatetime = 250
vim.o.timeoutlen = 300
vim.o.splitright = true
vim.o.splitbelow = true
vim.o.list = true
vim.opt.listchars = { tab = '» ', trail = '·', nbsp = '␣' }
vim.o.inccommand = 'split'
vim.o.guicursor = 'n-v-c:block-blinkoff0,i-ci-ve:ver25-blinkoff0,r-cr:hor20-blinkoff0,o:hor50-blinkoff0'
vim.o.cursorline = true
vim.o.scrolloff = 10
vim.o.confirm = true
vim.o.showtabline = 2
vim.opt.shortmess:append 'I'

vim.keymap.set('n', '<Esc>', '<cmd>nohlsearch<CR>')
vim.keymap.set('i', 'jj', '<Esc>', { desc = 'Exit insert mode' })
vim.keymap.set({ 'i', 'x', 'n', 's' }, '<C-s>', '<cmd>w<CR><Esc>', { desc = 'Save file' })
vim.keymap.set('n', '<leader>ww', '<cmd>w<CR>', { desc = 'Write file' })
vim.keymap.set('n', '<leader>qq', '<cmd>confirm q<CR>', { desc = 'Quit window' })

vim.diagnostic.config {
  update_in_insert = false,
  severity_sort = true,
  float = { border = 'rounded', source = 'if_many' },
  underline = { severity = { min = vim.diagnostic.severity.WARN } },
  virtual_text = true,
  virtual_lines = false,
  jump = { float = true },
}

vim.keymap.set('n', '<leader>xL', vim.diagnostic.setloclist, { desc = 'Location list diagnostics' })
vim.keymap.set('t', '<Esc><Esc>', '<C-\\><C-n>', { desc = 'Exit terminal mode' })
vim.keymap.set('n', '<C-h>', '<C-w><C-h>', { desc = 'Move focus to the left window' })
vim.keymap.set('n', '<C-l>', '<C-w><C-l>', { desc = 'Move focus to the right window' })
vim.keymap.set('n', '<C-j>', '<C-w><C-j>', { desc = 'Move focus to the lower window' })
vim.keymap.set('n', '<C-k>', '<C-w><C-k>', { desc = 'Move focus to the upper window' })
vim.keymap.set('n', '<leader>wh', '<C-w><C-h>', { desc = 'Focus left window', remap = true })
vim.keymap.set('n', '<leader>wl', '<C-w><C-l>', { desc = 'Focus right window', remap = true })
vim.keymap.set('n', '<leader>wj', '<C-w><C-j>', { desc = 'Focus lower window', remap = true })
vim.keymap.set('n', '<leader>wk', '<C-w><C-k>', { desc = 'Focus upper window', remap = true })
vim.keymap.set('n', '<S-h>', '<cmd>bprevious<CR>', { desc = 'Previous buffer' })
vim.keymap.set('n', '<S-l>', '<cmd>bnext<CR>', { desc = 'Next buffer' })
vim.keymap.set('n', '<leader>bp', '<cmd>bprevious<CR>', { desc = 'Previous buffer' })
vim.keymap.set('n', '<leader>bn', '<cmd>bnext<CR>', { desc = 'Next buffer' })
vim.keymap.set('n', '<leader>bb', '<cmd>e #<CR>', { desc = 'Switch to other buffer' })
vim.keymap.set('n', '<leader>bd', '<cmd>bdelete<CR>', { desc = 'Delete buffer' })
vim.keymap.set('n', '<leader>bo', '<cmd>%bdelete|edit#|bdelete#<CR>', { desc = 'Delete other buffers' })
vim.keymap.set('n', '<leader>-', '<C-W>s', { desc = 'Split window below', remap = true })
vim.keymap.set('n', '<leader>|', '<C-W>v', { desc = 'Split window right', remap = true })
vim.keymap.set('n', '<leader>wq', '<C-W>c', { desc = 'Quit window', remap = true })
vim.keymap.set('n', '<leader>fl', '<cmd>edit .<CR>', { desc = 'List current directory' })

function _G.lite_tabline()
  local parts = {}
  local current = vim.api.nvim_get_current_buf()

  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.bo[bufnr].buflisted then
      local name = vim.api.nvim_buf_get_name(bufnr)
      local label = name == '' and '[No Name]' or vim.fn.fnamemodify(name, ':t')
      local modified = vim.bo[bufnr].modified and ' [+]' or ''
      local hl = bufnr == current and '%#TabLineSel#' or '%#TabLine#'
      table.insert(parts, string.format('%s %d:%s%s ', hl, bufnr, label, modified))
    end
  end

  table.insert(parts, '%#TabLineFill#%=')
  return table.concat(parts)
end

vim.o.tabline = '%!v:lua.lite_tabline()'

vim.api.nvim_create_autocmd('TextYankPost', {
  desc = 'Highlight when yanking (copying) text',
  group = vim.api.nvim_create_augroup('kickstart-highlight-yank', { clear = true }),
  callback = function() vim.hl.on_yank() end,
})

local shared_nvim_data = vim.fn.expand '~/.local/share/nvim'
local lazypath = shared_nvim_data .. '/lazy/lazy.nvim'
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  local lazyrepo = 'https://github.com/folke/lazy.nvim.git'
  local out = vim.fn.system { 'git', 'clone', '--filter=blob:none', '--branch=stable', lazyrepo, lazypath }
  if vim.v.shell_error ~= 0 then error('Error cloning lazy.nvim:\n' .. out) end
end

---@type vim.Option
local rtp = vim.opt.rtp
rtp:prepend(lazypath)

local function open_file_under_config()
  local path = vim.fn.input('Config file: ', vim.fn.stdpath 'config' .. '/', 'file')
  if path ~= '' then
    vim.cmd.edit(vim.fn.fnameescape(path))
  end
end

local function find_files_builtin()
  local path = vim.fn.input('Open file: ', vim.fn.getcwd() .. '/', 'file')
  if path ~= '' then
    vim.cmd.edit(vim.fn.fnameescape(path))
  end
end

local function grep_builtin()
  local pattern = vim.fn.input 'Grep > '
  if pattern == '' then
    return
  end

  vim.cmd('silent grep! ' .. vim.fn.shellescape(pattern))
  vim.cmd.copen()
end

local function grep_word_builtin()
  local word = vim.fn.expand '<cword>'
  if word == '' then
    return
  end

  vim.cmd('silent grep! ' .. vim.fn.shellescape(word))
  vim.cmd.copen()
end

vim.keymap.set('n', '<leader><space>', find_files_builtin, { desc = 'Find files' })
vim.keymap.set('n', '<leader>,', '<cmd>buffers<CR>', { desc = 'Buffers' })
vim.keymap.set('n', '<leader><leader>', '<cmd>buffers<CR>', { desc = '[ ] Find existing buffers' })
vim.keymap.set('n', '<leader>ff', find_files_builtin, { desc = 'Find files' })
vim.keymap.set('n', '<leader>fF', find_files_builtin, { desc = 'Find files (cwd)' })
vim.keymap.set('n', '<leader>fr', '<cmd>oldfiles<CR>', { desc = 'Recent files' })
vim.keymap.set('n', '<leader>fb', '<cmd>buffers<CR>', { desc = 'Buffers' })
vim.keymap.set('n', '<leader>fc', open_file_under_config, { desc = 'Find config file' })
vim.keymap.set('n', '<leader>sh', '<cmd>help<CR>', { desc = '[S]earch [H]elp' })
vim.keymap.set('n', '<leader>sk', '<cmd>map<CR>', { desc = '[S]earch [K]eymaps' })
vim.keymap.set('n', '<leader>sf', find_files_builtin, { desc = '[S]earch [F]iles' })
vim.keymap.set({ 'n', 'v' }, '<leader>sw', grep_word_builtin, { desc = '[S]earch current [W]ord' })
vim.keymap.set('n', '<leader>sg', grep_builtin, { desc = '[S]earch by [G]rep' })
vim.keymap.set('n', '<leader>sd', '<cmd>lua vim.diagnostic.setqflist()<CR><cmd>copen<CR>', { desc = '[S]earch [D]iagnostics' })
vim.keymap.set('n', '<leader>sr', '<cmd>oldfiles<CR>', { desc = '[S]earch [R]esume' })
vim.keymap.set('n', '<leader>s.', '<cmd>oldfiles<CR>', { desc = '[S]earch Recent Files (\".\" for repeat)' })
vim.keymap.set('n', '<leader>sc', '<cmd>command<CR>', { desc = '[S]earch [C]ommands' })
vim.keymap.set('n', '<leader>ss', vim.lsp.buf.document_symbol, { desc = 'Document symbols' })
vim.keymap.set('n', '<leader>sS', function() vim.lsp.buf.workspace_symbol(vim.fn.input 'Workspace symbols > ') end, { desc = 'Workspace symbols' })
vim.keymap.set('n', '<leader>/', '<cmd>normal! /<CR>', { desc = 'Search in current buffer' })
vim.keymap.set('n', '<leader>s/', grep_builtin, { desc = '[S]earch [/] in Open Files' })
vim.keymap.set('n', '<leader>sn', open_file_under_config, { desc = '[S]earch [N]eovim files' })
vim.keymap.set('n', '<leader>xx', '<cmd>lua vim.diagnostic.setqflist()<CR><cmd>copen<CR>', { desc = 'Diagnostics' })
vim.keymap.set('n', '<leader>xX', '<cmd>lua vim.diagnostic.setloclist()<CR><cmd>lopen<CR>', { desc = 'Buffer diagnostics' })
vim.keymap.set('n', '<leader>xq', '<cmd>copen<CR>', { desc = 'Quickfix list' })
vim.keymap.set('n', '<leader>xl', '<cmd>lopen<CR>', { desc = 'Location list' })

require('lazy').setup({
  {
    'lewis6991/gitsigns.nvim',
    ---@module 'gitsigns'
    ---@type Gitsigns.Config
    ---@diagnostic disable-next-line: missing-fields
    opts = {
      signs = {
        add = { text = '+' }, ---@diagnostic disable-line: missing-fields
        change = { text = '~' }, ---@diagnostic disable-line: missing-fields
        delete = { text = '_' }, ---@diagnostic disable-line: missing-fields
        topdelete = { text = '‾' }, ---@diagnostic disable-line: missing-fields
        changedelete = { text = '~' }, ---@diagnostic disable-line: missing-fields
      },
    },
  },
  {
    'folke/which-key.nvim',
    event = 'VimEnter',
    ---@module 'which-key'
    ---@type wk.Opts
    ---@diagnostic disable-next-line: missing-fields
    opts = {
      delay = 0,
      preset = 'helix',
      icons = { mappings = vim.g.have_nerd_font },
      win = {
        width = { min = 30, max = 60 },
        height = { min = 4, max = 0.75 },
        col = -1,
        row = -1,
        border = 'rounded',
        title = true,
        title_pos = 'left',
      },
      spec = {
        { '<leader><tab>', group = '[T]abs' },
        { '<leader>b', group = '[B]uffer' },
        { '<leader>c', group = '[C]ode' },
        { '<leader>f', group = '[F]ind/[F]ile' },
        { '<leader>q', group = '[Q]uit' },
        { '<leader>s', group = '[S]earch', mode = { 'n', 'v' } },
        { '<leader>t', group = '[T]oggle' },
        { '<leader>u', group = '[U]I' },
        { '<leader>w', group = '[W]indows' },
        { '<leader>x', group = 'Diagnostics/Quickfix' },
        { '<leader>h', group = 'Git [H]unk', mode = { 'n', 'v' } },
        { 'gr', group = 'LSP Actions', mode = { 'n' } },
      },
    },
    keys = {
      {
        '<leader>?',
        function() require('which-key').show { global = false } end,
        desc = 'Buffer keymaps',
      },
      {
        '<C-w><space>',
        function() require('which-key').show { keys = '<C-w>', loop = true } end,
        desc = 'Window Hydra Mode',
      },
    },
  },
  {
    'neovim/nvim-lspconfig',
    config = function()
      vim.api.nvim_create_autocmd('LspAttach', {
        group = vim.api.nvim_create_augroup('kickstart-lsp-attach', { clear = true }),
        callback = function(event)
          local map = function(keys, func, desc, mode)
            mode = mode or 'n'
            vim.keymap.set(mode, keys, func, { buffer = event.buf, desc = 'LSP: ' .. desc })
          end

          map('grr', vim.lsp.buf.references, '[G]oto [R]eferences')
          map('gri', vim.lsp.buf.implementation, '[G]oto [I]mplementation')
          map('grd', vim.lsp.buf.definition, '[G]oto [D]efinition')
          map('grn', vim.lsp.buf.rename, '[R]e[n]ame')
          map('gra', vim.lsp.buf.code_action, '[G]oto Code [A]ction', { 'n', 'x' })
          map('grD', vim.lsp.buf.declaration, '[G]oto [D]eclaration')
          map('grt', vim.lsp.buf.type_definition, '[G]oto [T]ype Definition')
          map('gO', vim.lsp.buf.document_symbol, 'Document Symbols')
          map('gW', vim.lsp.buf.workspace_symbol, 'Workspace Symbols')

          local client = vim.lsp.get_client_by_id(event.data.client_id)
          if client and client:supports_method('textDocument/documentHighlight', event.buf) then
            local highlight_augroup = vim.api.nvim_create_augroup('kickstart-lsp-highlight', { clear = false })
            vim.api.nvim_create_autocmd({ 'CursorHold', 'CursorHoldI' }, {
              buffer = event.buf,
              group = highlight_augroup,
              callback = vim.lsp.buf.document_highlight,
            })

            vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI' }, {
              buffer = event.buf,
              group = highlight_augroup,
              callback = vim.lsp.buf.clear_references,
            })

            vim.api.nvim_create_autocmd('LspDetach', {
              group = vim.api.nvim_create_augroup('kickstart-lsp-detach', { clear = true }),
              callback = function(event2)
                vim.lsp.buf.clear_references()
                vim.api.nvim_clear_autocmds { group = 'kickstart-lsp-highlight', buffer = event2.buf }
              end,
            })
          end

          if client and client:supports_method('textDocument/inlayHint', event.buf) then
            map('<leader>th', function() vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled { bufnr = event.buf }) end, '[T]oggle Inlay [H]ints')
          end
        end,
      })

      local servers = {
        lua_ls = {
          on_init = function(client)
            if client.workspace_folders then
              local path = client.workspace_folders[1].name
              if path ~= vim.fn.stdpath 'config' and (vim.uv.fs_stat(path .. '/.luarc.json') or vim.uv.fs_stat(path .. '/.luarc.jsonc')) then return end
            end

            client.config.settings.Lua = vim.tbl_deep_extend('force', client.config.settings.Lua, {
              runtime = {
                version = 'LuaJIT',
                path = { 'lua/?.lua', 'lua/?/init.lua' },
              },
              workspace = {
                checkThirdParty = false,
                library = vim.tbl_extend('force', vim.api.nvim_get_runtime_file('', true), {
                  '${3rd}/luv/library',
                  '${3rd}/busted/library',
                }),
              },
            })
          end,
          settings = {
            Lua = {},
          },
        },
      }

      for name, server in pairs(servers) do
        vim.lsp.config(name, server)
        vim.lsp.enable(name)
      end
    end,
  },
  {
    'stevearc/conform.nvim',
    event = { 'BufWritePre' },
    cmd = { 'ConformInfo' },
    keys = {
      {
        '<leader>f',
        function() require('conform').format { async = true, lsp_format = 'fallback' } end,
        mode = '',
        desc = '[F]ormat buffer',
      },
    },
    ---@module 'conform'
    ---@type conform.setupOpts
    opts = {
      notify_on_error = false,
      format_on_save = function(bufnr)
        local disable_filetypes = { c = true, cpp = true }
        if disable_filetypes[vim.bo[bufnr].filetype] then
          return nil
        else
          return {
            timeout_ms = 500,
            lsp_format = 'fallback',
          }
        end
      end,
      formatters_by_ft = {
        lua = { 'stylua' },
      },
    },
  },
  {
    'saghen/blink.cmp',
    event = 'VimEnter',
    version = '1.*',
    ---@module 'blink.cmp'
    ---@type blink.cmp.Config
    opts = {
      keymap = {
        preset = 'default',
      },
      appearance = {
        nerd_font_variant = 'mono',
      },
      completion = {
        documentation = { auto_show = false, auto_show_delay_ms = 500 },
      },
      sources = {
        default = { 'lsp', 'path', 'buffer' },
      },
      cmdline = {
        keymap = { preset = 'inherit' },
        completion = {
          menu = {
            auto_show = function() return vim.fn.getcmdtype() == ':' end,
          },
        },
      },
      fuzzy = { implementation = 'lua' },
      signature = { enabled = true },
    },
  },
  {
    'catppuccin/nvim',
    name = 'catppuccin',
    priority = 1000,
    config = function()
      require('catppuccin').setup {
        transparent_background = true,
      }

      vim.cmd.colorscheme 'catppuccin'
    end,
  },
}, { ---@diagnostic disable-line: missing-fields
  root = shared_nvim_data .. '/lazy',
  lockfile = vim.fn.expand '~/.config/nvim/lazy-lock.json',
  ui = {
    icons = vim.g.have_nerd_font and {} or {
      cmd = '⌘',
      config = '🛠',
      event = '📅',
      ft = '📂',
      init = '⚙',
      keys = '🗝',
      plugin = '🔌',
      runtime = '💻',
      require = '🌙',
      source = '📄',
      start = '🚀',
      task = '📌',
      lazy = '💤 ',
    },
  },
})

-- vim: ts=2 sts=2 sw=2 et
