local query = require "vim.treesitter.query"
local helpers = require('helpers')
local view = require('ui.view.args')

local M = {}

local tests_query = [[
(function_declaration
  name: (identifier) @testname
  parameters: (parameter_list
    . (parameter_declaration
      type: (pointer_type) @type) .)
  (#match? @type "*testing.(T|M)")
  (#match? @testname "^Test.+$")) @parent
]]

local subtests_query = [[
(call_expression
  function: (selector_expression
    operand: (identifier)
    field: (field_identifier) @run)
  arguments: (argument_list
    (interpreted_string_literal) @testname
    (func_literal))
  (#eq? @run "Run")) @parent
]]

local function setup_go_adapter(dap)
  dap.adapters.go = function(callback, config)
    local stdout = vim.loop.new_pipe(false)
    local handle
    local pid_or_err
    local host = config.host or "127.0.0.1"
    local port = config.port or "38697"
    local addr = string.format("%s:%s", host, port)
   if (config.request == "attach" and config.mode == "remote") then
      -- Not starting delve server automatically in "Attach remote."
      -- Will connect to delve server that is listening to [host]:[port] instead.
      -- Users can use this with delve headless mode:
      --
      -- dlv debug -l 127.0.0.1:38697 --headless ./cmd/main.go
      --
      local msg = string.format("connecting to server at '%s'...", addr)
      print(msg)
    else
      local opts = {
        stdio = {nil, stdout},
        args = {"dap", "-l", addr},
        detached = true
      }
      handle, pid_or_err = vim.loop.spawn("dlv", opts, function(code)
        stdout:close()
        handle:close()
        if code ~= 0 then
          print('dlv exited with code', code)
        end
      end)
      assert(handle, 'Error running dlv: ' .. tostring(pid_or_err))
      stdout:read_start(function(err, chunk)
        assert(not err, err)
        if chunk then
          vim.schedule(function()
            require('dap.repl').append(chunk)
          end)
        end
      end)
    end
    -- Wait for delve to start
    vim.defer_fn(
      function()
        callback({type = "server", host = host, port = port})
      end,
      100)
  end
end

local function setup_go_configuration(dap)
  dap.configurations.go = {
    {
      type = "go",
      name = "Debug",
      request = "launch",
      program = "${file}",
    },
    {
      type = "go",
      name = "Debug Package",
      request = "launch",
      program = "${fileDirname}",
    },
    {
      type = "go",
      name = "Attach remote",
      mode = "remote",
      request = "attach",
    },
    {
      type = "go",
      name = "Attach",
      mode = "local",
      request = "attach",
      processId = require('dap.utils').pick_process,
    },
    {
      type = "go",
      name = "Debug test",
      request = "launch",
      mode = "test",
      program = "${file}",
    },
    {
      type = "go",
      name = "Debug test (go.mod)",
      request = "launch",
      mode = "test",
      program = "./${relativeFileDirname}",
    }
  }
end

function M.setup()
  local dap = helpers.load_module("dap")
  setup_go_adapter(dap)
  setup_go_configuration(dap)
end

local function debug_test(testname)
  local dap = helpers.load_module("dap")
  dap.run({
      type = "go",
      name = testname,
      request = "launch",
      mode = "test",
      program = "./${relativeFileDirname}",
      args = {"-test.run", testname},
  })
end

local function get_closest_above_cursor(test_tree)
  local result
  for _, curr in pairs(test_tree) do
    if not result then
      result = curr
    else
      local node_row1, _, _, _ = curr.node:range()
      local result_row1, _, _, _ = result.node:range()
      if node_row1 > result_row1 then
        result = curr
      end
    end
  end
  if result.parent then
    return string.format("%s/%s", result.parent, result.name)
  else
    return result.name
  end
end


local function is_parent(dest, source)
  if not (dest and source) then
    return false
  end
  if dest == source then
    return false
  end

  local current = source
  while current ~= nil do
    if current == dest then
      return true
    end

    current = current:parent()
  end

  return false
end

local function get_closest_test()
  local stop_row = vim.api.nvim_win_get_cursor(0)[1]
  local ft = vim.api.nvim_buf_get_option(0, 'filetype')
  assert(ft == 'go', 'dap-go error: can only debug go files, not '..ft)
  local parser = vim.treesitter.get_parser(0)
  local root = (parser:parse()[1]):root()

  local test_tree = {}

  local test_query = vim.treesitter.parse_query(ft, tests_query)
  assert(test_query, 'dap-go error: could not parse test query')
  for _, match, _ in test_query:iter_matches(root, 0, 0, stop_row) do
    local test_match = {}
    for id, node in pairs(match) do
      local capture = test_query.captures[id]
      if capture == "testname" then
        local name = query.get_node_text(node, 0)
        test_match.name = name
      end
      if capture == "parent" then
        test_match.node = node
      end
    end
    table.insert(test_tree, test_match)
  end

  local subtest_query = vim.treesitter.parse_query(ft, subtests_query)
  assert(subtest_query, 'dap-go error: could not parse test query')
  for _, match, _ in subtest_query:iter_matches(root, 0, 0, stop_row) do
    local test_match = {}
    for id, node in pairs(match) do
      local capture = subtest_query.captures[id]
      if capture == "testname" then
        local name = query.get_node_text(node, 0)
        test_match.name = string.gsub(string.gsub(name, ' ', '_'), '"', '')
      end
      if capture == "parent" then
        test_match.node = node
      end
    end
    table.insert(test_tree, test_match)
  end

  table.sort(test_tree, function(a, b)
    return is_parent(a.node, b.node)
  end)

  for _, parent in ipairs(test_tree) do
    for _, child in ipairs(test_tree) do
      if is_parent(parent.node, child.node) then
        child.parent = parent.name
      end
    end
  end

  return get_closest_above_cursor(test_tree)
end

function M.debug_test()
  local testname = get_closest_test()
  local msg = string.format("starting debug session '%s'...", testname)
  print(msg)
  debug_test(testname)
end

local function run_with_args(value)
      local dap = helpers.load_module("dap")
      dap.run({
          type = "go",
          name = "Debug",
          request = "launch",
          program = "${file}",
          args = value,
      })
end

function M.debug_with_args()
  local input = view:new({ on_submit = run_with_args })

  input:mount()
end

return M
