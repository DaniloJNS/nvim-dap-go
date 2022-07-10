local View = {}

function View:new(props)
    self.input = require('ui.components.input')
    self.props = props
    self.pos = 1
    self.storage = require('ultils.queue'):new()

    self.title = function ()
        return "Args " .. self.pos
    end

    self.increment = function ()
        self.pos = self.pos + 1
    end

    self.proxy = function ()
        local proxy = {}

        proxy.title = self.title()

        proxy.on_submit = function (value)
          self.storage:push(value)

          self.props.on_submit(self.storage.values)
        end

        return proxy
    end

    return self
end

function View:current_value()
    local value_with_prompt = vim.api.nvim_buf_get_lines(self.ui.bufnr, 0, 1, false)[1]
    return string.sub(value_with_prompt, self.ui._.prompt:length() + 1)
end

function View:regenerate_ui()
    self.storage:push(self:current_value())

    self.ui:unmount()

    self:generate_ui()
end


function View:generate_ui()
    self.ui = self.input(self.proxy())
    self.increment()

    self.ui:map("i", "+", function (_)
      self:regenerate_ui()
    end
    , { noremap = true })

    self.ui:mount()
end

function View:mount()
    self:generate_ui()
end

return View
