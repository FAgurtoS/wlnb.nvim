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

local GRAPHICS_PREFIX = '-Graphics- '

---Assets folder of a notebook: <notebook>.assets
---@param path string
---@return string
function M.assets_dir(path)
  return path .. '.assets'
end

---Chained hash of a code cell: its source plus all previous code cells, in order
---@param prev_hash string
---@param source string
---@return string
local function chain_hash(prev_hash, source)
  return vim.fn.sha256(prev_hash .. '\0' .. source):sub(1, 12)
end

---Parse .wlnb lines into cells
---@param lines string[]
---@param path string|nil Notebook path, used to load PNGs from the assets folder
---@return Cell[], table metadata, table<string, boolean> cell_ids
function M.parse(lines, path)
  local cell_ids = {}
  local cells = {}
  local current, body
  local chain = ''

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
        local out_text = unwrap_comment(text)
        local data = { ['text/plain'] = out_text }
        local hash = out_text:match('^%-Graphics%- (%x+)$')
        if hash then
          data['text/plain'] = '-Graphics-'
          local file = path and io.open(M.assets_dir(path) .. '/' .. hash .. '.png', 'rb')
          if file then
            data['image/png'] = vim.base64.encode(file:read('*a'))
            file:close()
            if hash ~= prev._chain then
              data['text/plain'] = '-Graphics- [stale]'
            end
          else
            data['text/plain'] = '-Graphics- [missing image ' .. hash .. ']'
          end
        end
        table.insert(prev.outputs, {
          output_type = 'execute_result',
          data = data,
          metadata = hash and data['image/png'] and { wlnb_hash = hash } or vim.empty_dict(),
          execution_count = vim.NIL,
        })
      end
    else
      local id = state_mod.generate_cell_id(cell_ids)
      cell_ids[id] = true
      local is_input = current.kind == 'input'
      if is_input then
        chain = chain_hash(chain, text)
      end
      table.insert(cells, {
        _chain = is_input and chain or nil,
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
  for _, cell in ipairs(cells) do
    cell._chain = nil
  end

  return cells, M.default_metadata(), cell_ids
end

---Serialize cells into .wlnb lines
---@param cells Cell[]
---@param path string|nil When given, PNG outputs are saved to the assets folder
---@return string[]
function M.serialize(cells, path)
  local lines = { HEADER, '' }
  local function add(kind, text)
    table.insert(lines, MARKER_PREFIX .. kind .. ' *)')
    vim.list_extend(lines, vim.split(text, '\n', { plain = true }))
    table.insert(lines, '')
  end
  local chain = ''
  for _, cell in ipairs(cells) do
    if cell.type == 'code' then
      add('input', cell.source)
      chain = chain_hash(chain, cell.source)
      for _, out in ipairs(cell.outputs or {}) do
        local text = output_text(out)
        local png = out.data and out.data['image/png']
        if type(png) == 'table' then
          png = table.concat(png, '')
        end
        if png and path then
          -- Keep the hash the marker already carries when the image was loaded from disk
          local hash = out.metadata and out.metadata.wlnb_hash or chain
          local dir = M.assets_dir(path)
          local file = dir .. '/' .. hash .. '.png'
          if vim.fn.filereadable(file) == 0 then
            vim.fn.mkdir(dir, 'p')
            local f = io.open(file, 'wb')
            if f then
              f:write(vim.base64.decode((png:gsub('%s', ''))))
              f:close()
            end
          end
          text = GRAPHICS_PREFIX .. hash
        end
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

---Delete PNGs in the assets folder that no marker in the saved file references
---@param path string Notebook path (the saved file is what counts)
---@return integer removed
function M.clean_assets(path)
  local dir = M.assets_dir(path)
  if vim.fn.isdirectory(dir) == 0 or vim.fn.filereadable(path) == 0 then
    return 0
  end
  local used = {}
  for _, line in ipairs(vim.fn.readfile(path)) do
    local hash = line:match('^%(%* %-Graphics%- (%x+) %*%)$')
    if hash then
      used[hash] = true
    end
  end
  local removed = 0
  for _, file in ipairs(vim.fn.glob(dir .. '/*.png', false, true)) do
    if not used[vim.fn.fnamemodify(file, ':t:r')] then
      vim.fn.delete(file)
      removed = removed + 1
    end
  end
  if #vim.fn.glob(dir .. '/*', false, true) == 0 then
    vim.fn.delete(dir, 'd')
  end
  return removed
end

---@param path string
---@return Cell[], table metadata, table<string, boolean> cell_ids
function M.read(path)
  return M.parse(vim.fn.readfile(path), path)
end

---@param path string
---@param cells Cell[]
function M.write(path, cells)
  vim.fn.writefile(M.serialize(cells, path), path)
end

return M
