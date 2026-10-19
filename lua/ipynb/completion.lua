-- ipynb/completion.lua - symbol completion for Wolfram cells, as an in-process LSP server.
-- Names and usage messages come from data/wolfram_symbols.json (scripts/gen_symbols.wl), so no
-- kernel is needed while typing. Any completion plugin that reads LSP (blink.cmp, nvim-cmp) shows
-- it; without one, Neovim's built-in LSP completion is turned on for the cell.

local M = {}

local MAX_ITEMS = 200
local MIN_PREFIX = 2

local symbols ---@type { name: string, lower: string, usage: string }[]|nil

local function load_symbols()
  if symbols then
    return symbols
  end
  symbols = {}
  local path = require('ipynb.util').get_plugin_root() .. '/data/wolfram_symbols.json'
  local f = io.open(path, 'r')
  if not f then
    return symbols
  end
  local ok, data = pcall(vim.json.decode, f:read('*a'))
  f:close()
  if ok and type(data) == 'table' then
    for name, usage in pairs(data) do
      table.insert(symbols, { name = name, lower = name:lower(), usage = usage })
    end
    table.sort(symbols, function(a, b)
      return a.name < b.name
    end)
  end
  return symbols
end

---Word being typed before the cursor, e.g. "Integ" in "x = Integ|"
---@param line string
---@param col integer 0-based cursor column
---@return string prefix, integer start_col
local function prefix_at(line, col)
  local before = line:sub(1, col)
  local prefix = before:match('[%a%$][%w%$]*$') or ''
  return prefix, col - #prefix
end

---@param prefix string
---@return table[] items LSP CompletionItems
---@return boolean truncated More matches exist than were returned
function M.items(prefix)
  if #prefix < MIN_PREFIX then
    return {}, false
  end
  local lower = prefix:lower()
  local items = {}
  for _, sym in ipairs(load_symbols()) do
    if sym.lower:sub(1, #lower) == lower then
      table.insert(items, {
        label = sym.name,
        kind = 3, -- Function
        documentation = sym.usage ~= '' and { kind = 'plaintext', value = sym.usage } or nil,
        -- exact-case matches first, then shorter names
        sortText = (sym.name:sub(1, #prefix) == prefix and '0' or '1') .. string.format('%03d', #sym.name) .. sym.name,
      })
      if #items >= MAX_ITEMS then
        return items, true
      end
    end
  end
  return items, false
end

local function server(dispatchers)
  local closing = false
  local srv = {}
  function srv.request(method, params, callback)
    if method == 'initialize' then
      local letters = {}
      for c in ('abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ$'):gmatch('.') do
        table.insert(letters, c)
      end
      callback(nil, { capabilities = { completionProvider = { triggerCharacters = letters } } })
    elseif method == 'textDocument/completion' then
      -- Completion is always asked for the buffer being typed in; cell buffers have no real file URI
      local buf = vim.api.nvim_get_current_buf()
      if vim.bo[buf].filetype ~= 'wolfram' then
        buf = vim.uri_to_bufnr(params.textDocument.uri)
      end
      local line = vim.api.nvim_buf_get_lines(buf, params.position.line, params.position.line + 1, false)[1] or ''
      local prefix = prefix_at(line, params.position.character)
      local items, truncated = M.items(prefix)
      callback(nil, { isIncomplete = truncated, items = items }) -- truncated: the client asks again as you type
    else
      callback(nil, nil) -- shutdown and anything else
    end
    return true, 1
  end
  function srv.notify(method)
    if method == 'exit' then
      closing = true
      dispatchers.on_exit(0, 0)
    end
    return true
  end
  function srv.is_closing()
    return closing
  end
  function srv.terminate()
    closing = true
  end
  return srv
end

---Attach symbol completion to a Wolfram cell buffer
---@param buf integer
function M.attach(buf)
  if not (vim.lsp and vim.lsp.start) then
    return
  end
  local client_id = vim.lsp.start({
    name = 'wlnb-symbols',
    cmd = server,
    root_dir = require('ipynb.util').get_plugin_root(),
  }, { bufnr = buf, silent = true })
  if not client_id then
    return
  end
  -- With no completion plugin around, use Neovim's own popup
  local has_plugin = pcall(require, 'blink.cmp') or pcall(require, 'cmp')
  if not has_plugin and vim.lsp.completion and not vim.b[buf].wlnb_native_completion then
    vim.b[buf].wlnb_native_completion = true
    -- noinsert: show the best match without typing it into the cell; popup: show the usage text
    vim.api.nvim_buf_call(buf, function()
      vim.opt_local.completeopt = { 'menu', 'menuone', 'noinsert', 'popup' }
    end)
    vim.lsp.completion.enable(true, client_id, buf, { autotrigger = true })
  end
end

return M
