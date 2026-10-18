-- ipynb/kernels.lua - List and stop running Wolfram kernels (the license caps concurrent kernels)

local M = {}

M._max = nil ---@type number|nil

---Where the license limit is cached between sessions (replaceable in tests)
function M.cache_path()
  return vim.fn.stdpath('state') .. '/wln_license.json'
end

---Maximum concurrent kernels allowed by the license ($MaxLicenseProcesses), if known
---@return number|nil
function M.get_max()
  if M._max then
    return M._max
  end
  local ok, lines = pcall(vim.fn.readfile, M.cache_path())
  if ok then
    local decoded_ok, data = pcall(vim.json.decode, table.concat(lines, '\n'))
    if decoded_ok and type(data) == 'table' and type(data.max) == 'number' then
      M._max = data.max
    end
  end
  return M._max
end

---Remember the limit reported by a running kernel
---@param max number
function M.set_max(max)
  if type(max) ~= 'number' then
    return
  end
  M._max = max
  pcall(vim.fn.mkdir, vim.fn.fnamemodify(M.cache_path(), ':h'), 'p')
  pcall(vim.fn.writefile, { vim.json.encode({ max = max }) }, M.cache_path())
end

---@class WolframKernelInfo
---@field pid number
---@field ppid number
---@field etime string
---@field owner string Human readable owner
---@field state NotebookState|nil Notebook (in this Neovim) that owns the kernel

local function short(cmd, n)
  cmd = cmd:gsub('%s+', ' ')
  if #cmd > n then
    return cmd:sub(1, n - 3) .. '...'
  end
  return cmd
end

---Running WolframKernel processes of this user, with their owner
---@return WolframKernelInfo[]
function M.list()
  local res = vim.system({ 'ps', '-axo', 'pid=,ppid=,etime=,command=' }, { text = true }):wait()
  local procs = {} ---@type table<number, {ppid:number, etime:string, cmd:string}>
  for line in (res.stdout or ''):gmatch('[^\n]+') do
    local pid, ppid, etime, cmd = line:match('^%s*(%d+)%s+(%d+)%s+(%S+)%s+(.*)$')
    if pid then
      procs[tonumber(pid)] = { ppid = tonumber(ppid), etime = etime, cmd = cmd }
    end
  end

  local bridge_owner = {} ---@type table<number, NotebookState>
  for _, state in pairs(require('ipynb.state').notebooks) do
    local job = state.kernel and state.kernel.job_id
    if job then
      local ok, pid = pcall(vim.fn.jobpid, job)
      if ok and pid then
        bridge_owner[pid] = state
      end
    end
  end

  local kernels = {}
  for pid, p in pairs(procs) do
    if p.cmd:find('WolframKernel', 1, true) and not p.cmd:find('wolframscript', 1, true) then
      local owner, state
      local parent = procs[p.ppid]
      if bridge_owner[p.ppid] then
        state = bridge_owner[p.ppid]
        owner = 'this Neovim: ' .. vim.fn.fnamemodify(state.source_path or '?', ':t')
      elseif p.ppid == 1 then
        owner = 'orphan (no parent process)'
      elseif parent and parent.cmd:find('wolfram_bridge.py', 1, true) then
        owner = 'another Neovim session'
      elseif parent then
        owner = 'external: ' .. short(parent.cmd, 40)
      else
        owner = 'external'
      end
      table.insert(kernels, { pid = pid, ppid = p.ppid, etime = p.etime, owner = owner, state = state })
    end
  end
  table.sort(kernels, function(a, b)
    return a.pid < b.pid
  end)
  return kernels
end

---Stop a kernel: through its notebook when it is ours, otherwise by signal
---@param info WolframKernelInfo
function M.kill(info)
  if info.state then
    require('ipynb.kernel').shutdown(info.state)
  end
  pcall(vim.uv.kill, info.pid, 'sigterm')
  vim.defer_fn(function()
    if pcall(vim.uv.kill, info.pid, 0) then
      pcall(vim.uv.kill, info.pid, 'sigkill')
    end
  end, 1500)
end

local function describe(info)
  return ('pid %d  %s  %s'):format(info.pid, info.etime, info.owner)
end

---Run `callback` once there is a free kernel slot, offering to stop a kernel if the license limit is reached
---@param callback fun()
function M.ensure_slot(callback)
  local max = M.get_max()
  local running = M.list()
  if not max or #running < max then
    return callback()
  end
  local items = {}
  for _, info in ipairs(running) do
    table.insert(items, info)
  end
  vim.ui.select(items, {
    prompt = ('Wolfram license limit reached (%d/%d kernels). Stop one to continue:'):format(#running, max),
    format_item = describe,
  }, function(choice)
    if not choice then
      vim.notify('Kernel start cancelled (license limit reached)', vim.log.levels.WARN)
      return
    end
    M.kill(choice)
    -- wait for the slot to be released (up to ~5 s)
    local tries = 0
    local function wait()
      tries = tries + 1
      if #M.list() < max or tries > 25 then
        callback()
      else
        vim.defer_fn(wait, 200)
      end
    end
    vim.defer_fn(wait, 200)
  end)
end

---Open a float listing the running kernels. x: stop, r: refresh, q: close
function M.show()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].filetype = 'notebook_kernels'

  local entries = {}
  local function render()
    entries = M.list()
    local max = M.get_max()
    local lines = {
      ('Wolfram kernels: %d / %s (license limit)'):format(#entries, max and tostring(max) or '?'),
      'x: stop kernel   r: refresh   q: close',
      '',
    }
    for _, info in ipairs(entries) do
      table.insert(lines, describe(info))
    end
    if #entries == 0 then
      table.insert(lines, '(no kernels running)')
    end
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false
  end
  render()

  local width = 90
  local height = math.max(6, #entries + 5)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    width = math.min(width, vim.o.columns - 4),
    height = height,
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    style = 'minimal',
    border = 'rounded',
    title = ' Wolfram kernels ',
  })

  local function close()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end
  local map = function(lhs, fn)
    vim.keymap.set('n', lhs, fn, { buffer = buf, nowait = true })
  end
  map('q', close)
  map('<Esc>', close)
  map('r', render)
  map('x', function()
    local info = entries[vim.api.nvim_win_get_cursor(win)[1] - 3]
    if not info then
      return
    end
    local external = info.state == nil
    local msg = ('Stop kernel %d (%s)?'):format(info.pid, info.owner)
    if external then
      msg = msg .. '\nIt is not owned by this Neovim: another application may be using it.'
    end
    if vim.fn.confirm(msg, '&Yes\n&No', 2) == 1 then
      M.kill(info)
      vim.defer_fn(function()
        if vim.api.nvim_buf_is_valid(buf) then
          render()
        end
      end, 1800)
    end
  end)
end

return M
