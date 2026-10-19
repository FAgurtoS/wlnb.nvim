-- ipynb/agent.lua - control an open notebook from outside Neovim (scripts/wlnb-agent, nvim --server).
-- Every function takes the notebook path and returns a JSON string, so it can be called with
-- --remote-expr. Cell indexes are 1-based. Execution is asynchronous: run() returns at once,
-- poll with get() until "state" is "idle".

local M = {}

local function find(path)
  local state_mod = require('ipynb.state')
  local state = state_mod.get_by_path(path) or state_mod.get_by_path(vim.fn.fnamemodify(path, ':p'))
  if not state then
    for _, s in pairs(state_mod.notebooks) do
      if s.source_path and vim.fn.fnamemodify(s.source_path, ':p') == vim.fn.fnamemodify(path, ':p') then
        state = s
      end
    end
  end
  return state
end

local function reply(value)
  return vim.json.encode(value)
end

local function fail(msg)
  return reply({ ok = false, error = msg })
end

---Run fn(state) on the notebook, refusing while a cell is open in edit mode
local function with_notebook(path, fn, allow_editing)
  local state = find(path)
  if not state then
    return fail('notebook not open in this Neovim: ' .. tostring(path))
  end
  if state.edit_state and not allow_editing then
    return fail('a cell is being edited in Neovim; leave edit mode (Esc) first')
  end
  local ok, res = pcall(fn, state)
  if not ok then
    return fail((tostring(res):gsub('^.-agent%.lua:%d+: ', '')))
  end
  return reply(res)
end

local function output_texts(cell)
  local texts = {}
  for _, out in ipairs(cell.outputs or {}) do
    local data = out.data or {}
    local text = out.text or data['text/plain']
    if out.output_type == 'error' then
      text = (out.ename or '') .. ': ' .. (out.evalue or '')
    end
    if type(text) == 'table' then
      text = table.concat(text, '')
    end
    if text then
      table.insert(texts, text)
    end
  end
  return texts
end

local function cell_at(state, i)
  local cell = state.cells[i]
  if not cell then
    error('no cell ' .. tostring(i) .. ' (notebook has ' .. #state.cells .. ')')
  end
  return cell
end

function M.list(path)
  return with_notebook(path, function(state)
    local cells = {}
    for i, cell in ipairs(state.cells) do
      table.insert(cells, {
        index = i, type = cell.type, state = cell.execution_state or 'idle',
        first_line = vim.split(cell.source, '\n', { plain = true })[1], outputs = #(cell.outputs or {}),
      })
    end
    local kernel = state.kernel
    return { ok = true, kernel_connected = kernel and kernel.connected or false, cells = cells }
  end, true)
end

function M.get(path, i)
  return with_notebook(path, function(state)
    local cell = cell_at(state, i)
    return { ok = true, index = i, type = cell.type, source = cell.source,
      state = cell.execution_state or 'idle', outputs = output_texts(cell) }
  end, true)
end

function M.set(path, i, text)
  return with_notebook(path, function(state)
    cell_at(state, i).source = text
    require('ipynb.facade').refresh(state)
    return { ok = true }
  end)
end

---Insert a cell after cell `after` (0 = at the top)
function M.insert(path, after, cell_type, text)
  return with_notebook(path, function(state)
    local idx = require('ipynb.facade').insert_cell(state, after, cell_type)
    state.cells[idx].source = text
    require('ipynb.facade').refresh(state)
    return { ok = true, index = idx }
  end)
end

function M.delete(path, i)
  return with_notebook(path, function(state)
    cell_at(state, i)
    require('ipynb.facade').delete_cell(state, i)
    return { ok = true }
  end)
end

---Start the kernel if needed and execute a code cell. Returns at once: poll get() until idle.
function M.run(path, i)
  return with_notebook(path, function(state)
    local cell = cell_at(state, i)
    if cell.type ~= 'code' then
      error('cell ' .. i .. ' is a ' .. cell.type .. ' cell')
    end
    local kernel = require('ipynb.kernel')
    if state.kernel and state.kernel.connected then
      kernel.execute(state, i)
      return { ok = true }
    end
    -- Starting a kernel at the license limit would open a prompt nobody can answer
    local kernels = require('ipynb.kernels')
    local count, max = kernels.count(), kernels.get_max()
    if count and max and count >= max then
      error(('license limit reached (%d/%d kernels): stop one with :NotebookKernels or in WLJS'):format(count, max))
    end
    kernel.connect(state, {})
    cell.execution_state = 'busy' -- shown as busy while the kernel starts
    local tries = 0
    local timer = vim.uv.new_timer()
    timer:start(200, 200, vim.schedule_wrap(function()
      tries = tries + 1
      if state.kernel and state.kernel.connected then
        timer:stop()
        timer:close()
        kernel.execute(state, i)
      elseif tries > 300 then -- 60 s
        timer:stop()
        timer:close()
        cell.execution_state = nil
        cell.outputs = { { output_type = 'error', ename = 'Kernel', evalue = 'kernel did not start' } }
      end
    end))
    return { ok = true, starting = true }
  end)
end

function M.save(path)
  return with_notebook(path, function(state)
    vim.api.nvim_buf_call(state.facade_buf, function()
      vim.cmd('silent write')
    end)
    return { ok = true }
  end, true)
end

---Dispatch from a JSON request {"fn": "get", "args": [path, 1]} (used by scripts/wlnb-agent)
function M.call(request)
  local req = vim.json.decode(request)
  local fn = ({ list = 1, get = 1, set = 1, insert = 1, delete = 1, run = 1, save = 1 })[req.fn] and M[req.fn]
  if not fn then
    return fail('unknown function ' .. tostring(req.fn))
  end
  return fn(unpack(req.args or {}))
end

return M
