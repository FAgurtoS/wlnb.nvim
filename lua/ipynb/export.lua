-- ipynb/export.lua - export a notebook to a LaTeX document and compile it to PDF
-- (pandoc for markdown cells, xelatex for the page; code and outputs in colored boxes).

local M = {}

local PREAMBLE = [==[
\documentclass[11pt]{article}
\usepackage[a4paper,margin=2.2cm]{geometry}
\usepackage{fontspec}
\usepackage{amsmath,amssymb}
\usepackage{xcolor}
\usepackage{graphicx}
\usepackage[export]{adjustbox}
\usepackage{hyperref}
\usepackage{listings}
\usepackage[most]{tcolorbox}
\definecolor{codebg}{HTML}{F5F7FA}
\definecolor{codeline}{HTML}{4A6FA5}
\definecolor{outbg}{HTML}{FFFFFF}
\definecolor{outline}{HTML}{9AA5B1}
\definecolor{kw}{HTML}{1F5FA8}
\definecolor{cm}{HTML}{6A737D}
\definecolor{st}{HTML}{A33A3A}
\lstdefinestyle{wl}{
  language=Mathematica, basicstyle=\ttfamily\small, breaklines=true, breakatwhitespace=false,
  columns=fullflexible, keepspaces=true, showstringspaces=false, upquote=true,
  keywordstyle=\color{kw}, commentstyle=\color{cm}\itshape, stringstyle=\color{st},
}
\lstdefinestyle{out}{basicstyle=\ttfamily\footnotesize, breaklines=true, columns=fullflexible, keepspaces=true}
\newtcolorbox{codecell}{breakable, enhanced, colback=codebg, colframe=codeline, boxrule=0pt,
  leftrule=2.5pt, arc=0pt, top=3pt, bottom=3pt, left=6pt, right=6pt, before skip=10pt, after skip=2pt}
\newtcolorbox{outcell}{breakable, enhanced, colback=outbg, colframe=outline, boxrule=0pt,
  leftrule=1pt, arc=0pt, top=3pt, bottom=3pt, left=6pt, right=6pt, before skip=2pt, after skip=10pt}
\setlength{\parindent}{0pt}
\setlength{\parskip}{6pt}
\providecommand{\tightlist}{\setlength{\itemsep}{0pt}\setlength{\parskip}{0pt}}
\begin{document}
]==]

---@param cell Cell
---@return string|nil png_base64, string|nil text
local function output_parts(out)
  local data = out.data or {}
  local png = data['image/png']
  if type(png) == 'table' then
    png = table.concat(png, '')
  end
  local text = out.text or data['text/plain']
  if out.output_type == 'error' then
    text = (out.ename or '') .. ': ' .. (out.evalue or '')
  end
  if type(text) == 'table' then
    text = table.concat(text, '')
  end
  return png, text
end


local TYPESET_CODE = [==[
strs = Import[%q, "RawJSON"];
tex[s_String] := Quiet[Check[ToString[ToExpression[s, InputForm, HoldForm], TeXForm], ""]];
png[s_String] := Quiet[Check[TimeConstrained[BaseEncode[ExportByteArray[Rasterize[
   Style[ToExpression[s, InputForm, HoldForm], FontColor -> Black], Background -> White, ImageResolution -> 220], "PNG"]], 30, ""], ""]];
WriteString["stdout", "@@TYPESET@@" <> ExportString[%s /@ strs, "RawJSON", "Compact" -> True]];
Exit[]
]==]

