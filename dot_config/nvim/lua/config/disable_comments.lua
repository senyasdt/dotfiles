local Snacks = require("snacks") -- <- добавьте это
local comment = require("config.commands")

return Snacks.toggle
  .new({
    id = "auto_comments",
    name = "Auto Comments",
    get = function()
      return comment.is_enabled()
    end,
    set = function(state)
      if state then
        comment.enable()
      else
        comment.disable()
      end
    end,
  })
  :map("<leader>u<Bslash>")
