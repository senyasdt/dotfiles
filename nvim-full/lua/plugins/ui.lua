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

local function patch_snacks_explorer_compact_dirs()
  local ok, Tree = pcall(require, "snacks.explorer.tree")
  if not ok or Tree._idea_compact_dirs then
    return
  end

  Tree._idea_compact_dirs = true

  ---@param self snacks.picker.explorer.Tree
  ---@param node snacks.picker.explorer.Node
  ---@param filter fun(child: snacks.picker.explorer.Node): boolean
  ---@param opts table
  local function auto_expand_single_dir_chain(self, node, filter, opts)
    local current = node

    while current and current.dir and current.open do
      if not current.expanded and opts.expand ~= false then
        self:expand(current)
      end

      local next_dir = nil
      local visible_children = 0

      for _, child in pairs(current.children) do
        if filter(child) then
          visible_children = visible_children + 1
          if visible_children > 1 or not child.dir then
            return
          end
          next_dir = child
        end
      end

      if visible_children == 1 and next_dir and next_dir.dir then
        next_dir.open = true
        current = next_dir
      else
        return
      end
    end
  end

  ---@param cwd string
  ---@param cb fun(node: snacks.picker.explorer.Node)
  ---@param opts? {expand?: boolean}|snacks.picker.explorer.Filter
  function Tree:get(cwd, cb, opts)
    opts = opts or {}
    assert(vim.fn.isdirectory(cwd) == 1, "Not a directory: " .. cwd)

    local node = self:find(cwd)
    node.open = true

    local filter = self:filter(opts)

    self:walk(node, function(n)
      if n ~= node and not filter(n) then
        return false
      end

      if n.dir and n.open then
        auto_expand_single_dir_chain(self, n, filter, opts)
      end

      cb(n)
    end)
  end
end

