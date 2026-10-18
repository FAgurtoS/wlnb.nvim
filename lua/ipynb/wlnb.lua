-- ipynb/wlnb.lua - .wlnb text format (see FORMAT.md)
-- A valid Wolfram .wl file: every marker and every non-code body is a comment.

local M = {}

local state_mod = require('ipynb.state')

local HEADER = '(* ::wlnb:: v0 *)'
local MARKER_PREFIX = '(* ::cell:: '

-- Comment bodies may not contain a raw "(*" or "*)": they would nest or close early.
local function escape(text)
  return (text:gsub('%(%*', '(\\*'):gsub('%*%)', '*\\)'))
end

local function unescape(text)
  return (text:gsub('%(\\%*', '(*'):gsub('%*\\%)', '*)'))
end

local function wrap_comment(text)
  return '(* ' .. escape(text) .. ' *)'
end

local function unwrap_comment(text)
  local inner = text:match('^%(%* (.*) %*%)$')
  return unescape(inner or text)
end

---Default metadata for a Wolfram notebook
---@return table
function M.default_metadata()
  return {
    kernelspec = { display_name = 'Wolfram Language', language = 'wolfram', name = 'wolframscript' },
    language_info = { name = 'wolfram' },
    nbformat = 4,
    nbformat_minor = 5,
  }
end

---Text of one Jupyter-style output (only text for now)
---@param out table
---@return string|nil
local function output_text(out)
  local function join(v)
    return type(v) == 'table' and table.concat(v, '') or v
  end
  if out.output_type == 'stream' then
    return join(out.text)
  elseif out.data and out.data['text/plain'] then
    return join(out.data['text/plain'])
  elseif out.output_type == 'error' then
    return (out.ename or '') .. ': ' .. (out.evalue or '')
  end
end

---Parse .wlnb lines into cells
---@param lines string[]
---@return Cell[], table metadata, table<string, boolean> cell_ids
function M.parse(lines)
  local cell_ids = {}
  local cells = {}
  local current, body

  -- The blank separator is only present between cells, not after the last one.
  local function finish(at_eof)
    if not current then
      return
    end
    if not at_eof and body[#body] == '' then
      table.remove(body)
    end
    local text = table.concat(body, '\n')
    if current.kind == 'output' then
      local prev = cells[#cells]
      if prev and prev.type == 'code' then
        table.insert(prev.outputs, {
          output_type = 'execute_result',
          data = { ['text/plain'] = unwrap_comment(text) },
          metadata = vim.empty_dict(),
          execution_count = vim.NIL,
        })
      end
    else
      local id = state_mod.generate_cell_id(cell_ids)
      cell_ids[id] = true
      local is_input = current.kind == 'input'
      table.insert(cells, {
        id = id,
        type = is_input and 'code' or current.kind,
        source = is_input and text or unwrap_comment(text),
        metadata = {},
        outputs = is_input and {} or nil,
      })
    end
    current = nil
  end

  for _, line in ipairs(lines) do
    local kind = line:match('^%(%* ::cell:: (%w+) %*%)$')
    if kind then
      finish()
      current, body = { kind = kind }, {}
    elseif current then
      table.insert(body, line)
    end
  end
  finish(true)

  return cells, M.default_metadata(), cell_ids
end

---Serialize cells into .wlnb lines
---@param cells Cell[]
---@return string[]
function M.serialize(cells)
  local lines = { HEADER, '' }
  local function add(kind, text)
    table.insert(lines, MARKER_PREFIX .. kind .. ' *)')
    vim.list_extend(lines, vim.split(text, '\n', { plain = true }))
    table.insert(lines, '')
  end
  for _, cell in ipairs(cells) do
    if cell.type == 'code' then
      add('input', cell.source)
      for _, out in ipairs(cell.outputs or {}) do
        local text = output_text(out)
        if text then
          add('output', wrap_comment(text))
        end
      end
    else
      add(cell.type, wrap_comment(cell.source))
    end
  end
  if #lines > 2 then
    table.remove(lines) -- no blank line at end of file
  end
  return lines
end

---@param path string
---@return Cell[], table metadata, table<string, boolean> cell_ids
function M.read(path)
  return M.parse(vim.fn.readfile(path))
end

---@param path string
---@param cells Cell[]
function M.write(path, cells)
  vim.fn.writefile(M.serialize(cells), path)
end

return M
