-- .nb <-> .wlnb conversion with a real kernel (skipped when no WolframKernel is installed)
-- Run with: nvim --headless -u tests/minimal_init.lua -l tests/test_nb.lua

local h = require('tests.helpers')

print('')
print(string.rep('=', 60))
print('Running .nb conversion tests')
print(string.rep('=', 60))
print('')

if not require('ipynb.util').find_wolfram_kernel() then
  print('SKIP: no WolframKernel')
  vim.cmd('qa!')
end

h.run_test('wlnb_to_nb_and_back_keeps_code_markdown_and_outputs', function()
  local function result(text)
    return { output_type = 'execute_result', data = { ['text/plain'] = text }, metadata = {} }
  end
  local cells = {
    { type = 'markdown', source = '# Title', metadata = {} },
    { type = 'markdown', source = 'Some text.', metadata = {} },
    { type = 'code', source = 'x = 5;\nx^2 + Sin[x]', metadata = {}, outputs = { result('25 + Sin[5]'), result('"text out"') } },
    { type = 'code', source = 'f[y_] := y^2', metadata = {}, outputs = {} },
  }
  local nb = vim.fn.tempname() .. '.nb'
  local ok, err = require('ipynb.nb').write(nb, cells)
  h.assert_true(ok, 'write .nb: ' .. tostring(err))
  h.assert_true(vim.fn.getfsize(nb) > 200, '.nb written')

  local back, err2 = require('ipynb.nb').read(nb)
  h.assert_true(back ~= nil, 'read .nb: ' .. tostring(err2))
  local kinds = {}
  for _, c in ipairs(back) do
    kinds[#kinds + 1] = c.type
  end
  h.assert_eq(table.concat(kinds, ','), 'markdown,markdown,code,code')
  h.assert_eq(back[1].source, '# Title') -- Title style maps back to a heading
  h.assert_eq(back[2].source, 'Some text.')
  h.assert_true(back[3].source:find('x = 5', 1, true) ~= nil and back[3].source:find('x^2', 1, true) ~= nil, 'code kept: ' .. back[3].source)
  h.assert_eq(#back[3].outputs, 2)
  h.assert_true(back[3].outputs[1].data['text/plain']:find('Sin[5]', 1, true) ~= nil, 'output kept')
  vim.fn.delete(nb)
end)

h.run_test('convert_entry_point_handles_nb_both_ways', function()
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, 'p')
  local src = dir .. '/a.wlnb'
  vim.fn.writefile({ '(* ::wlnb:: v1 *)', '', '(* ::cell:: input *)', 'Range[3]', '', '(* ::cell:: output *)', '(* {1, 2, 3} *)' }, src)
  local nb, err = require('ipynb.wln').convert(src, dir .. '/a.nb')
  h.assert_eq(nb, dir .. '/a.nb')
  local back, err2 = require('ipynb.wln').convert(dir .. '/a.nb', dir .. '/b.wlnb')
  h.assert_true(back ~= nil, tostring(err) .. tostring(err2))
  local text = table.concat(vim.fn.readfile(dir .. '/b.wlnb'), '\n')
  h.assert_true(text:find('Range[3]', 1, true) ~= nil and text:find('{1, 2, 3}', 1, true) ~= nil, 'round trip through .nb')
  vim.fn.delete(dir, 'rf')
end)

local success = h.summary()
if success then
  vim.cmd('qa!')
else
  vim.cmd('cquit 1')
end
