-- Agent API tests (scripts/wln-agent talks to this module through nvim --server)
-- Run with: nvim --headless -u tests/minimal_init.lua -l tests/test_agent.lua

local h = require('tests.helpers')
local agent = require('ipynb.agent')

print('')
print(string.rep('=', 60))
print('Running agent API tests')
print(string.rep('=', 60))
print('')

local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')

h.run_test('agent_list_get_set_insert_delete', function()
  local tmp = vim.fn.tempname() .. '.wlnb'
  vim.fn.writefile(vim.fn.readfile(root .. '/tests/fixtures/wlnb/basic.wlnb'), tmp)
  local state = h.open_notebook_path(tmp)
  local function call(fn, ...)
    return vim.json.decode(agent.call(vim.json.encode({ fn = fn, args = { tmp, ... } })))
  end

  local list = call('list')
  h.assert_true(list.ok, 'list ok')
  h.assert_eq(#list.cells, #state.cells)

  local got = call('get', 2)
  h.assert_eq(got.type, 'code')

  h.assert_true(call('set', 2, 'y = 7').ok, 'set')
  h.assert_eq(state.cells[2].source, 'y = 7')
  h.assert_eq(call('get', 2).source, 'y = 7')

  local n = #state.cells
  local ins = call('insert', 1, 'markdown', 'hello')
  h.assert_true(ins.ok and ins.index == 2, 'insert index')
  h.assert_eq(#state.cells, n + 1)
  h.assert_eq(state.cells[2].type, 'markdown')

  h.assert_true(call('delete', 2).ok, 'delete')
  h.assert_eq(#state.cells, n)

  local bad = call('get', 99)
  h.assert_true(not bad.ok and bad.error:find('no cell 99') ~= nil, 'out of range reported')
  local missing = vim.json.decode(agent.call(vim.json.encode({ fn = 'list', args = { '/nope.wlnb' } })))
  h.assert_true(not missing.ok, 'unknown notebook reported')

  h.assert_true(call('save').ok, 'save')
  h.assert_true(table.concat(vim.fn.readfile(tmp), '\n'):find('y = 7', 1, true) ~= nil, 'saved to disk')
  vim.fn.delete(tmp)
end)

local success = h.summary()
if success then
  vim.cmd('qa!')
else
  vim.cmd('cquit 1')
end
