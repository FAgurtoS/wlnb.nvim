-- ipynb/nb.lua - convert Mathematica notebooks (.nb) to and from the .wlnb cell model.
-- The work is done by a one-shot WolframKernel (wl/nb_to_wlnb.wl, wl/wlnb_to_nb.wl): no front end
-- needed, but it uses one license slot for a few seconds.
--   .nb -> .wlnb: Input/Code cells become code, Output/Print/Message become outputs (InputForm text, graphics
--                 as PNG), titles/sections/text become markdown. Formatting and dynamic content are lost.
--   .wlnb -> .nb: code becomes Input cells, outputs become Output cells (real typeset expressions, plots as
--                 images), markdown headings become Title/Section/Subsection, other markdown becomes Text.

local M = {}

local function wl_script(name)
  return require('ipynb.util').get_plugin_root() .. '/wl/' .. name
end

---Run a conversion script with a kernel
---@param script string File name inside wl/
---@param input string
---@param output string
---@return boolean ok, string|nil err
local function run_kernel(script, input, output)
  local kernel = require('ipynb.util').find_wolfram_kernel()
  if not kernel then
    return false, 'WolframKernel not found'
  end
  local code = ('$WLNBInput = %s; $WLNBOutput = %s; Get[%s]'):format(
    vim.json.encode(input), vim.json.encode(output), vim.json.encode(wl_script(script)))
  local res = vim.system({ kernel, '-noprompt', '-run', code }, { text = true }):wait()
  if vim.fn.filereadable(output) == 0 then
    return false, 'the kernel produced no output (is a license slot free?) ' .. vim.trim((res.stdout or ''):sub(-200))
  end
  return true
end

---Read a .nb file into cells
---@param path string
---@return Cell[]|nil, string|nil err
function M.read(path)
  local tmp = vim.fn.tempname() .. '.json'
  local ok, err = run_kernel('nb_to_wlnb.wl', vim.fn.fnamemodify(path, ':p'), tmp)
  if not ok then
    return nil, err
  end
  local items = vim.json.decode(table.concat(vim.fn.readfile(tmp), '\n'), { luanil = { object = true, array = true } })
  vim.fn.delete(tmp)
  local cells = {}
  for _, item in ipairs(items) do
    if item.type == 'output' then
      local prev = cells[#cells]
      if prev and prev.type == 'code' then
        local data = { ['text/plain'] = item.text }
        if item.png then
          data['image/png'] = item.png
        end
        table.insert(prev.outputs, {
          output_type = 'execute_result', data = data, metadata = vim.empty_dict(), execution_count = vim.NIL,
        })
      end
    elseif item.type == 'code' then
      table.insert(cells, { type = 'code', source = item.text, metadata = {}, outputs = {} })
    else
      table.insert(cells, { type = 'markdown', source = item.text, metadata = {} })
    end
  end
  return cells
end

---Write cells as a .nb file
---@param path string
---@param cells Cell[]
---@return boolean ok, string|nil err
function M.write(path, cells)
  local model = {}
  for _, cell in ipairs(cells) do
    local entry = { type = cell.type, text = cell.source, outputs = {} }
    for _, out in ipairs(cell.outputs or {}) do
      local data = out.data or {}
      local text = out.text or data['text/plain']
      if type(text) == 'table' then
        text = table.concat(text, '')
      end
      if out.output_type == 'error' then
        text = (out.ename or '') .. ': ' .. (out.evalue or '')
      end
      local png = data['image/png']
      if type(png) == 'table' then
        png = table.concat(png, '')
      end
      -- a rendered result is an expression: the typeset .nb output is made from its text, not its picture
      table.insert(entry.outputs, { text = text or '', png = png and png:gsub('%s', '') or vim.NIL })
    end
    table.insert(model, entry)
  end
  local tmp = vim.fn.tempname() .. '.json'
  vim.fn.writefile({ vim.json.encode(model) }, tmp)
  local ok, err = run_kernel('wlnb_to_nb.wl', tmp, vim.fn.fnamemodify(path, ':p'))
  vim.fn.delete(tmp)
  return ok, err
end

return M
