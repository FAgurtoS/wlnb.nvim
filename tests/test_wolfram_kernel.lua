-- End-to-end: run cells of a .wlnb through the Wolfram bridge
-- Run with: nvim --headless -u tests/minimal_init.lua -l tests/test_wolfram_kernel.lua

local h = require('tests.helpers')

print('')
print(string.rep('=', 60))
print('Running Wolfram kernel tests')
print(string.rep('=', 60))
print('')

if vim.fn.executable('wolframscript') ~= 1 and vim.fn.executable('/usr/local/bin/wolframscript') ~= 1
  and vim.env.WLN_KERNEL == nil then
  print('SKIP: wolframscript not installed')
  vim.cmd('qa!')
end

local kernel = require('ipynb.kernel')
local kernels = require('ipynb.kernels')
local tmp_cache = vim.fn.tempname() .. '.json'
kernels.cache_path = function() return tmp_cache end -- never touch the real cache
local tmp = vim.fn.tempname() .. '.wlnb'
vim.fn.writefile({
  '(* ::wlnb:: v0 *)',
  '',
  '(* ::cell:: input *)',
  'x = 5; Print["hi"]; x^2',
  '',
  '(* ::cell:: input *)',
  '1/0',
  '',
  '(* ::cell:: input *)',
  'x + 1',
}, tmp)
-- One sequential test: run_test closes all notebooks between tests, and the kernel is slow to start.
local function output_text(cell)
  local parts = {}
  for _, out in ipairs(cell.outputs or {}) do
    if out.output_type == 'stream' then
      table.insert(parts, out.text)
    elseif out.data then
      table.insert(parts, out.data['text/plain'])
    end
  end
  return table.concat(parts, '')
end

h.run_test('wolfram_kernel_end_to_end', function()
  local state = h.open_notebook_path(tmp)

  local function run(idx)
    kernel.execute(state, idx)
    local ok = vim.wait(30000, function()
      return state.cells[idx].execution_state ~= 'busy' and #(state.cells[idx].outputs or {}) > 0
    end, 100)
    h.assert_true(ok, 'cell ' .. idx .. ' produced no output')
    vim.wait(300)
    return output_text(state.cells[idx])
  end

  kernel.connect(state, {})
  h.assert_true(vim.wait(60000, function()
    return state.kernel and state.kernel.connected
  end, 200), 'Wolfram kernel did not connect')

  -- the bridge reports the license limit and the kernel shows up in the manager as ours
  h.assert_true(vim.wait(5000, function() return kernels.get_max() ~= nil end, 100), 'license limit not reported')
  h.assert_true(type(kernels.get_max()) == 'number', 'max should be a number')
  local mine = false
  for _, k in ipairs(kernels.list()) do
    if k.state == state then
      mine = true
    end
  end
  h.assert_true(mine, 'kernel not listed as owned by this notebook')

  local t1 = run(1)
  h.assert_true(t1:find('hi') ~= nil and t1:find('25') ~= nil, 'cell 1 output: ' .. t1)

  local t2 = run(2)
  h.assert_true(t2:find('ComplexInfinity') ~= nil, 'cell 2 output: ' .. t2)

  local t3 = run(3)
  h.assert_true(t3:find('6') ~= nil, 'x should persist between cells: ' .. t3)

  kernel.restart(state, false)
  vim.wait(500)
  h.assert_true(vim.wait(60000, function()
    return state.kernel.connected
  end, 200), 'kernel did not come back after restart')
  local t4 = run(3)
  h.assert_true(t4:find('1 + x', 1, true) ~= nil, 'x should be undefined after restart: ' .. t4)

  -- closing the notebook must stop its kernel (it would hold a license slot otherwise)
  local pid
  for _, k in ipairs(kernels.list()) do
    if k.state == state then
      pid = k.pid
    end
  end
  h.assert_true(pid ~= nil, 'kernel pid not found before closing')
  vim.api.nvim_buf_delete(state.facade_buf, { force = true })
  h.assert_true(vim.wait(10000, function()
    return vim.uv.kill(pid, 0) ~= 0
  end, 100), 'kernel still running after the notebook was closed')
end)

local success = h.summary()
if success then
  vim.cmd('qa!')
else
  vim.cmd('cquit 1')
end
