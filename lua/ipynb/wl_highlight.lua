-- ipynb/wl_highlight.lua - ultra-light Wolfram syntax colors.
-- A small tokenizer paints extmarks once when a cell changes, instead of tree-sitter re-running its
-- queries on every redraw. Set vim.g.wlnb_highlight = 'treesitter' to use the tree-sitter colors.

local M = {}

local ns = vim.api.nvim_create_namespace('wlnb_highlight')

local LINKS = {
  WlComment = 'Comment', WlString = 'String', WlNumber = 'Number', WlSystem = 'Function',
  WlPattern = 'Special', WlOperator = 'Operator', WlSlot = 'Special',
}
for group, target in pairs(LINKS) do
  vim.api.nvim_set_hl(0, group, { link = target, default = true })
end

---@return boolean
function M.enabled()
  return (vim.g.wlnb_highlight or 'light') ~= 'treesitter'
end

local system_set ---@type table<string, boolean>|nil
local function is_system(name)
  if not system_set then
    system_set = {}
    for _, sym in ipairs(require('ipynb.completion').symbols()) do
      system_set[sym.name] = true
    end
  end
  return system_set[name]
end

local OPS3 = { ['===']=1, ['=!=']=1, ['>>>']=1, ['...']=1, ['@@@']=1 }
local OPS2 = {
  ['->']=1, [':>']=1, ['/.']=1, ['//']=1, ['@@']=1, ['/@']=1, [':=']=1, ['&&']=1, ['||']=1, ['==']=1,
  ['!=']=1, ['<=']=1, ['>=']=1, [';;']=1, ['<>']=1, ['~~']=1, ['/;']=1, ['^=']=1, ['+=']=1, ['-=']=1,
}
local OPS1 = '+-*/^=&|;@<>!?'

---Tokens of Wolfram code: { line (1-based), col_start (1-based), col_end (inclusive), group }
---@param lines string[]
---@return table[]
function M.tokens(lines)
  local toks = {}
  local function add(li, s, e, group)
    if e >= s then
      toks[#toks + 1] = { li, s, e, group }
    end
  end
  local depth, in_str = 0, false
  for li, line in ipairs(lines) do
    local i, n = 1, #line
    local open_from = (depth > 0 or in_str) and 1 or nil -- start of a comment/string continuing from before
    while i <= n do
      if depth > 0 then
        local a, b = line:find('(*', i, true), line:find('*)', i, true)
        if b and (not a or b < a) then
          depth = depth - 1
          i = b + 2
          if depth == 0 then
            add(li, open_from or 1, i - 1, 'WlComment')
            open_from = nil
          end
        elseif a then
          depth = depth + 1
          i = a + 2
        else
          i = n + 1
        end
      elseif in_str then
        local j = i
        while j <= n do
          local c = line:sub(j, j)
          if c == '\\' then
            j = j + 2
          elseif c == '"' then
            break
          else
            j = j + 1
          end
        end
        if j <= n then
          in_str = false
          add(li, open_from or 1, j, 'WlString')
          open_from = nil
          i = j + 1
        else
          i = n + 1
        end
      else
        local c = line:sub(i, i)
        if c == '(' and line:sub(i + 1, i + 1) == '*' then
          depth, open_from, i = 1, i, i + 2
        elseif c == '"' then
          in_str, open_from, i = true, i, i + 1
        elseif c:match('[%a$]') then
          local _, e = line:find('^[%a$][%w$]*', i)
          local name = line:sub(i, e)
          local _, e2 = line:find('^_+[%a$]?[%w$]*', e + 1)
          if e2 then
            add(li, i, e2, 'WlPattern')
            e = e2
          elseif is_system(name) then
            add(li, i, e, 'WlSystem')
          end
          i = e + 1
        elseif c == '_' then
          local _, e = line:find('^_+[%a$]?[%w$]*', i)
          add(li, i, e, 'WlPattern')
          i = e + 1
        elseif c:match('%d') or (c == '.' and line:sub(i + 1, i + 1):match('%d')) then
          local _, e = line:find('^%d*%.?%d*', i)
          local _, e2 = line:find('^%*%^%-?%d+', e + 1)
          add(li, i, e2 or e, 'WlNumber')
          i = (e2 or e) + 1
        elseif c == '#' then
          local _, e = line:find('^##?%d*', i)
          add(li, i, e, 'WlSlot')
          i = e + 1
        else
          local three, two = line:sub(i, i + 2), line:sub(i, i + 1)
          if OPS3[three] then
            add(li, i, i + 2, 'WlOperator')
            i = i + 3
          elseif OPS2[two] then
            add(li, i, i + 1, 'WlOperator')
            i = i + 2
          else
            if OPS1:find(c, 1, true) then
              add(li, i, i, 'WlOperator')
            end
            i = i + 1
          end
        end
      end
    end
    if open_from and (depth > 0 or in_str) then
      add(li, open_from, n, depth > 0 and 'WlComment' or 'WlString')
    end
  end
  return toks
end

---Paint `lines` into rows starting at `row0` (0-based) of `buf`
---@param buf integer
---@param row0 integer
---@param lines string[]
function M.paint(buf, row0, lines)
  for _, t in ipairs(M.tokens(lines)) do
    pcall(vim.api.nvim_buf_set_extmark, buf, ns, row0 + t[1] - 1, t[2] - 1, {
      end_col = t[3], hl_group = t[4], priority = 90, strict = false,
    })
  end
end

---Colors for the code cells of the notebook buffer; only cells that changed or moved are repainted.
---@param state NotebookState
function M.apply(state)
  local buf = state.facade_buf
  if not M.enabled() or not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  local lang = vim.b[buf].ipynb_language
  if lang and lang ~= 'wolfram' then
    return
  end
  local cells_mod = require('ipynb.cells')
  state._wl_hl = state._wl_hl or {}
  for idx, cell in ipairs(state.cells) do
    if cell.type == 'code' then
      local start_row = cells_mod.get_content_range(state, idx)
      local sig = state._wl_hl[cell.id or idx]
      local lines = vim.split(cell.source, '\n', { plain = true })
      local intact = sig and sig.src == cell.source and sig.row == start_row
        and (sig.count == 0 or #vim.api.nvim_buf_get_extmarks(buf, ns, { start_row, 0 }, { start_row + #lines - 1, -1 }, { limit = 1 }) > 0)
      if start_row and not intact then
        if sig and sig.row then
          vim.api.nvim_buf_clear_namespace(buf, ns, sig.row, sig.row + sig.nlines)
        end
        vim.api.nvim_buf_clear_namespace(buf, ns, start_row, start_row + #lines)
        M.paint(buf, start_row, lines)
        local count = #vim.api.nvim_buf_get_extmarks(buf, ns, { start_row, 0 }, { start_row + #lines - 1, -1 }, { limit = 1 })
        state._wl_hl[cell.id or idx] = { src = cell.source, row = start_row, nlines = #lines, count = count }
      end
    end
  end
end

---Colors for a cell edit buffer, repainted a moment after each change
---@param buf integer
function M.attach_edit(buf)
  if not M.enabled() or vim.b[buf].wlnb_light_hl then
    return
  end
  vim.b[buf].wlnb_light_hl = true
  local timer
  local function repaint()
    if vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
      M.paint(buf, 0, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
    end
  end
  repaint()
  vim.api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI', 'TextChangedP' }, {
    buffer = buf,
    callback = function()
      if timer then
        timer:stop()
      else
        timer = assert(vim.uv.new_timer())
      end
      timer:start(60, 0, vim.schedule_wrap(repaint))
    end,
  })
end

return M
