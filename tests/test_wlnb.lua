-- .wlnb format tests (fixtures in tests/fixtures/wlnb, kept apart from the editable examples/): byte-identical round trip, escaping, open/save in the plugin
-- Run with: nvim --headless -u tests/minimal_init.lua -l tests/test_wlnb.lua

local h = require('tests.helpers')
local wlnb = require('ipynb.wlnb')

print('')
print(string.rep('=', 60))
print('Running .wlnb format tests')
print(string.rep('=', 60))
print('')

local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')

local function read_bytes(path)
  local f = assert(io.open(path, 'rb'))
  local s = f:read('*a')
  f:close()
  return s
end

for _, name in ipairs({ 'basic', 'plot', 'error', 'raw' }) do
  h.run_test('examples_roundtrip_byte_identical_' .. name, function()
    local src = root .. '/tests/fixtures/wlnb/' .. name .. '.wlnb'
    local cells = wlnb.read(src)
    local tmp = vim.fn.tempname() .. '.wlnb'
    wlnb.write(tmp, cells)
    local same = read_bytes(src) == read_bytes(tmp)
    vim.fn.delete(tmp)
    h.assert_true(same, name .. '.wlnb changed after read+write')
  end)
end

h.run_test('parse_maps_cell_types_and_outputs', function()
  local cells = wlnb.read(root .. '/tests/fixtures/wlnb/basic.wlnb')
  h.assert_eq(#cells, 3, 'markdown + 2 inputs')
  h.assert_eq(cells[1].type, 'markdown')
  h.assert_eq(cells[1].source, '# Integrals')
  h.assert_eq(cells[2].type, 'code')
  h.assert_eq(cells[2].source, 'Integrate[Sin[x]^2, x]')
  h.assert_eq(cells[2].outputs[1].data['text/plain'], 'x/2 - Sin[2 x]/4')
end)

h.run_test('comment_delimiters_are_escaped', function()
  local cells = {
    { type = 'markdown', source = 'a (* b *) c\nsecond', metadata = {} },
    { type = 'code', source = 'x', metadata = {}, outputs = {} },
  }
  local back = wlnb.parse(wlnb.serialize(cells))
  h.assert_eq(back[1].source, 'a (* b *) c\nsecond')
end)

h.run_test('empty_and_multiline_inputs_roundtrip', function()
  local cells = {
    { type = 'code', source = '', metadata = {}, outputs = {} },
    { type = 'code', source = 'f[x_] :=\n  x^2\n', metadata = {}, outputs = {} },
  }
  local back = wlnb.parse(wlnb.serialize(cells))
  h.assert_eq(#back, 2)
  h.assert_eq(back[1].source, '')
  h.assert_eq(back[2].source, 'f[x_] :=\n  x^2\n')
end)

h.run_test('open_and_save_in_plugin_keeps_file_identical', function()
  local tmp = vim.fn.tempname() .. '.wlnb'
  vim.fn.writefile(vim.fn.readfile(root .. '/tests/fixtures/wlnb/basic.wlnb'), tmp)
  local before = read_bytes(tmp)
  h.open_notebook_path(tmp)
  vim.cmd('write')
  vim.wait(100)
  local after = read_bytes(tmp)
  vim.fn.delete(tmp)
  h.assert_true(before == after, 'file changed after open+save in the plugin')
end)

h.run_test('yank_output_copies_cell_output_to_register', function()
  local tmp = vim.fn.tempname() .. '.wlnb'
  vim.fn.writefile(vim.fn.readfile(root .. '/tests/fixtures/wlnb/basic.wlnb'), tmp)
  local state = h.open_notebook_path(tmp)
  vim.fn.setreg('"', '')
  require('ipynb.output').yank_output(state, 2)
  vim.fn.delete(tmp)
  h.assert_eq(vim.fn.getreg('"'), 'x/2 - Sin[2 x]/4')
end)

local success = h.summary()
if success then
  vim.cmd('qa!')
else
  vim.cmd('cquit 1')
end
