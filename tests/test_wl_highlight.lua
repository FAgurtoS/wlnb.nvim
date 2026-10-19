-- Light Wolfram highlighter (extmarks, no tree-sitter)
-- Run with: nvim --headless -u tests/minimal_init.lua -l tests/test_wl_highlight.lua

local h = require('tests.helpers')
local wl = require('ipynb.wl_highlight')

print('')
print(string.rep('=', 60))
print('Running light highlight tests')
print(string.rep('=', 60))
print('')

local function groups(lines)
  local out = {}
  for _, t in ipairs(wl.tokens(lines)) do
    out[#out + 1] = t[4] .. ':' .. lines[t[1]]:sub(t[2], t[3])
  end
  return table.concat(out, ' ')
end

h.run_test('tokens_cover_comments_strings_numbers_symbols_patterns', function()
  h.assert_eq(groups({ 'Plot[Sin[x], {x, 0, 2.5*^3}] (* note *)' }),
    'WlSystem:Plot WlSystem:Sin WlNumber:0 WlNumber:2.5*^3 WlComment:(* note *)')
  h.assert_eq(groups({ 'f[x_, y__Integer] := x /. y -> "a\\"b"' }),
    'WlPattern:x_ WlPattern:y__Integer WlOperator::= WlOperator:/. WlOperator:-> WlString:"a\\"b"')
  h.assert_eq(groups({ 'TrainDiffSystem[name, F[x]] + y' }), 'WlCall:TrainDiffSystem WlCall:F')
  h.assert_eq(groups({ '#1 + ## &' }), 'WlSlot:#1 WlOperator:+ WlSlot:## WlOperator:&')
end)

h.run_test('comments_and_strings_continue_over_lines_and_nest', function()
  h.assert_eq(groups({ 'a (* x', 'y (* z *) w', '*) b', '"s1', 's2" c' }),
    'WlComment:(* x WlComment:y (* z *) w WlComment:*) WlString:"s1 WlString:s2"')
end)

h.run_test('notebook_cells_are_painted_once_and_repainted_when_they_change', function()
  vim.g.wlnb_highlight = 'light'
  local tmp = vim.fn.tempname() .. '.wlnb'
  vim.fn.writefile({ '(* ::wlnb:: v1 *)', '', '(* ::cell:: input *)', 'Plot[x, {x, 0, 1}]', '', '(* ::cell:: input *)', 'Integrate[x^2, x]' }, tmp)
  local state = h.open_notebook_path(tmp)
  wl.apply(state)
  local ns = vim.api.nvim_create_namespace('wlnb_highlight')
  local function count()
    return #vim.api.nvim_buf_get_extmarks(state.facade_buf, ns, 0, -1, {})
  end
  local first = count()
  h.assert_true(first > 4, 'tokens painted: ' .. first)
  wl.apply(state)
  h.assert_eq(count(), first) -- nothing changes, nothing is repainted
  state.cells[2].source = 'Integrate[x^2, {x, 0, 1}] + Sin[x]'
  require('ipynb.facade').refresh(state)
  h.assert_true(count() > first, 'changed cell repainted')
  vim.fn.delete(tmp)
end)

local success = h.summary()
if success then
  vim.cmd('qa!')
else
  vim.cmd('cquit 1')
end
