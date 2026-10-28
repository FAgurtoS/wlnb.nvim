-- ipynb/wln.lua - convert WLJS .wln notebooks to and from the .wlnb cell model.
-- Two .wln flavours exist: the text one (sections between %---% lines) is parsed here;
-- the legacy one (a Wolfram association dump) is read through a one-shot WolframKernel.
-- Text outputs (default "codemirror" and "print" displays) are kept as InputForm text with the
-- editor's box markers removed; rendered ones (html, markdown, js, ...) are dropped: run the cells again.

local M = {}

local WIDTH = 75

local function delimiter(title)
  if not title then
    return '%' .. string.rep('-', WIDTH - 2) .. '%'
  end
  local rest = WIDTH - 2 - #title - 2
  local left = math.floor(rest / 2)
  return '%' .. string.rep('-', left) .. '%' .. title .. '%' .. string.rep('-', rest - left) .. '%'
end

---@return boolean is_delimiter, string|nil title
local function parse_delimiter(line)
  if #line < 20 or line:sub(1, 2) ~= '%-' or line:sub(-2) ~= '-%' then
    return false
  end
  return true, line:match('^%%%-+%%(%w+)%%%-+%%$')
end

---A WLJS input body starts with ".<lang>" for non-Wolfram cells (.md, .html, .mjs, ...)
---@param data string
---@return Cell
local function input_cell(data)
  local lang, rest = data:match('^%.(%w+)\n(.*)$')
  if not lang then
    lang = data:match('^%.(%w+)$')
    rest = ''
  end
  if lang == 'md' then
    return { type = 'markdown', source = (rest:gsub('^\n+', ''):gsub('\n+$', '')), metadata = {} }
  elseif lang then
    return { type = 'raw', source = (data:gsub('\n+$', '')), metadata = {} }
  end
  return { type = 'code', source = (data:gsub('^\n+', ''):gsub('\n+$', '')), metadata = {}, outputs = {} }
end

---Output text kept as-is, minus the WLJS box markers such as (*SpB[*) (*|*) (*]SpB*)
---@param text string
---@return string
local function clean_output(text)
  text = text:gsub('%(%*%a+%[%*%)', ''):gsub('%(%*|%*%)', ''):gsub('%(%*%]%a+%*%)', '')
  return (text:gsub('^\n+', ''):gsub('\n+$', ''))
end

