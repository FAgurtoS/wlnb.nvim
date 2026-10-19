-- Wolfram syntax highlighting inside code cells of a .wlnb (tree-sitter-wolfram injection)
-- Run with: nvim --headless -u tests/minimal_init.lua -l tests/test_wolfram_highlight.lua

local h = require('tests.helpers')
vim.g.wlnb_highlight = 'treesitter' -- these tests cover the tree-sitter colors; wl_highlight has its own tests

print('')
print(string.rep('=', 60))
print('Running Wolfram highlight tests')
print(string.rep('=', 60))
print('')

local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')

h.run_test('wolfram_parser_and_highlight_query_load', function()
  -- the parser compiles lazily on first load; wait for it
  vim.wait(60000, function()
    return pcall(vim.treesitter.language.inspect, 'wolfram')
  end, 200)
  h.assert_true(pcall(vim.treesitter.language.inspect, 'wolfram'), 'wolfram parser not installed')
  local query = vim.treesitter.query.get('wolfram', 'highlights')
  h.assert_true(query ~= nil, 'wolfram highlights query failed to load')
end)

h.run_test('code_cells_get_wolfram_captures', function()
  local state = h.open_notebook_path(root .. '/tests/fixtures/wlnb/basic.wlnb')
  vim.treesitter.get_parser(state.facade_buf):parse(true)
  local cells_mod = require('ipynb.cells')
  local start_line = cells_mod.get_cell_range(state, 2) -- 0-indexed start marker
  -- content line is start marker + 1: "Integrate[Sin[x]^2, x]"
  local caps = vim.treesitter.get_captures_at_pos(state.facade_buf, start_line + 1, 2)
  local names = {}
  for _, c in ipairs(caps) do
    names[#names + 1] = c.lang .. ':' .. c.capture
  end
  local joined = table.concat(names, ',')
  h.assert_true(joined:find('wolfram:function', 1, true) ~= nil, 'no wolfram function capture; got: ' .. joined)
end)

local success = h.summary()
if success then
  vim.cmd('qa!')
else
  vim.cmd('cquit 1')
end
