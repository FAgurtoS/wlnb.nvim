-- .wln <-> .wlnb conversion tests (text flavour; the legacy flavour needs a kernel and is not tested here)
-- Run with: nvim --headless -u tests/minimal_init.lua -l tests/test_wln.lua

local h = require('tests.helpers')
local wln = require('ipynb.wln')
local wlnb = require('ipynb.wlnb')

print('')
print(string.rep('=', 60))
print('Running .wln conversion tests')
print(string.rep('=', 60))
print('')

local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')
local sample = root .. '/tests/fixtures/wln/sample.wln'

h.run_test('wln_text_outputs_kept_rendered_ones_dropped', function()
  local cells = wln.read(sample)
  h.assert_eq(#cells, 3)
  h.assert_eq(cells[1].type, 'markdown')
  h.assert_eq(cells[1].source, '# Title')
  h.assert_eq(cells[2].type, 'code')
  h.assert_eq(#cells[2].outputs, 2) -- joined Print lines + the expression; the html output is dropped
  h.assert_eq(cells[2].outputs[1].data['text/plain'], 'a\nb')
  h.assert_eq(cells[2].outputs[2].data['text/plain'], 'Power[x,2]/(1+x)')
  h.assert_eq(cells[3].type, 'raw')
  h.assert_eq(cells[3].source, '.html\n<b>raw</b>')
end)

h.run_test('wln_to_wlnb_to_wln_to_wlnb_is_stable', function()
  local a = vim.fn.tempname() .. '.wlnb'
  local b = vim.fn.tempname() .. '.wln'
  local c = vim.fn.tempname() .. '.wlnb'
  h.assert_true(wln.convert(sample, a) ~= nil, 'wln -> wlnb')
  h.assert_true(wln.convert(a, b) ~= nil, 'wlnb -> wln')
  h.assert_true(wln.convert(b, c) ~= nil, 'wln -> wlnb again')
  local first = table.concat(vim.fn.readfile(a), '\n')
  -- outputs are not written back to .wln, so compare the inputs only
  local function inputs(path)
    local out = {}
    for _, cell in ipairs(wlnb.read(path)) do
      table.insert(out, cell.type .. ':' .. cell.source)
    end
    return table.concat(out, '\n--\n')
  end
  h.assert_eq(inputs(a), inputs(c))
  h.assert_true(first:find('::cell:: output', 1, true) ~= nil, 'outputs reach the .wlnb')
  for _, f in ipairs({ a, b, c }) do
    vim.fn.delete(f)
  end
end)

local success = h.summary()
if success then
  vim.cmd('qa!')
else
  vim.cmd('cquit 1')
end
