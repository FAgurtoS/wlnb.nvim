# wlnb.nvim

Wolfram Language notebooks in Neovim. A fork of [ajbucci/ipynb.nvim](https://github.com/ajbucci/ipynb.nvim)
that edits plain-text `.wlnb` notebooks (agent-readable, git-friendly) and runs cells on a local
`WolframKernel`. Outputs are saved as `InputForm` text, so they can be copied and pasted.

> [!IMPORTANT]
> Experimental. See [PLAN.md](PLAN.md) for status and [FORMAT.md](FORMAT.md) for the `.wlnb` format.

## Quick start

The Wolfram Engine license limits how many kernels can run at once (2 on the free one; the limit is
read from `$MaxLicenseProcesses` and cached). `:NotebookKernels` lists every `WolframKernel` process of
your user, including those of other apps, with the count against the limit. When you start a kernel at
the limit, you are asked which one to stop first.

Requirements: Neovim 0.10+, Wolfram Engine or Mathematica (`wolframscript`) and Python 3.
On macOS, everything else is in the [Brewfile](Brewfile): `brew bundle`. It installs
`tree-sitter-cli`, `zig` (a C compiler for the parser if you have no Xcode command line tools;
put `scripts/zig-cc` first on `PATH` when the parser is first compiled) and Ghostty.

```sh
git clone https://github.com/FAgurtoS/wlnb.nvim ~/wlnb.nvim
cd ~/wlnb.nvim
# first run only (compiles the parser, clones test dependencies into tests/.nvim-test):
PATH=$PWD/scripts/zig-cc:$PATH nvim --headless -u tests/minimal_init.lua -l tests/run_all.lua
# open a notebook with the plugin loaded:
./scripts/wlnb examples/basic.wlnb
```

`scripts/wlnb` is a throwaway launcher with a clean config (`scripts/init.lua`). To use the plugin in
your own Neovim, so that any `.wlnb` (for example opened from ranger) loads as cells, add it as a
local plugin (lazy.nvim):

```lua
{
  dir = vim.fn.expand('~/wlnb.nvim'),
  name = 'wlnb.nvim',
  main = 'ipynb',
  dependencies = { 'nvim-treesitter/nvim-treesitter', 'neovim/nvim-lspconfig' },
  -- optional: put zig-cc first on PATH if you have no working C compiler
  init = function() vim.env.PATH = vim.fn.expand('~/wlnb.nvim/scripts/zig-cc:') .. vim.env.PATH end,
  opts = {},
},
{ 'folke/snacks.nvim', opts = { image = { enabled = true } } }, -- inline images
```

The parser compiles on first load; the first open may print a tree-sitter error, reopen the file.
A status line component is available as `require('ipynb.kernels').status()` (returns text and a
highlight group). Notebook shortcuts start with a comma (`,`) and only exist inside `.wlnb` buffers.

`NotebookDirectory[]` works in cells (it returns the notebook's folder), so notebooks written for WLJS or Mathematica that build file paths from it run unchanged.

## Syntax colors

Wolfram cells are colored by a tiny built-in highlighter (`lua/ipynb/wl_highlight.lua`): comments,
strings, numbers, built-in symbols, any name applied with `[` (your own and package functions), patterns (`x_`), operators and slots. It paints once when a cell
changes instead of re-running tree-sitter queries on every redraw, so scrolling stays smooth. The
colors follow your theme (`WlComment`, `WlString`, `WlNumber`, `WlSystem`, `WlCall`, `WlPattern`, `WlOperator`,
`WlSlot` are links to standard groups; override them as usual). To use the tree-sitter colors instead,
set `vim.g.wlnb_highlight = 'treesitter'` before the plugin loads.

## Performance with long expressions

With `vim.g.wlnb_highlight = 'treesitter'`, syntax colors are skipped for cells with a line longer than 1200 characters or more than 60,000
bytes (tree-sitter re-runs its queries over the whole line on every redraw, which made moving around
a notebook with huge equations slow). Those cells are shown as plain text, in the notebook and in edit
mode. Change the limits with `vim.g.wlnb_highlight_max_line` and `vim.g.wlnb_highlight_max_bytes`.

## Completion

While you type Wolfram code in a cell, a popup offers the built-in symbols (7,700 `System`` names) with
their usage text. It works as a small in-process LSP server fed by `data/wolfram_symbols.json`, so no
kernel is needed. With blink.cmp or nvim-cmp their LSP source shows it; without one, Neovim's own
completion popup is turned on for the cell (`Ctrl-y` accepts, `Ctrl-n`/`Ctrl-p` move). It starts after
two characters. Regenerate the list with a kernel after a Wolfram upgrade:
`WolframKernel -noprompt -run 'Get["scripts/gen_symbols.wl"]; Exit[]'`.
Your own definitions (`f[x_] := ...`) are not offered yet.

## Export to PDF

`,e` or `:NotebookExport [file.pdf|file.tex]` inside the open notebook (it exports what is in the buffer, saved or not), or `scripts/wlnb-export notebook.wlnb [out.pdf]` from a shell, builds a PDF
that looks like the notebook: code in boxes with Wolfram syntax colors, outputs below, plots as
images, markdown cells typeset by pandoc (LaTeX math works), and results as real typeset equations
(StandardForm look, via `TeXForm` from a throwaway kernel, so it needs one free license slot; without
one, or for very wide expressions, the InputForm text is printed instead). Long text outputs are cut
after 40 lines. A `.tex` destination writes the LaTeX source plus an images folder, and a `.wl` destination writes plain Wolfram code (markdown as comments, no outputs). Needs `pandoc` and
`xelatex` (TeX Live / MacTeX).

## Agents (Claude Code and others)

`skills/wlnb/SKILL.md` teaches an agent the format and how to drive a notebook that is open in
Neovim: `scripts/wlnb-agent list|get|set|insert|delete|run|save notebook.wlnb` talks to the running
Neovim through `nvim --server` (no setup), so edits and runs show up live and nothing on disk is
overwritten. For Claude Code, link it once: `ln -s ~/wlnb.nvim/skills/wlnb ~/.claude/skills/`.
`run` starts the kernel if needed and refuses when the license limit is reached instead of prompting.

## Converting notebooks (.nb and WLJS .wln)

```sh
scripts/wlnb-convert notebook.nb                 # Mathematica -> notebook.wlnb
scripts/wlnb-convert notebook.wlnb out.nb        # -> Mathematica notebook
scripts/wlnb-convert notebook.wln                # WLJS -> notebook.wlnb
scripts/wlnb-convert notebook.wlnb out.wln       # -> WLJS text format
```

or `:NotebookConvert source [destination]` inside Neovim (no notebook needs to be open).

**Mathematica `.nb`** (both ways, no front end needed; a one-shot kernel does the work, so one license
slot is used for a few seconds). Reading: Input/Code cells become code (as InputForm text), Output, Print
and Message become outputs (graphics as PNG), Title/Section/Text and similar become markdown (headings
as `#`). Cell formatting, dynamic content and notebook options are lost. Writing: code becomes Input
cells, outputs become real typeset Output cells (plots as images), `#` headings become
Title/Section/Subsection, other markdown becomes Text. Tested on the xAct documentation notebooks, for
example `xTensorDoc.nb` (8 MB, 1292 input cells) converts to a 640 KB `.wlnb` in about 15 seconds.

**WLJS `.wln`.** Both flavours are read: the text one directly, and the older association dump through
a one-shot `WolframKernel` (it needs a free license slot). Markdown cells stay markdown, other WLJS cells
(`.html`, `.js`, `.slide`, ...) become `raw` cells, and text outputs (`codemirror` and `print` displays) are
kept as InputForm text with the editor's box markers removed. Rendered outputs (html, graphics, ...) are
dropped: run the cells again. Writing `.wln` saves inputs only.

## Using a notebook

Cells are navigated in *Notebook mode*; `i` or `Enter` opens the current cell for editing
(*Cell mode*), `Esc` returns to Notebook mode. `:w` saves the `.wlnb` file.

| Action | Keys |
|---|---|
| Next / previous cell | `]]` / `[[` |
| Edit cell / leave cell | `i` or `Enter` / `Esc` |
| New cell below / above | `,b` / `,a` |
| Cut cell / paste below / paste above | `dd` / `p` / `P` |
| Delete cell without copying | `:NotebookDeleteCell` |
| Undo / redo | `u` / `Ctrl-r` |
| Move cell down / up | `Alt-j` / `Alt-k` |
| Make cell markdown / code | `,m` / `,c` |
| Start kernel (about 9 s) | `,s` |
| Run cell | `,x` |
| Run cell and go to next | `,X` |
| Toggle output panel (selectable text) | `,p` (`:NotebookOutputPanel`) |
| Copy output to the clipboard | `,y` (`:NotebookYankOutput`) |
| Open output in a float | `,o` |
| List running Wolfram kernels / stop one | `,k` (`:NotebookKernels`; `j`/`k` select a kernel, `x` stops it, `r` refreshes, `q` closes; no prefix needed inside the window) |
| Stop this notebook's kernel / restart it | `,q` / `,r` |
| Interrupt (kills and restarts the kernel) | `Ctrl-c` |

The launcher's status line shows `Kernels n/max`: kernels running on the machine against the license
limit, green when this notebook's kernel is ready, yellow while it runs a cell, grey when it is not
started. Start the kernel before running cells; otherwise you get "No kernel connected". Closing a
notebook stops its kernel, and so does quitting Neovim. The kernel keeps
variables between cells. Interrupt is implemented by killing and restarting the kernel, so
variables are lost (a piped `WolframKernel` dies on SIGINT).

The `Alt` keymaps need the terminal to send Option as Alt, which on some keyboard layouts (e.g.
Spanish) stops Option from typing `[ ] { } \\ |`. If that affects you, leave it off and use the
comma keymaps and the `:Notebook...` commands instead.

## Images

Plots are rendered to PNG by the kernel and shown as `-Graphics-` in the file. Showing them inline
needs [snacks.nvim](https://github.com/folke/snacks.nvim) (the launcher loads it from
`tests/.nvim-test/share/ipynb-test/lazy/snacks.nvim` when present) and a terminal with the kitty
graphics protocol: kitty, Ghostty or WezTerm. iTerm2 is not supported by snacks.nvim.

Output is drawn as virtual lines, which Neovim cannot select. To select it like any text, open the
output panel (`,p`): a split at the bottom with the current cell's output as a real buffer,
that follows the cursor and updates after each run. Jump into it with `Ctrl-w j`, use `v`/`V`/`y`
as usual, and close it with `q` (or `,p` again). `,y` copies the whole output without
opening anything.

## Syntax highlighting

Code cells are highlighted with the official
[tree-sitter-wolfram](https://github.com/WolframResearch/tree-sitter-wolfram) grammar, vendored in
`tree-sitter-wolfram/` (the parser compiles automatically the first time, like the cell parser).

## Limitations

- No variable inspector or diagnostics for Wolfram (completion with usage text works, see above).
- Every result (numbers, expressions, lists, matrices...) is shown as a rendered StandardForm image; `,y` / `:NotebookYankOutput` still copy the InputForm text. Without image support the InputForm text is shown instead. Set `WLNB_RENDER_MATH=0` to turn rendering off, or `WLNB_MATH_STYLE=light` (black on white) / `dark` (Wolfram's dark box) instead of the default transparent background with light text.
- Plot and result images are saved on `:w` next to the notebook in a sidecar file of the same name: `plot.wlnb` (readable cells) + `plot.wlnbi` (images). Copy them together: `:NotebookCopy destination` copies both, and a notebook opened without its `.wlnbi` still works but warns that images are missing. `require('ipynb').setup({ assets = 'embedded' })` puts the images at the end of the `.wlnb` instead (one file, ugly tail). Old notebooks with a `<notebook>.assets` folder are migrated when you save. If the code above a plot changed since it ran, the output shows `[stale]`. See [FORMAT.md](FORMAT.md).


## Acknowledgements and license

wlnb.nvim is a fork of [ajbucci/ipynb.nvim](https://github.com/ajbucci/ipynb.nvim) (Apache License 2.0).
The notebook editing engine (facade buffer, modal cell editing, shadow buffers for LSP, kernel bridge,
output rendering, images) comes from that project; this fork adapts it to Wolfram Language: the
`.wlnb` / `.wlnbi` formats, the Wolfram kernel bridge, highlighting, completion, export, converters and the
agent tools. Many thanks to [@ajbucci](https://github.com/ajbucci) and the ipynb.nvim contributors. Original
usage docs: [doc/UPSTREAM_README.md](doc/UPSTREAM_README.md). The Lua module keeps the name `ipynb` to stay
close to upstream.

Also used:
- [tree-sitter-wolfram](https://github.com/WolframResearch/tree-sitter-wolfram) (MIT, Wolfram Research / Brenton Bostick), vendored in `tree-sitter-wolfram/`; highlight queries from [zed-wolfram-highlighter](https://github.com/WolframResearch/zed-wolfram-highlighter) (MIT).
- [snacks.nvim](https://github.com/folke/snacks.nvim) for inline images, [nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter) and [nvim-lspconfig](https://github.com/neovim/nvim-lspconfig).
- Wolfram Language and WolframKernel are products of Wolfram Research; this project is not affiliated with or endorsed by Wolfram Research.

Licensed under the Apache License 2.0 (see [LICENSE](LICENSE)). Files changed from upstream are marked by the git history of this repository.

---

The original ipynb.nvim README (Jupyter usage, full configuration) is kept in [doc/UPSTREAM_README.md](doc/UPSTREAM_README.md).
