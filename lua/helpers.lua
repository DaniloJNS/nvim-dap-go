local M = {}


function M.load_module(module_name)
  local ok, module = pcall(require, module_name)
  assert(ok, string.format('dap-go dependency error: %s not installed', module_name))
  return module
end

return M
