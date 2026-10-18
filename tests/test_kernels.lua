-- Kernel list / stop / license-limit prompt, using fake "WolframKernel" processes (no license used)
-- Run with: nvim --headless -u tests/minimal_init.lua -l tests/test_kernels.lua

local h = require('tests.helpers')

print('')
print(string.rep('=', 60))
print('Running kernel manager tests')
print(string.rep('=', 60))
print('')

local kernels = require('ipynb.kernels')
local tmp_cache = vim.fn.tempname() .. '.json'
kernels.cache_path = function() return tmp_cache end -- never touch the real cache

local dir = vim.fn.tempname()
vim.fn.mkdir(dir, 'p')
local fake = dir .. '/WolframKernel'
vim.fn.writefile({ '#!/bin/sh', 'while true; do sleep 1; done' }, fake)
vim.fn.system({ 'chmod', '+x', fake })

local function spawn()
  return vim.fn.jobstart({ fake }, { detach = false })
end

local function pids()
  local out = {}
  for _, k in ipairs(kernels.list()) do
    out[k.pid] = k
  end
  return out
end

local function wait_for(cond)
  return vim.wait(8000, cond, 100)
end

h.run_test('list_finds_and_kill_stops_a_kernel', function()
  local job = spawn()
  local pid = vim.fn.jobpid(job)
  h.assert_true(wait_for(function() return pids()[pid] ~= nil end), 'fake kernel not listed')
  h.assert_true(pids()[pid].owner:find('external') ~= nil, 'owner: ' .. pids()[pid].owner)
  kernels.kill(pids()[pid])
  h.assert_true(wait_for(function() return pids()[pid] == nil end), 'kernel still listed after kill')
end)

h.run_test('license_max_is_remembered', function()
  kernels.set_max(2)
  kernels._max = nil
  h.assert_eq(kernels.get_max(), 2)
end)

h.run_test('limit_reached_prompts_and_frees_a_slot_before_continuing', function()
  kernels.set_max(1)
  local job = spawn()
  local pid = vim.fn.jobpid(job)
  h.assert_true(wait_for(function() return pids()[pid] ~= nil end), 'fake kernel not listed')

  local prompted, continued = false, false
  local orig = vim.ui.select
  vim.ui.select = function(items, opts, on_choice)
    prompted = true
    h.assert_true(opts.prompt:find('limit') ~= nil, opts.prompt)
    on_choice(items[1])
  end
  kernels.ensure_slot(function() continued = true end)
  vim.wait(8000, function() return continued end, 100)
  vim.ui.select = orig
  h.assert_true(prompted, 'should prompt at the limit')
  h.assert_true(continued, 'should continue after freeing a slot')
  h.assert_true(pids()[pid] == nil, 'chosen kernel should be stopped')
end)

h.run_test('below_limit_continues_without_prompt', function()
  kernels.set_max(5)
  local called = false
  kernels.ensure_slot(function() called = true end)
  h.assert_true(called, 'should continue immediately')
end)

vim.fn.delete(dir, 'rf')
local success = h.summary()
if success then
  vim.cmd('qa!')
else
  vim.cmd('cquit 1')
end
