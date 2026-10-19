-- ipynb/util.lua - Shared utility functions

local M = {}

---Get the plugin's root directory
---@return string
function M.get_plugin_root()
  local source = debug.getinfo(1, 'S').source:sub(2)
  return vim.fn.fnamemodify(source, ':h:h:h')
end

---Path of the WolframKernel executable (same search as the bridge), or nil
---@return string|nil
function M.find_wolfram_kernel()
  local py = vim.fn.executable('python3') == 1 and 'python3' or 'python'
  local script = M.get_plugin_root() .. '/python/wolfram_bridge.py'
  local res = vim.system({
    py, '-I', '-c',
    'import sys,importlib.util as u;s=u.spec_from_file_location("b",sys.argv[1]);m=u.module_from_spec(s);s.loader.exec_module(m);print(m.find_kernel() or "")',
    script,
  }, { text = true }):wait()
  local kernel = vim.trim(res.stdout or '')
  return kernel ~= '' and kernel or nil
end

return M
