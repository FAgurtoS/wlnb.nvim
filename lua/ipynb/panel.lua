-- ipynb/panel.lua - Output panel: current cell's output as real, selectable text in a split

local M = {}

local PANEL_HEIGHT = 10

---@param state NotebookState
---@return boolean
local function is_open(state)
  local p = state.output_panel
  return p ~= nil and p.win ~= nil and vim.api.nvim_win_is_valid(p.win)
end

---Cell whose output the panel should show
---@param state NotebookState
---@return number|nil
local function current_cell_idx(state)
  if state.edit_state and state.edit_state.cell_idx then
    return state.edit_state.cell_idx
  end
  if vim.api.nvim_get_current_buf() == state.facade_buf then
    local line = vim.api.nvim_win_get_cursor(0)[1] - 1
    return require('ipynb.cells').get_cell_at_line(state, line)
  end
  return state.output_panel and state.output_panel.cell_idx
end

---Redraw the panel for the cell under the cursor (no-op when closed)
---@param state NotebookState
function M.refresh(state)
  if not is_open(state) then
    return
  end
  local panel = state.output_panel
  local idx = current_cell_idx(state)
  panel.cell_idx = idx
  local cell = idx and state.cells[idx]
  local lines = cell and require('ipynb.output').build_output_text(cell, true) or {}
  if #lines == 0 then
    lines = { '(no output)' }
  end
  vim.bo[panel.buf].modifiable = true
  vim.api.nvim_buf_set_lines(panel.buf, 0, -1, false, lines)
  vim.bo[panel.buf].modifiable = false
end

---@param state NotebookState
function M.close(state)
  if is_open(state) then
    vim.api.nvim_win_close(state.output_panel.win, true)
  end
  if state.output_panel and state.output_panel.augroup then
    pcall(vim.api.nvim_del_augroup_by_id, state.output_panel.augroup)
  end
  state.output_panel = nil
end

---@param state NotebookState
function M.open(state)
  if is_open(state) then
    return
  end
  local origin = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].filetype = 'notebook_output'
  vim.bo[buf].modifiable = false

  vim.cmd('botright ' .. PANEL_HEIGHT .. 'split')
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, buf)
  vim.wo[win].number = false
  vim.wo[win].signcolumn = 'no'
  vim.wo[win].winfixheight = true
  vim.wo[win].wrap = true
  vim.api.nvim_set_current_win(origin)

  local augroup = vim.api.nvim_create_augroup('NotebookOutputPanel' .. state.facade_buf, { clear = true })
  state.output_panel = { buf = buf, win = win, augroup = augroup }

  vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI', 'BufEnter' }, {
    group = augroup,
    callback = function()
      if vim.api.nvim_get_current_buf() ~= buf then
        M.refresh(state)
      end
    end,
  })
  vim.api.nvim_create_autocmd('WinClosed', {
    group = augroup,
    pattern = tostring(win),
    callback = function()
      state.output_panel = nil
      pcall(vim.api.nvim_del_augroup_by_id, augroup)
    end,
  })
  vim.keymap.set('n', 'q', function()
    M.close(state)
  end, { buffer = buf, nowait = true, desc = 'Close output panel' })

  M.refresh(state)
end

---@param state NotebookState
function M.toggle(state)
  if is_open(state) then
    M.close(state)
  else
    M.open(state)
  end
end

return M
