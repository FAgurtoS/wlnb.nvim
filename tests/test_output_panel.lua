-- Output panel: current cell's output as real text in a split (visual mode + yank work)
-- Run with: nvim --headless -u tests/minimal_init.lua -l tests/test_output_panel.lua

local h = require('tests.helpers')

print('')
print(string.rep('=', 60))
print('Running output panel tests')
print(string.rep('=', 60))
print('')

local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')
local panel = require('ipynb.panel')

h.run_test('panel_shows_plain_output_of_current_cell_and_follows_cursor', function()
  local tmp = vim.fn.tempname() .. '.wlnb'
  vim.fn.writefile(vim.fn.readfile(root .. '/tests/fixtures/wlnb/basic.wlnb'), tmp)
  local state = h.open_notebook_path(tmp)
  local cells_mod = require('ipynb.cells')
  local facade_win = vim.api.nvim_get_current_win()

  -- cursor on cell 2 (first input with output)
  local start_line = cells_mod.get_cell_range(state, 2)
  vim.api.nvim_win_set_cursor(0, { start_line + 2, 0 })
  panel.open(state)
  h.assert_true(state.output_panel ~= nil, 'panel should be open')
  h.assert_eq(vim.api.nvim_get_current_win(), facade_win, 'focus should stay in the notebook')
  local lines = vim.api.nvim_buf_get_lines(state.output_panel.buf, 0, -1, false)
  h.assert_eq(lines[1], 'x/2 - Sin[2 x]/4')

  -- move to cell 3 and let CursorMoved fire
  local start3 = cells_mod.get_cell_range(state, 3)
  vim.api.nvim_win_set_cursor(0, { start3 + 2, 0 })
  vim.api.nvim_exec_autocmds('CursorMoved', { buffer = state.facade_buf })
  lines = vim.api.nvim_buf_get_lines(state.output_panel.buf, 0, -1, false)
  h.assert_eq(lines[1], '{1, 4, 9, 16, 25}')

  -- real text: normal vim yank works
  vim.api.nvim_set_current_win(state.output_panel.win)
  vim.fn.setreg('"', '')
  vim.cmd('normal! yy')
  h.assert_eq(vim.fn.getreg('"'), '{1, 4, 9, 16, 25}\n')

  panel.close(state)
  h.assert_true(state.output_panel == nil, 'panel should be closed')
  vim.fn.delete(tmp)
end)

local success = h.summary()
if success then
  vim.cmd('qa!')
else
  vim.cmd('cquit 1')
end