---Typeset InputForm texts with one throwaway kernel. mode "image" (default, the StandardForm look of
---the notebook in black on white) gives base64 PNGs; "tex" gives LaTeX equations.
---Returns index -> { png = base64 } | { tex = string }; texts that fail are simply missing.
---@param texts string[]
---@param mode string
---@return table<integer, table>
local function typeset(texts, mode)
  local result = {}
  if #texts == 0 then
    return result
  end
  local kernel = require('ipynb.util').find_wolfram_kernel()
  if not kernel then
    return result
  end
  local file = vim.fn.tempname() .. '.json'
  vim.fn.writefile({ vim.json.encode(texts) }, file)
  local fn = mode == 'tex' and 'tex' or 'png'
  local out = vim.system({ kernel, '-noprompt', '-run', TYPESET_CODE:format(file, fn) }, { text = true }):wait()
  vim.fn.delete(file)
  local json = (out.stdout or ''):match('@@TYPESET@@(%b[])')
  if json then
    for i, v in ipairs(vim.json.decode(json)) do
      if type(v) == 'string' and v ~= '' then
        if fn == 'png' then
          result[i] = { png = v }
        elseif #v <= 700 and not v:find('\n') then
          result[i] = { tex = v }
        end
      end
    end
  end
  return result
end

local function is_graphics(text)
  return text and (text:match('^%-Graphics%-') or text:match('^%-Image%-'))
end

-- ?Symbol answers are native Wolfram info panels: keep the image the kernel drew, as in Neovim
local function is_info_box(text)
  return text and text:match('^InformationData%[') ~= nil
end

local function markdown_to_latex(md)
  local res = vim.system({ 'pandoc', '-f', 'markdown', '-t', 'latex', '--wrap=none' }, { stdin = md, text = true }):wait()
  if res.code ~= 0 then
    return '\\begin{verbatim}\n' .. md .. '\n\\end{verbatim}'
  end
  return res.stdout
end