local function patch_snacks_explorer_compact_render()
  local ok_source, Explorer = pcall(require, "snacks.picker.source.explorer")
  local ok_actions, Actions = pcall(require, "snacks.explorer.actions")
  local ok_format, Format = pcall(require, "snacks.picker.format")
  local ok_tree, Tree = pcall(require, "snacks.explorer.tree")
  if not (ok_source and ok_actions and ok_format and ok_tree) then
    return
  end
  if Explorer._idea_compact_render then
    return
  end

  Explorer._idea_compact_render = true

  local explorer_original = Explorer.explorer
  local filename_original = Format.filename
  local confirm_original = Actions.actions.confirm
  local close_original = Actions.actions.explorer_close

  function Format.filename(item, picker)
    if item.compact_name and picker.opts.formatters.file.filename_only then
      local ret = {}
      if picker.opts.icons.files.enabled ~= false then
        local icon, hl = Snacks.util.icon(item.compact_name, item.dir and "directory" or "file", {
          fallback = picker.opts.icons.files,
        })
        if item.dir and item.open then
          icon = picker.opts.icons.files.dir_open
        end
        icon = Snacks.picker.util.align(icon, picker.opts.formatters.file.icon_width or 2)
        ret[#ret + 1] = { icon, hl, virtual = true }
      end

      local base_hl = item.dir and "SnacksPickerDirectory" or "SnacksPickerFile"
      local function is(prop)
        local it = item
        while it do
          if it[prop] then
            return true
          end
          it = it.parent
        end
      end

      if is("ignored") then
        base_hl = "SnacksPickerPathIgnored"
      elseif item.filename_hl then
        base_hl = item.filename_hl
      elseif is("hidden") then
        base_hl = "SnacksPickerPathHidden"
      end

      ret[#ret + 1] = { item.compact_name, base_hl, field = "file" }
      ret[#ret + 1] = { " " }
      return ret
    end
    return filename_original(item, picker)
  end

  function Actions.actions.confirm(picker, item, action)
    if item and item.dir and item.compact_toggle_path then
      local file = item.file
      item.file = item.compact_toggle_path
      confirm_original(picker, item, action)
      item.file = file
      return
    end
    confirm_original(picker, item, action)
  end

  function Actions.actions.explorer_close(picker, item)
    if item and item.compact_toggle_path then
      local file = item.file
      item.file = item.compact_toggle_path
      close_original(picker, item)
      item.file = file
      return
    end
    close_original(picker, item)
  end

  function Explorer.explorer(opts, ctx)
    local finder = explorer_original(opts, ctx)
    if ctx.picker.matcher.opts.keep_parents then
      return finder
    end

    return function(cb)
      local skipped = {}
      local items = {}
      local last = {}

      finder(function(item)
        if skipped[item.file] then
          return
        end

        local parent = item.parent and items[item.parent.file] or nil
        item.parent = parent

        if item.dir and item.open then
          local compact_names = { vim.fn.fnamemodify(item.file, ":t") }
          local current = Tree:node(item.file)
          local tail_paths = {}

          while current and current.expanded do
            local visible = {}
            for _, child in pairs(current.children) do
              if not child.hidden or opts.hidden then
                if not child.ignored or opts.ignored then
                  table.insert(visible, child)
                end
              end
            end

            if #visible ~= 1 or not visible[1].dir then
              break
            end

            current = visible[1]
            compact_names[#compact_names + 1] = current.name
            tail_paths[#tail_paths + 1] = current.path
          end

          if #compact_names > 1 then
            item.compact_name = table.concat(compact_names, "/")
            item.compact_toggle_path = item.file
            item.file = current.path
            item.text = current.path
            item.open = current.open
            item.type = current.type
            item.status = current.status or item.status
            item.dir_status = current.dir_status or item.dir_status
            item.severity = current.severity or item.severity

            for _, path in ipairs(tail_paths) do
              skipped[path] = true
            end
          end
        end

        local last_key = item.parent or "__root__"
        if last[last_key] then
          last[last_key].last = false
        end
        last[last_key] = item

        items[item.file] = item
        if item.compact_toggle_path then
          items[item.compact_toggle_path] = item
        end
        cb(item)
      end)
    end
  end
end

local function patch_snacks_transparent_backdrop()
  local ok_win, Win = pcall(require, "snacks.win")
  local ok_util, Util = pcall(require, "snacks.util")
  if not (ok_win and ok_util) or Win._ruantni_transparent_backdrop then
    return
  end

  Win._ruantni_transparent_backdrop = true

  function Win:drop()
    if self.backdrop then
      self.backdrop:close()
      self.backdrop = nil
    end

    local backdrop = self.opts.backdrop
    if not backdrop then
      return
    end

    backdrop = type(backdrop) == "number" and { blend = backdrop } or backdrop
    backdrop = backdrop == true and {} or backdrop
    backdrop = vim.tbl_extend("force", { bg = "#181825", blend = 50, transparent = true }, backdrop)

    if not vim.o.termguicolors or backdrop.blend == 100 or not self:is_floating() then
      return
    end

    local bg = backdrop.bg or "#181825"
    local winblend = backdrop.blend

    if not Util.is_transparent() and not backdrop.transparent then
      bg = Util.blend(Util.color("Normal", "bg"), bg, winblend / 100)
      winblend = 0
    end

    local group = ("SnacksBackdrop_%s"):format(bg and bg:sub(2) or "T")
    vim.api.nvim_set_hl(0, group, { bg = bg })

    self.backdrop = Win.new(Win.resolve({
      enter = false,
      backdrop = false,
      relative = "editor",
      height = 0,
      width = 0,
      style = "minimal",
      border = "none",
      focusable = false,
      zindex = self.opts.zindex - 1,
      wo = {
        winhighlight = "Normal:" .. group,
        winblend = winblend,
        colorcolumn = "",
      },
      bo = {
        buftype = "nofile",
        filetype = "snacks_win_backdrop",
      },
    }, backdrop.win))
  end
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

      opts.picker = opts.picker or {}
      opts.picker.layouts = opts.picker.layouts or {}
      opts.picker.layouts.default = vim.tbl_deep_extend("force", opts.picker.layouts.default or {}, {
        layout = {
          backdrop = {
            bg = "#181825",
            transparent = true,
            blend = 50,
          },
        },
      })

      return opts
    end,
    config = function(_, opts)
      require("snacks").setup(opts)
      patch_snacks_transparent_backdrop()
      patch_snacks_explorer_compact_dirs()
      patch_snacks_explorer_compact_render()
    end,
  },
}
