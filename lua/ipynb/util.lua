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

---Cells with very long lines make tree-sitter highlighting crawl (every redraw re-runs the
---queries over the whole line), so they are shown without syntax colors.
---@param text string|string[]
---@return boolean
function M.too_long_to_highlight(text)
  local max_line = vim.g.wlnb_highlight_max_line or 1200
  local max_bytes = vim.g.wlnb_highlight_max_bytes or 60000
  local lines = type(text) == 'table' and text or vim.split(text, '\n', { plain = true })
  local bytes = 0
  for _, line in ipairs(lines) do
    if #line > max_line then
      return true
    end
    bytes = bytes + #line + 1
  end
  return bytes > max_bytes
end

return M
