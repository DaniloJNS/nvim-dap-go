local helpers = require('helpers')

local Input = helpers.load_module("nui.input")
local event = helpers.load_module("nui.utils.autocmd").event


return function(props)
  local input = Input({
    position = "50%",
    size = {
        width = 30,
        height = 4,
    },
    relative = "editor",
    border = {
      style = "rounded",
      text = {
          top = props.title ,
          top_align = "center",
      },
    },
    win_options = {
      winblend = 20,
      winhighlight = "Normal:Normal",
    },
  }, {
    prompt = "> ",
    default_value = "",
    on_close = function ()
    end,
    on_submit = props.on_submit,
  })

  input:on(event.BufLeave, function()
    input:unmount()
  end)

  return input
end
