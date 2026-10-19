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

h.run_test('graphics_are_saved_to_assets_and_reloaded_with_stale_detection', function()
  local png = vim.base64.encode('\137PNG fake image bytes')
  local function plot_cell(src)
    return {
      id = 'a', type = 'code', source = src, metadata = {},
      outputs = { { output_type = 'execute_result', data = { ['text/plain'] = '-Graphics-', ['image/png'] = png }, metadata = {} } },
    }
  end
  local tmp = vim.fn.tempname() .. '.wlnb'
  wlnb.write(tmp, { plot_cell('Plot[x, {x, 0, 1}]') })
  local lines = vim.fn.readfile(tmp)
  local hash = lines[#lines]:match('^%(%* %-Graphics%- (%x+) %*%)$')
  h.assert_true(hash ~= nil, 'marker has a hash')
  h.assert_eq(vim.fn.filereadable(tmp .. '.assets/' .. hash .. '.png'), 1)
  -- Reload: image restored, not stale, and a second save keeps the same marker
  local cells = wlnb.read(tmp)
  h.assert_eq(cells[1].outputs[1].data['image/png'], png)
  h.assert_eq(cells[1].outputs[1].data['text/plain'], '-Graphics-')
  wlnb.write(tmp, cells)
  h.assert_eq(table.concat(vim.fn.readfile(tmp), '\n'), table.concat(lines, '\n'))
  -- Edit the code: the image is stale and keeps pointing at its old PNG
  local edited = vim.fn.readfile(tmp)
  edited[4] = 'Plot[2 x, {x, 0, 1}]'
  vim.fn.writefile(edited, tmp)
  cells = wlnb.read(tmp)
  h.assert_eq(cells[1].outputs[1].data['text/plain'], '-Graphics- [stale]')
  wlnb.write(tmp, cells)
  h.assert_eq(vim.fn.readfile(tmp)[#lines], lines[#lines])
  -- The old PNG is still referenced; an unreferenced one is removed
  vim.fn.writefile({ 'x' }, tmp .. '.assets/deadbeef0000.png')
  h.assert_eq(wlnb.clean_assets(tmp), 1)
  h.assert_eq(vim.fn.filereadable(tmp .. '.assets/' .. hash .. '.png'), 1)
  vim.fn.delete(tmp)
  vim.fn.delete(tmp .. '.assets', 'rf')
end)

local success = h.summary()
if success then
  vim.cmd('qa!')
else
  vim.cmd('cquit 1')
end
