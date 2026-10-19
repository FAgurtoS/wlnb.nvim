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


local TEX_CODE = [==[
strs = Import[%q, "RawJSON"];
conv[s_String] := Quiet[Check[ToString[ToExpression[s, InputForm, HoldForm], TeXForm], ""]];
WriteString["stdout", "@@TEX@@" <> ExportString[conv /@ strs, "RawJSON", "Compact" -> True]];
Exit[]
]==]

---Typeset InputForm texts as LaTeX with one throwaway kernel (StandardForm look: real equations).
---Returns a table index -> TeX string; texts that fail or are too wide are simply missing.
---@param texts string[]
---@return table<integer, string>
local function tex_forms(texts)
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
  local out = vim.system({ kernel, '-noprompt', '-run', TEX_CODE:format(file) }, { text = true }):wait()
  vim.fn.delete(file)
  local json = (out.stdout or ''):match('@@TEX@@(%b[])')
  if json then
    for i, tex in ipairs(vim.json.decode(json)) do
      if type(tex) == 'string' and tex ~= '' and #tex <= 700 and not tex:find('\\n') then
        result[i] = tex
      end
    end
  end
  return result
end

local function is_graphics(text)
  return text and (text:match('^%-Graphics%-') or text:match('^%-Image%-'))
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
---@param opts { title: string|nil, dir: string, max_output_lines: integer|nil }
---@return string
function M.to_tex(cells, opts)
  local max = opts.max_output_lines or 40
  local parts = { PREAMBLE }
  if opts.title then
    local title = opts.title:gsub('([&%%$#_{}])', '\\%1')
    table.insert(parts, ('{\\Large\\bfseries %s}\\par\\vspace{4pt}\\hrule\\vspace{8pt}\n'):format(title))
  end
  local image_n = 0
  -- Rendered results (text + PNG): typeset them as equations instead of pasting the dark PNG
  local math_texts, math_index = {}, {}
  for ci, cell in ipairs(cells) do
    for oi, out in ipairs(cell.type == 'code' and cell.outputs or {}) do
      local png, text = output_parts(out)
      if png and text and not is_graphics(text) then
        table.insert(math_texts, text)
        math_index[ci .. ':' .. oi] = #math_texts
      end
    end
  end
  local tex_of = opts.tex_forms or tex_forms(math_texts)
  for ci, cell in ipairs(cells) do
    if cell.type == 'markdown' then
      table.insert(parts, markdown_to_latex(cell.source))
    elseif cell.type == 'raw' then
      table.insert(parts, '\\begin{codecell}\n\\begin{lstlisting}[style=out]\n' .. cell.source .. '\n\\end{lstlisting}\n\\end{codecell}\n')
    elseif cell.type == 'code' then
      table.insert(parts, '\\begin{codecell}\n\\begin{lstlisting}[style=wl]\n' .. cell.source .. '\n\\end{lstlisting}\n\\end{codecell}\n')
      for oi, out in ipairs(cell.outputs or {}) do
        local png, text = output_parts(out)
        local tex = math_index[ci .. ':' .. oi] and tex_of[math_index[ci .. ':' .. oi]]
        if tex then
          table.insert(parts, '\\begin{outcell}\n\\[ ' .. tex .. ' \\]\n\\end{outcell}\n')
        elseif png and is_graphics(text) then
          image_n = image_n + 1
          local name = ('img%d.png'):format(image_n)
          local f = assert(io.open(opts.dir .. '/' .. name, 'wb'))
          f:write(vim.base64.decode((png:gsub('%s', ''))))
          f:close()
          table.insert(parts, ('\\begin{outcell}\n\\includegraphics[max width=\\linewidth,max height=0.45\\textheight]{%s}\n\\end{outcell}\n'):format(name))
        elseif text and text ~= '' and not is_graphics(text) then
          table.insert(parts, '\\begin{outcell}\n\\begin{lstlisting}[style=out]\n' .. truncate(text, max) .. '\n\\end{lstlisting}\n\\end{outcell}\n')
        end
      end
    end
  end
  table.insert(parts, '\\end{document}\n')
  return table.concat(parts, '\n')
end

---Export cells to `dest` (.pdf, or .tex which is written next to its images folder)
---@param cells Cell[]
---@param dest string
---@param title string|nil
---@return string|nil dest, string|nil err
function M.export(cells, dest, title)
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
