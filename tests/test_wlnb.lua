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

h.run_test('graphics_embedded_mode_reloads_with_stale_detection', function()
  local png = vim.base64.encode('\137PNG fake image bytes')
  local function plot_cell(src)
    return {
      id = 'a', type = 'code', source = src, metadata = {},
      outputs = { { output_type = 'execute_result', data = { ['text/plain'] = '-Graphics-', ['image/png'] = png }, metadata = {} } },
    }
  end
  local tmp = vim.fn.tempname() .. '.wlnb'
  wlnb.write(tmp, { plot_cell('Plot[x, {x, 0, 1}]') }, 'embedded')
  local lines = vim.fn.readfile(tmp)
  local text = table.concat(lines, '\n')
  local hash = text:match('%(%* %-Graphics%- (%x+) %*%)')
  h.assert_true(hash ~= nil, 'marker has a hash')
  h.assert_true(text:find('(* ::assets:: *)', 1, true) ~= nil, 'assets section present')
  h.assert_true(text:find('(* ::asset:: ' .. hash .. ' png *)', 1, true) ~= nil, 'image embedded')
  h.assert_eq(vim.fn.isdirectory(tmp .. '.assets'), 0) -- no folder next to the file
  -- Reload: image restored, not stale, and a second save is byte-identical
  local cells = wlnb.read(tmp)
  h.assert_eq(cells[1].outputs[1].data['image/png'], png)
  h.assert_eq(cells[1].outputs[1].data['text/plain'], '-Graphics-')
  h.assert_eq(#cells, 1) -- the assets section is not a cell
  wlnb.write(tmp, cells, 'embedded')
  h.assert_eq(table.concat(vim.fn.readfile(tmp), '\n'), text)
  -- Edit the code: the image is stale and keeps its original hash
  local edited = vim.fn.readfile(tmp)
  edited[4] = 'Plot[2 x, {x, 0, 1}]'
  vim.fn.writefile(edited, tmp)
  cells = wlnb.read(tmp)
  h.assert_eq(cells[1].outputs[1].data['text/plain'], '-Graphics- [stale]')
  wlnb.write(tmp, cells, 'embedded')
  h.assert_true(table.concat(vim.fn.readfile(tmp), '\n'):find('-Graphics- ' .. hash, 1, true) ~= nil, 'hash kept')
  vim.fn.delete(tmp)
end)

h.run_test('sidecar_mode_keeps_notebook_readable_and_images_in_wlnbi', function()
  local png = vim.base64.encode('\137PNG fake image bytes')
  local cell = {
    id = 'a', type = 'code', source = 'Plot[x]', metadata = {},
    outputs = { { output_type = 'execute_result', data = { ['text/plain'] = '-Graphics-', ['image/png'] = png }, metadata = {} } },
  }
  local tmp = vim.fn.tempname() .. '.wlnb'
  local side = wlnb.sidecar_path(tmp)
  wlnb.write(tmp, { cell }) -- default mode: sidecar
  local text = table.concat(vim.fn.readfile(tmp), '\n')
  h.assert_true(text:find('::assets::', 1, true) == nil and #text < 200, 'notebook has no image data')
  h.assert_eq(vim.fn.filereadable(side), 1)
  h.assert_eq(vim.fn.readfile(side)[1], '(* ::wlnbi:: v1 *)')
  local cells = wlnb.read(tmp)
  h.assert_eq(cells[1].outputs[1].data['image/png'], png)
  -- Saving again is stable
  wlnb.write(tmp, cells)
  h.assert_eq(table.concat(vim.fn.readfile(tmp), '\n'), text)
  -- Without the images file the plot is reported missing but the notebook still opens
  local copy = vim.fn.tempname() .. '.wlnb'
  vim.fn.writefile(vim.fn.readfile(tmp), copy)
  local lonely = wlnb.read(copy)
  h.assert_true(lonely[1].outputs[1].data['text/plain']:find('missing image', 1, true) ~= nil, 'missing image reported')
  -- No images left: the stale images file goes away
  cells[1].outputs = {}
  wlnb.write(tmp, cells)
  h.assert_eq(vim.fn.filereadable(side), 0)
  vim.fn.delete(tmp)
  vim.fn.delete(copy)
end)

h.run_test('old_files_with_an_assets_folder_are_migrated_on_save', function()
  local tmp = vim.fn.tempname() .. '.wlnb'
  vim.fn.mkdir(tmp .. '.assets', 'p')
  local f = io.open(tmp .. '.assets/abcdef012345.png', 'wb')
  f:write('\137PNG old')
  f:close()
  vim.fn.writefile({ '(* ::wlnb:: v0 *)', '', '(* ::cell:: input *)', 'Plot[x]', '', '(* ::cell:: output *)', '(* -Graphics- abcdef012345 *)' }, tmp)
  local cells = wlnb.read(tmp)
  h.assert_eq(cells[1].outputs[1].data['image/png'], vim.base64.encode('\137PNG old'))
  wlnb.write(tmp, cells)
  h.assert_eq(vim.fn.isdirectory(tmp .. '.assets'), 0)
  h.assert_eq(wlnb.read(tmp)[1].outputs[1].data['image/png'], vim.base64.encode('\137PNG old'))
  vim.fn.delete(tmp)
end)

h.run_test('info_boxes_are_saved_as_images_like_other_results', function()
  local box = vim.base64.encode('info panel image')
  local cell = { id = 'a', type = 'code', source = '?Series', metadata = {},
    outputs = { { output_type = 'execute_result', data = { ['text/plain'] = 'InformationData[<|"x" -> 1|>]', ['image/png'] = box }, metadata = {} } } }
  local tmp = vim.fn.tempname() .. '.wlnb'
  wlnb.write(tmp, { cell })
  local text = table.concat(vim.fn.readfile(tmp), '\n')
  h.assert_true(text:find('-Rendered- ', 1, true) ~= nil, 'info box has an image marker')
  h.assert_eq(wlnb.read(tmp)[1].outputs[1].data['image/png'], box)
  vim.fn.delete(tmp)
  vim.fn.delete(wlnb.sidecar_path(tmp))
end)

h.run_test('rendered_math_keeps_inputform_text_and_png', function()
  local png = vim.base64.encode('\137PNG math image')
  local cell = { id = 'a', type = 'code', source = 'Sqrt[a^2]/2', metadata = {},
    outputs = { { output_type = 'execute_result', data = { ['text/plain'] = 'Sqrt[a^2]/2', ['image/png'] = png }, metadata = {} } } }
  local tmp = vim.fn.tempname() .. '.wlnb'
  wlnb.write(tmp, { cell }, 'embedded')
  local first = table.concat(vim.fn.readfile(tmp), '\n')
  h.assert_true(first:match('%(%* Sqrt%[a%^2%]/2\n%-Rendered%- %x+ %*%)') ~= nil, 'marker follows the text')
  local cells = wlnb.read(tmp)
  h.assert_eq(cells[1].outputs[1].data['text/plain'], 'Sqrt[a^2]/2')
  h.assert_eq(cells[1].outputs[1].data['image/png'], png)
  wlnb.write(tmp, cells, 'embedded')
  h.assert_eq(table.concat(vim.fn.readfile(tmp), '\n'), first)
  vim.fn.delete(tmp)
end)

local success = h.summary()
if success then
  vim.cmd('qa!')
else
  vim.cmd('cquit 1')
end
