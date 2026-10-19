-- ipynb/wlnb.lua - .wlnb text format (see FORMAT.md)
-- A valid Wolfram .wl file: every marker and every non-code body is a comment.

local M = {}

local state_mod = require('ipynb.state')

local HEADER = '(* ::wlnb:: v1 *)'
local ASSETS_MARKER = '(* ::assets:: *)'
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

---Split the embedded-images section off the cells.
---@param lines string[]
---@return string[] cell_lines, table<string, string> assets hash -> base64 PNG
local function split_assets(lines)
  local assets = {}
  local at
  for i, line in ipairs(lines) do
    if line == ASSETS_MARKER then
      at = i
      break
    end
  end
  if not at then
    return lines, assets
  end
  local cell_lines = vim.list_slice(lines, 1, at - 1)
  while cell_lines[#cell_lines] == '' do
    table.remove(cell_lines)
  end
  local i = at + 1
  while i <= #lines do
    local hash = lines[i]:match('^%(%* ::asset:: (%x+) png %*%)$')
    if hash and lines[i + 1] == '(*' then
      local b64, j = {}, i + 2
      while j <= #lines and lines[j] ~= '*)' do
        table.insert(b64, lines[j])
        j = j + 1
      end
      assets[hash] = table.concat(b64, '')
      i = j
    end
    i = i + 1
  end
  return cell_lines, assets
end

---Parse .wlnb lines into cells
---@param lines string[]
---@param path string|nil Notebook path; only used to find images of old files in <notebook>.assets
---@return Cell[], table metadata, table<string, boolean> cell_ids
function M.parse(lines, path)
  local assets
  lines, assets = split_assets(lines)

  ---PNG for a hash: embedded block first, then the folder old files used
  local function load_png(hash)
    if assets[hash] then
      return assets[hash]
    end
    local file = path and io.open(M.assets_dir(path) .. '/' .. hash .. '.png', 'rb')
    if file then
      local data = vim.base64.encode(file:read('*a'))
      file:close()
      return data
    end
  end
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
        local body, rhash = out_text:match('^(.*)\n%-Rendered%- (%x+)$')
        if rhash then
          -- Rendered math: InputForm text plus a PNG of the StandardForm
          data['text/plain'] = body
          data['image/png'] = load_png(rhash)
        elseif hash then
          data['text/plain'] = '-Graphics-'
          data['image/png'] = load_png(hash)
          if not data['image/png'] then
            data['text/plain'] = '-Graphics- [missing image ' .. hash .. ']'
          elseif hash ~= prev._chain then
            data['text/plain'] = '-Graphics- [stale]'
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

---Serialize cells into .wlnb lines. PNG outputs are embedded in one section at the end.
---@param cells Cell[]
---@param _path string|nil Unused (images are embedded; kept for the old call signature)
---@return string[]
function M.serialize(cells, _path)
  local lines = { HEADER, '' }
  local function add(kind, text)
    table.insert(lines, MARKER_PREFIX .. kind .. ' *)')
    vim.list_extend(lines, vim.split(text, '\n', { plain = true }))
    table.insert(lines, '')
  end
  local assets, seen = {}, {}
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
        local is_graphics = text and (text:match('^%-Graphics%-') or text:match('^%-Image%-'))
        -- ?Symbol info panels are big and cheap to regenerate: keep their text only
        local is_info = text and text:match('^InformationData%[')
        if png and not is_info then
          local bytes = vim.base64.decode((png:gsub('%s', '')))
          -- A graphics marker keeps the hash it was loaded with; rendered math is named after its bytes
          local hash = is_graphics and (out.metadata and out.metadata.wlnb_hash or chain)
            or vim.fn.sha256(bytes):sub(1, 12)
          if not seen[hash] then
            seen[hash] = true
            table.insert(assets, { hash = hash, b64 = vim.base64.encode(bytes) })
          end
          text = is_graphics and (GRAPHICS_PREFIX .. hash) or (text .. '\n-Rendered- ' .. hash)
        end
        if text then
          add('output', wrap_comment(text))
        end
      end
    else
      add(cell.type, wrap_comment(cell.source))
    end
  end
  if #assets > 0 then
    table.insert(lines, ASSETS_MARKER)
    table.insert(lines, '(* Embedded images (base64 PNG) for the outputs above. Safe to delete: outputs fall back to text. *)')
    table.insert(lines, '')
    for _, asset in ipairs(assets) do
      table.insert(lines, ('(* ::asset:: %s png *)'):format(asset.hash))
      table.insert(lines, '(*')
      for i = 1, #asset.b64, 76 do
        table.insert(lines, asset.b64:sub(i, i + 75))
      end
      table.insert(lines, '*)')
      table.insert(lines, '')
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
  return M.parse(vim.fn.readfile(path), path)
end

---@param path string
---@param cells Cell[]
function M.write(path, cells)
  vim.fn.writefile(M.serialize(cells), path)
  -- Old files kept images in <notebook>.assets; they are embedded now, so the folder is obsolete
  local dir = M.assets_dir(path)
  if vim.fn.isdirectory(dir) == 1 then
    for _, file in ipairs(vim.fn.glob(dir .. '/*.png', false, true)) do
      vim.fn.delete(file)
    end
    vim.fn.delete(dir, 'd') -- only succeeds when empty
  end
end

return M
