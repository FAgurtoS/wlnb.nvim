-- PDF/LaTeX export (kernel-free: TeX forms are injected)
-- Run with: nvim --headless -u tests/minimal_init.lua -l tests/test_export.lua

local h = require('tests.helpers')
local export = require('ipynb.export')

print('')
print(string.rep('=', 60))
print('Running export tests')
print(string.rep('=', 60))
print('')

local png = vim.base64.encode('\137PNG fake')
local function cell(source, outputs)
  return { type = 'code', source = source, outputs = outputs or {}, metadata = {} }
end
local function result(text, with_png)
  return { output_type = 'execute_result', data = { ['text/plain'] = text, ['image/png'] = with_png and png or nil }, metadata = {} }
end

h.run_test('tex_has_boxes_equations_images_and_truncation', function()
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, 'p')
  local long = {}
  for i = 1, 60 do
    long[i] = 'line ' .. i
  end
  local cells = {
    { type = 'markdown', source = '# Title\n\nA formula $x^2$.', metadata = {} },
    cell('Integrate[x^2, x]', { result('x^3/3', true) }),
    cell('Plot[x, {x, 0, 1}]', { result('-Graphics-', true) }),
    cell('Do[...]', { result(table.concat(long, '\n'), false) }),
  }
  local tex = export.to_tex(cells, { dir = dir, tex_forms = { [1] = '\\frac{x^3}{3}' }, max_output_lines = 40 })
  h.assert_true(tex:find('\\begin{codecell}', 1, true) ~= nil, 'code box')
  h.assert_true(tex:find('language=Mathematica', 1, true) ~= nil, 'syntax style')
  h.assert_true(tex:find('\\[ \\frac{x^3}{3} \\]', 1, true) ~= nil, 'equation instead of the dark PNG')
  h.assert_true(tex:find('img1.png', 1, true) ~= nil and vim.fn.filereadable(dir .. '/img1.png') == 1, 'plot image written')
  h.assert_true(tex:find('img2.png', 1, true) == nil, 'math result is not an image')
  h.assert_true(tex:find('20 more lines not shown', 1, true) ~= nil, 'long output truncated')
  h.assert_true(tex:find('\\section', 1, true) ~= nil or tex:find('Title', 1, true) ~= nil, 'markdown converted')
  vim.fn.delete(dir, 'rf')
end)

h.run_test('export_writes_tex_with_images_folder', function()
  local dest = vim.fn.tempname() .. '.tex'
  local out = export.export({ cell('Plot[x]', { result('-Graphics-', true) }) }, dest, 'demo')
  h.assert_eq(out, dest)
  local text = table.concat(vim.fn.readfile(dest), '\n')
  local folder = vim.fn.fnamemodify(dest:gsub('%.tex$', ''), ':t') .. '_files/img1.png'
  h.assert_true(text:find(folder, 1, true) ~= nil, 'image path points into the _files folder')
  vim.fn.delete(dest)
  vim.fn.delete(dest:gsub('%.tex$', '') .. '_files', 'rf')
end)

local success = h.summary()
if success then
  vim.cmd('qa!')
else
  vim.cmd('cquit 1')
end