---Keep long outputs readable: first `max` lines plus a note
local function truncate(text, max)
  local lines = vim.split(text, '\n', { plain = true })
  if #lines <= max then
    return text
  end
  local kept = vim.list_slice(lines, 1, max)
  table.insert(kept, ('... (%d more lines not shown)'):format(#lines - max))
  return table.concat(kept, '\n')
end

---Build the LaTeX source. PNG outputs are written into `dir`.
---@param cells Cell[]
---@param opts { title: string|nil, dir: string, max_output_lines: integer|nil, math: string|nil, typeset: table|nil }
---@return string
function M.to_tex(cells, opts)
  local max = opts.max_output_lines or 40
  local parts = { PREAMBLE }
  if opts.title then
    local title = opts.title:gsub('([&%%$#_{}])', '\\%1')
    table.insert(parts, ('{\\Large\\bfseries %s}\\par\\vspace{4pt}\\hrule\\vspace{8pt}\n'):format(title))
  end
  local image_n = 0
  -- Rendered results (text + PNG): redraw them black on white instead of pasting the light-on-dark PNG
  local math_texts, math_index = {}, {}
  for ci, cell in ipairs(cells) do
    for oi, out in ipairs(cell.type == 'code' and cell.outputs or {}) do
      local png, text = output_parts(out)
      if png and text and not is_graphics(text) and not is_info_box(text) then
        table.insert(math_texts, text)
        math_index[ci .. ':' .. oi] = #math_texts
      end
    end
  end
  local typeset_of = opts.typeset or typeset(math_texts, opts.math or os.getenv('WLNB_EXPORT_MATH') or 'image')
  local function save_png(b64)
    image_n = image_n + 1
    local name = ('img%d.png'):format(image_n)
    local f = assert(io.open(opts.dir .. '/' .. name, 'wb'))
    f:write(vim.base64.decode((b64:gsub('%s', ''))))
    f:close()
    return name
  end
  local OUT_LABEL = '{\\scriptsize\\color{outline}Out:}\\par\\smallskip\n'
  for ci, cell in ipairs(cells) do
    if cell.type == 'markdown' then
      table.insert(parts, markdown_to_latex(cell.source))
    elseif cell.type == 'raw' then
      table.insert(parts, '\\begin{codecell}\n\\begin{lstlisting}[style=out]\n' .. cell.source .. '\n\\end{lstlisting}\n\\end{codecell}\n')
    elseif cell.type == 'code' then
      table.insert(parts, '\\begin{codecell}\n\\begin{lstlisting}[style=wl]\n' .. cell.source .. '\n\\end{lstlisting}\n\\end{codecell}\n')
      for oi, out in ipairs(cell.outputs or {}) do
        local png, text = output_parts(out)
        local typed = math_index[ci .. ':' .. oi] and typeset_of[math_index[ci .. ':' .. oi]]
        if typed and typed.tex then
          table.insert(parts, '\\begin{outcell}\n' .. OUT_LABEL .. '\\[ ' .. typed.tex .. ' \\]\n\\end{outcell}\n')
        elseif typed and typed.png then
          table.insert(parts, ('\\begin{outcell}\n%s\\includegraphics[max width=\\linewidth]{%s}\n\\end{outcell}\n'):format(OUT_LABEL, save_png(typed.png)))
        elseif png and (is_graphics(text) or is_info_box(text)) then
          table.insert(parts, ('\\begin{outcell}\n\\includegraphics[max width=\\linewidth,max height=0.45\\textheight]{%s}\n\\end{outcell}\n'):format(save_png(png)))
        elseif text and text ~= '' and not is_graphics(text) then
          table.insert(parts, '\\begin{outcell}\n' .. OUT_LABEL .. '\\begin{lstlisting}[style=out]\n' .. truncate(text, max) .. '\n\\end{lstlisting}\n\\end{outcell}\n')
        end
      end
    end
  end
  table.insert(parts, '\\end{document}\n')
  return table.concat(parts, '\n')
end

---Plain Wolfram script: code cells as they are, markdown and raw cells as comments, no outputs.
---@param cells Cell[]
---@return string[]
function M.to_wl(cells)
  local out = {}
  for _, cell in ipairs(cells) do
    local body = cell.source
    if cell.type ~= 'code' then
      body = '(* ' .. body:gsub('%(%*', '(\\*'):gsub('%*%)', '*\\)') .. ' *)'
    end
    vim.list_extend(out, vim.split(body, '\n', { plain = true }))
    table.insert(out, '')
  end
  if #out > 0 then
    table.remove(out)
  end
  return out
end

---Export cells to `dest`: .pdf, .tex (next to its images folder) or .wl (code only)
---@param cells Cell[]
---@param dest string
---@param title string|nil
---@return string|nil dest, string|nil err
function M.export(cells, dest, title)
  if dest:match('%.wls?$') then
    vim.fn.writefile(M.to_wl(cells), dest)
    return dest
  end
  local as_tex = dest:match('%.tex$') ~= nil
  local dir = as_tex and (dest:gsub('%.tex$', '') .. '_files') or vim.fn.tempname()
  vim.fn.mkdir(dir, 'p')
  local tex = M.to_tex(cells, { title = title, dir = dir })
  if as_tex then
    vim.fn.writefile(vim.split(tex:gsub('{(img%d+%.png)}', '{' .. vim.fn.fnamemodify(dir, ':t') .. '/%1}'), '\n', { plain = true }), dest)
    return dest
  end
  if vim.fn.executable('xelatex') == 0 or vim.fn.executable('pandoc') == 0 then
    return nil, 'xelatex and pandoc are required'
  end
  vim.fn.writefile(vim.split(tex, '\n', { plain = true }), dir .. '/notebook.tex')
  local res = vim.system({ 'xelatex', '-interaction=nonstopmode', '-halt-on-error', 'notebook.tex' }, { cwd = dir, text = true }):wait()
  if vim.fn.filereadable(dir .. '/notebook.pdf') == 0 then
    local log = vim.fn.filereadable(dir .. '/notebook.log') == 1 and vim.fn.readfile(dir .. '/notebook.log') or {}
    local msg = {}
    for _, l in ipairs(log) do
      if l:sub(1, 1) == '!' then
        table.insert(msg, l)
      end
    end
    return nil, 'xelatex failed: ' .. (msg[1] or (res.stdout or ''):sub(-300)) .. ' (kept ' .. dir .. ')'
  end
  vim.fn.rename(dir .. '/notebook.pdf', dest)
  vim.fn.delete(dir, 'rf')
  return dest
end

return M