---@param cells Cell[]
---@param display string|nil
---@param data string
local function attach_output(cells, display, data)
  local prev = cells[#cells]
  if prev and prev.type == 'code' and (display == nil or display == '' or display == 'codemirror' or display == 'print') then
    local text = clean_output(data)
    local last = prev.outputs[#prev.outputs]
    if text ~= '' and display == 'print' and last and last._print then
      last.data['text/plain'] = last.data['text/plain'] .. '\n' .. text -- consecutive Print lines form one output
    elseif text ~= '' then
      table.insert(prev.outputs, {
        _print = display == 'print' or nil,
        output_type = 'execute_result',
        data = { ['text/plain'] = text },
        metadata = vim.empty_dict(),
        execution_count = vim.NIL,
      })
    end
  end
end

---Parse the text flavour
---@param lines string[]
---@return Cell[]
function M.parse(lines)
  local cells = {}
  local in_cells, in_header = false, true
  local seg, header = {}, {}

  local function flush_body()
    local ctype = header.Type
    if ctype == 'Input' then
      table.insert(cells, input_cell(table.concat(seg, '\n')))
    elseif ctype == 'Output' then
      attach_output(cells, header.Display, table.concat(seg, '\n'))
    end
  end

  for _, line in ipairs(lines) do
    local is_delim, title = parse_delimiter(line)
    if is_delim and title == 'Cells' then
      in_cells, in_header, seg, header = true, true, {}, {}
    elseif is_delim and title == 'EndOfCells' then
      if in_cells and not in_header then
        flush_body()
      end
      break
    elseif in_cells and is_delim and not title then
      if in_header then
        header = {}
        for _, l in ipairs(seg) do
          local k, v = l:match('^(%w+):%s*(.*)$')
          if k then
            header[k] = v
          end
        end
      else
        flush_body()
      end
      in_header, seg = not in_header, {}
    elseif in_cells then
      table.insert(seg, line)
    end
  end
  return cells
end

---Serialize cells to the text flavour (inputs only)
---@param cells Cell[]
---@return string[]
function M.serialize(cells)
  local out = {
    delimiter('Notebook'), 'HaveToSaveAs: false', 'ObjectFields:', '  - Objects', '  - Symbols', 'Quick: true',
    delimiter(), '', '', delimiter('Cells'),
  }
  for i, cell in ipairs(cells) do
    local body = cell.source
    if cell.type == 'markdown' then
      body = '.md\n' .. body
    end
    if i > 1 then
      table.insert(out, delimiter())
    end
    table.insert(out, 'Type: Input')
    table.insert(out, delimiter())
    vim.list_extend(out, vim.split(body, '\n', { plain = true }))
    table.insert(out, '')
  end
  vim.list_extend(out, {
    delimiter('EndOfCells'), '', '', '', delimiter('Objects'), delimiter('EndOfObjects'), '', '', '',
    delimiter('Symbols'), delimiter('EndOfSymbols'), '', '', '', '', '', delimiter('EndOfNotebook'),
  })
  return out
end

local LEGACY_CODE = [==[
data = Get[%q];
cells = Lookup[data, "Cells", {}];
WriteString["stdout", "@@WLN@@" <> ExportString[Map[<|"type" -> ToString[Lookup[#, "Type", ""]],
  "display" -> ToString[Lookup[#, "Display", ""]],
  "data" -> With[{d = Lookup[#, "Data", ""]}, If[StringQ[d], d, ""]]|> &, cells], "RawJSON", "Compact" -> True]];
Exit[]
]==]

---Convert a legacy (association dump) .wln with a one-shot kernel
---@param path string
---@return Cell[]|nil, string|nil err
local function parse_legacy(path)
  local kernel = require('ipynb.util').find_wolfram_kernel()
  if not kernel then
    return nil, 'WolframKernel not found'
  end
  local out = vim.system({ kernel, '-noprompt', '-run', LEGACY_CODE:format(path) }, { text = true }):wait()
  local json = (out.stdout or ''):match('@@WLN@@(%b[])')
  if not json then
    return nil, 'could not read the legacy .wln (is a kernel slot free?)'
  end
  local cells = {}
  for _, c in ipairs(vim.json.decode(json)) do
    if c.type == 'Input' then
      table.insert(cells, input_cell(c.data))
    elseif c.type == 'Output' then
      attach_output(cells, c.display, c.data)
    end
  end
  return cells
end

---Read a .wln file of either flavour
---@param path string
---@return Cell[]|nil, string|nil err
function M.read(path)
  local lines = vim.fn.readfile(path)
  for _, l in ipairs(lines) do
    if l ~= '' then
      if l:sub(1, 2) == '<|' then
        return parse_legacy(path)
      end
      break
    end
  end
  return M.parse(lines)
end

---Convert between .wln and .wlnb (direction from the extensions)
---@param src string
---@param dest string|nil Defaults to src with the other extension
---@return string|nil dest, string|nil err
function M.convert(src, dest)
  local wlnb = require('ipynb.wlnb')
  if src:match('%.nb$') then
    dest = dest or src:gsub('%.nb$', '.wlnb')
    local cells, err = require('ipynb.nb').read(src)
    if not cells then
      return nil, err
    end
    wlnb.write(dest, cells)
  elseif src:match('%.wlnb$') and dest and dest:match('%.nb$') then
    local ok, err = require('ipynb.nb').write(dest, wlnb.read(src))
    if not ok then
      return nil, err
    end
  elseif src:match('%.wln$') then
    dest = dest or src:gsub('%.wln$', '.wlnb')
    local cells, err = M.read(src)
    if not cells then
      return nil, err
    end
    wlnb.write(dest, cells)
  elseif src:match('%.wlnb$') then
    dest = dest or src:gsub('%.wlnb$', '.wln')
    vim.fn.writefile(M.serialize((wlnb.read(src))), dest)
  else
    return nil, 'expected a .nb, .wln or .wlnb file'
  end
  return dest
end

return M
