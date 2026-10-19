-- ipynb/wlnb.lua - .wlnb text format (see FORMAT.md)
-- A valid Wolfram .wl file: every marker and every non-code body is a comment.

local M = {}

local state_mod = require('ipynb.state')

local HEADER = '(* ::wlnb:: v1 *)'
local ASSETS_MARKER = '(* ::assets:: *)'
local SIDECAR_HEADER = '(* ::wlnbi:: v1 *)'
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

---Images file next to a notebook: plot.wlnb -> plot.wlnbi
---@param path string
---@return string
function M.sidecar_path(path)
  return (path:gsub('%.wlnb$', '')) .. '.wlnbi'
end

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
  -- Images may live in the sidecar file instead of the notebook
  local side = path and M.sidecar_path(path)
  if side and vim.fn.filereadable(side) == 1 then
    local _, side_assets = split_assets(vim.fn.readfile(side))
    for hash, b64 in pairs(side_assets) do
      assets[hash] = assets[hash] or b64
    end
  end

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

---Serialize cells into .wlnb lines. PNG outputs go to one section at the end of the notebook
---(embed, the default) or are returned as a second list of lines for the .wlnbi file.
---@param cells Cell[]
---@param _path string|nil Unused (kept for the old call signature)
---@param embed boolean|nil
---@return string[] lines, string[]|nil image_lines
function M.serialize(cells, _path, embed)
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
        if png then
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
  local image_lines
  if #assets > 0 then
    image_lines = {}
    table.insert(image_lines, ASSETS_MARKER)
    table.insert(image_lines, '(* Embedded images (base64 PNG) for the outputs above. Safe to delete: outputs fall back to text. *)')
    table.insert(image_lines, '')
    for _, asset in ipairs(assets) do
      table.insert(image_lines, ('(* ::asset:: %s png *)'):format(asset.hash))
      table.insert(image_lines, '(*')
      for i = 1, #asset.b64, 76 do
        table.insert(image_lines, asset.b64:sub(i, i + 75))
      end
      table.insert(image_lines, '*)')
      table.insert(image_lines, '')
    end
    table.remove(image_lines)
  end
  if #lines > 2 then
    table.remove(lines) -- no blank line at end of file
  end
  if image_lines and embed ~= false then
    table.insert(lines, '')
    vim.list_extend(lines, image_lines)
    return lines
  end
  if image_lines then
    local header = { SIDECAR_HEADER, '(* Images for the notebook next to this file. Keep them together: copy both. *)', '' }
    return lines, vim.list_extend(header, image_lines)
  end
  return lines
end

---@param path string
---@return Cell[], table metadata, table<string, boolean> cell_ids
function M.read(path)
  local cells, metadata, cell_ids = M.parse(vim.fn.readfile(path), path)
  local missing = 0
  for _, cell in ipairs(cells) do
    for _, out in ipairs(cell.outputs or {}) do
      local text = out.data and out.data['text/plain']
      if type(text) == 'string' and text:find('[missing image', 1, true) then
        missing = missing + 1
      end
    end
  end
  if missing > 0 then
    vim.schedule(function()
      vim.notify(('%d image(s) missing: expected %s next to the notebook (copy both files together)'):format(
        missing, vim.fn.fnamemodify(M.sidecar_path(path), ':t')), vim.log.levels.WARN)
    end)
  end
  return cells, metadata, cell_ids
end

---@param path string
---@param cells Cell[]
---@param mode 'sidecar'|'embedded'|nil Where images go; default from the `assets` setting ('sidecar')
function M.write(path, cells, mode)
  if not mode then
    local ok, cfg = pcall(function()
      return require('ipynb.config').get()
    end)
    mode = ok and cfg.assets or 'sidecar'
  end
  local lines, image_lines = M.serialize(cells, nil, mode == 'embedded')
  vim.fn.writefile(lines, path)
  local side = M.sidecar_path(path)
  if image_lines then
    vim.fn.writefile(image_lines, side)
  elseif vim.fn.filereadable(side) == 1 and vim.fn.readfile(side, '', 1)[1] == SIDECAR_HEADER then
    vim.fn.delete(side) -- no images left: do not keep a stale images file
  end
  -- Old files kept images in <notebook>.assets; they are in the notebook or sidecar now
  local dir = M.assets_dir(path)
  if vim.fn.isdirectory(dir) == 1 then
    local only_ours = true
    for _, name in ipairs(vim.fn.readdir(dir)) do
      only_ours = only_ours and (name:match('%.png$') ~= nil or name == '.gitkeep' or name == '.DS_Store')
    end
    if only_ours then -- never remove a folder that holds anything else
      vim.fn.delete(dir, 'rf')
    end
  end
end

return M
