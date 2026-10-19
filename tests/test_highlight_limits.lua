-- Cells with very long lines are not syntax highlighted (they made redraws crawl)
-- Run with: nvim --headless -u tests/minimal_init.lua -l tests/test_highlight_limits.lua

local h = require('tests.helpers')
vim.g.wlnb_highlight = 'treesitter' -- these tests cover the tree-sitter colors; wl_highlight has its own tests

print('')
print(string.rep('=', 60))
print('Running highlight limit tests')
print(string.rep('=', 60))
print('')

local function wolfram_regions(buf)
  local parser = vim.treesitter.get_parser(buf, 'ipynb')
  parser:parse(true)
  local child = parser:children().wolfram
  return child and #child:trees() or 0
end

h.run_test('long_lines_cell_is_not_injected_short_one_is', function()
  local util = require('ipynb.util')
  h.assert_true(util.too_long_to_highlight({ string.rep('x', 5000) }), 'long line detected')
  h.assert_true(not util.too_long_to_highlight({ 'Plot[x, {x, 0, 1}]' }), 'short cell fine')

  local tmp = vim.fn.tempname() .. '.wlnb'
  vim.fn.writefile({
    '(* ::wlnb:: v1 *)', '',
    '(* ::cell:: input *)', 'Plot[Sin[x], {x, 0, 1}]', '',
    '(* ::cell:: input *)', 'y = ' .. string.rep('a + ', 1500) .. '1',
  }, tmp)
  local state = h.open_notebook_path(tmp)
  vim.wait(300)
  h.assert_eq(wolfram_regions(state.facade_buf), 1) -- only the short cell is highlighted
  vim.fn.delete(tmp)
end)

local success = h.summary()
if success then
  vim.cmd('qa!')
else
  vim.cmd('cquit 1')
end
