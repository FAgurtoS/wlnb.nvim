# wln.nvim

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
git clone <this repo> ~/wln.nvim
cd ~/wln.nvim
# first run only (compiles the parser, clones test dependencies into tests/.nvim-test):
PATH=$PWD/scripts/zig-cc:$PATH nvim --headless -u tests/minimal_init.lua -l tests/run_all.lua
# open a notebook with the plugin loaded:
./scripts/wln examples/basic.wlnb
```

`scripts/wln` is a shell command (run it in a terminal, not from a file manager such as ranger,
which would open the file with your normal Neovim without the plugin). It uses
`scripts/init.lua`. Notebook shortcuts start with a comma (`,`) and only exist inside `.wlnb` buffers.

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

- No completion, variable inspector or LSP for Wolfram.
- Every result (numbers, expressions, lists, matrices...) is shown as a rendered StandardForm image; `,y` / `:NotebookYankOutput` still copy the InputForm text. Without image support the InputForm text is shown instead. Set `WLN_RENDER_MATH=0` to turn rendering off.
- Plot images are saved on `:w` to `<notebook>.assets/<hash>.png` and the file holds only `(* -Graphics- <hash> *)`. Copy the `.assets` folder together with the notebook. If the code above a plot changed since it ran, the output shows `[stale]`. `:NotebookCleanAssets` deletes PNGs no marker references (run it after saving).

---

# Upstream README (ipynb.nvim)

## 📘 `ipynb.nvim`

A modal Jupyter notebook editor for Neovim.

> [!IMPORTANT]
> `ipynb.nvim` is currently in **alpha**. There *will* be bugs!

<img width="752" height="517" alt="Screenshot From 2026-01-17 01-28-38" src="https://github.com/user-attachments/assets/6784bcce-ab98-4f5a-9383-567e252276bc" />

## ✨ Features

- Edit `.ipynb` files as actual notebooks with isolated cell buffers
- Cell outputs render inline as virtual lines (open in float to copy)
- Inline image rendering (PNG, JPEG, SVG, etc.)
- Variable inspector with auto-hover (uses Jupyter inspect protocol)
- Partial language server support (diagnostics, completion, go to definition, rename)
- Multi-language support (Python, Julia, R, and more)
- Treesitter highlighting with dynamic language injection

## 🧩 How It Works

The plugin uses a modal editing approach:

- **Notebook mode**: for navigating and managing cells
- **Cell mode**: for editing cell content in an isolated buffer

Under the hood, the notebook is rendered into a single buffer for display. Entering Cell mode opens an isolated buffer for just the active cell, and edits sync back to the notebook buffer. In parallel, all code cells are mirrored into a shared “shadow” buffer that LSP requests are proxied through. This design aims to preserve the feel of Jupyter notebooks.

## ⚡️ Requirements

- Neovim 0.10+
- [nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter)
- Python 3.x with `jupyter_client` (for kernel execution)

***Optional (but highly recommended):***

- [nvim-lspconfig](https://github.com/neovim/nvim-lspconfig) for LSP support (completion, diagnostics, etc.)
- [nvim-web-devicons](https://github.com/nvim-tree/nvim-web-devicons) for language icons in cell borders
- [snacks.nvim](https://github.com/folke/snacks.nvim) for inline image rendering
  - a terminal that fully supports the kitty graphics protocol (e.g., kitty, Ghostty)
  - ImageMagick required to display non-PNG image formats

Run `:checkhealth ipynb` to verify your setup.

## 📦 Installation

### lazy.nvim

```lua
{
  "ajbucci/ipynb.nvim",
  dependencies = {
    "nvim-treesitter/nvim-treesitter",
    "neovim/nvim-lspconfig",
    -- "nvim-tree/nvim-web-devicons", -- optional, for language icons
    -- "folke/snacks.nvim", -- optional, for inline images
  },
  opts = {},
}
```

The treesitter parser is automatically compiled on first load.

### Manual

1. Add the plugin to your runtime path
2. Call `require("ipynb").setup()` (parser auto-compiles on first load)

## 🚀 Usage

### 1. Open a notebook

  ```sh
  nvim notebook.ipynb
  ```

  ```vim
  " or from in neovim:
  :e notebook.ipynb
  " or
  :NotebookCreate notebook.ipynb 
  ```

### 2. Edit a cell

- Place your cursor anywhere on a cell (you can quickly navigate using `]]` (next) and `[[` (previous), though any vim motions will work)
- Press `i` (Insert) or `<CR>` (Normal) to enter Cell mode for the current cell
- Press `<Esc>` to exit Cell mode and return to Notebook mode

### 3. Start a kernel

- Start a Jupyter kernel with `:NotebookKernelStart` (default keymap: `,s`)

### 4. Execute a cell

- Execute a cell with `:NotebookExecuteCell` (default keymap: `,x`)

### 5. View outputs

- Outputs render inline as virtual lines below the cell
- Use `:NotebookOutput` (default keymap: `,o`) to open the output in a floating window for easy copying

### 6. Inspect variables

- Place your cursor on a variable and inspect it using `:NotebookInspect` (default keymap: `,h`)
- Inspect all variables in cell using `:NotebookInspectCell` (default keymap: `,v`)

## 📝 Persistent Markdown Rendering

Markdown cells receive Tree-sitter highlighting out of the box. To render
headings, links, lists, tables, and LaTeX persistently in Notebook mode, use a
Markdown renderer that supports injected Tree-sitter languages and configure it
to attach to the `ipynb` filetype.

For [render-markdown.nvim](https://github.com/MeanderingProgrammer/render-markdown.nvim)
with lazy.nvim:

```lua
{
  "MeanderingProgrammer/render-markdown.nvim",
  ft = { "markdown", "ipynb" },
  opts = {
    overrides = {
      filetype = {
        ipynb = {
          -- Optional: keep the cursor line rendered in the notebook facade.
          anti_conceal = { enabled = false },
        },
      },
    },
  },
}
```

If your plugin manager does not provide filetype configuration to
render-markdown.nvim, set its attachment list explicitly:

```lua
require("render-markdown").setup({
  file_types = { "markdown", "ipynb" },
})
```

If a distribution already configures render-markdown.nvim, extend its existing
plugin specification instead of calling `setup()` a second time. LaTeX
rendering also requires render-markdown.nvim's optional LaTeX dependencies.

For [markview.nvim](https://github.com/OXY2DEV/markview.nvim), add `ipynb` to
`preview.filetypes` while retaining its defaults.

The notebook buffer must remain `filetype=ipynb`. Changing it to `markdown` or
`ipynb.markdown` disables the parser that identifies cell boundaries and
provides the Markdown injections.

## 🐍 Python Environment *(for Jupyter kernels)*

When starting a kernel, the plugin looks for Python in this order:

1. **Path argument** passed to `:NotebookKernelStart`
2. **`kernel.python_path`** in config
3. **Virtual environment** found by walking up from the notebook's directory, checking for `.venv`, `venv`, `.virtualenv`, or `env`
4. **System Python** (`python3` or `python` in PATH)

```vim
" Use a specific Python for this session
:NotebookKernelStart /path/to/venv/bin/python

" Or configure a default in setup
```

```lua
require("ipynb").setup({
  kernel = {
    python_path = "/path/to/your/venv/bin/python",
  },
})
```

## 🗂️ Multi-Language Support

> [!WARNING]
> `R.nvim` is unsupported! Please disable it when using this plugin.

The plugin reads the language from notebook metadata and automatically configures:

- **Syntax highlighting** via tree-sitter language injection
- **LSP** by setting the shadow buffer's filetype (triggers your LSP config)
- **Kernel execution** via `jupyter_client` (supports any installed Jupyter kernel)
- **Blocking `input()` support** via floating prompt UI (`getpass` uses secure masked fallback)

The default language when creating a new notebook is Python. You can specify a kernel when creating:

```vim
:NotebookCreate mynotebook julia-1.10
:NotebookCreate analysis ir          " R kernel
```

Or change an existing notebook's kernel with `:NotebookSetKernel`:

```vim
:NotebookSetKernel julia-1.12
:NotebookSetKernel ir           " R kernel
:NotebookSetKernel python3
```

This updates the notebook metadata and re-attaches the appropriate LSP.

**Requirements per language:**

- Install the Jupyter kernel (e.g., `IJulia` for Julia, `IRkernel` for R)
- Install an LSP server (e.g., `julials`, `r_language_server`)
- Configure the LSP in your Neovim setup

## ⚙️ Configuration

`ipynb.nvim` is highly configurable. Expand to see the default configuration below.

<details><summary>Default Options</summary>

<!-- config:start -->
```lua
require("ipynb").setup({
  keymaps = {
    -- Navigation (Notebook mode)
    next_cell = "]]",              -- jump to next cell
    prev_cell = "[[",              -- jump to previous cell
    -- Navigation (both Notebook mode and Cell mode)
    jump_to_cell = ",j",   -- open cell picker
    -- Cell operations (Notebook mode)
    cut_cell = "dd",               -- cut cell to register
    paste_cell_below = "p",        -- paste cell below
    paste_cell_above = "P",        -- paste cell above
    move_cell_down = "<M-j>",      -- move cell down
    move_cell_up = "<M-k>",        -- move cell up
    -- Cell operations (both Notebook mode and Cell mode)
    add_cell_above = ",a", -- insert cell above
    add_cell_below = ",b", -- insert cell below
    make_markdown = ",m",  -- convert to markdown cell
    make_code = ",c",      -- convert to code cell
    make_raw = ",w",       -- convert to raw cell
    fold_toggle = ",f",    -- toggle cell fold
    -- Execution (both Notebook mode and Cell mode)
    execute_cell = "<C-CR>",            -- execute cell, stay
    execute_and_next = "<S-CR>",        -- execute cell, move to next
    execute_and_insert = "<M-CR>",      -- execute cell, insert new below
    execute_all_below = nil,            -- execute current and all below (unmapped)
    menu_execute_cell = ",x",   -- execute cell (menu, if <C-CR> conflicts)
    menu_execute_and_next = ",X", -- execute and next (menu, if <S-CR> conflicts)
    -- Output (both Notebook mode and Cell mode)
    open_output = ",o",      -- open cell output in float (for copying)
    clear_output = ",d",     -- clear current cell output
    clear_all_outputs = ",D", -- clear all outputs
    -- Kernel (both Notebook mode and Cell mode)
    interrupt_kernel = "<C-c>",      -- interrupt execution
    kernel_interrupt = ",i", -- interrupt (menu)
    kernel_restart = ",r",   -- restart kernel
    kernel_start = ",s",     -- start kernel
    kernel_shutdown = ",q",  -- shutdown kernel
    kernel_info = ",n",      -- show kernel info
    -- Inspector (both Notebook mode and Cell mode)
    variable_inspect = ",h", -- inspect variable at cursor
    cell_variables = ",v",   -- show all variables in cell
    toggle_auto_hover = ",H", -- toggle auto-hover on CursorHold
    -- Note: i, a, I, A, o, O, <CR> enter Cell mode; <Esc> exits Cell mode
    -- Note: u, <C-r> perform global undo/redo across cells in both Notebook mode and Cell mode
    -- Note: <C-j>/<C-k> navigate cells while in Cell mode
    -- Note: LSP commands (go to definition, references, hover, etc.) are proxied
  },
  -- Highlight groups for various notebook elements
  highlights = {
    -- For notebook
    border = "Comment",           -- Cell border
    border_hover = "Special",     -- Cell border when cursor on cell
    border_active = "Number",     -- Cell border when in Cell mode
    exec_count = "Number",        -- Execution count [N]
    output = "Comment",           -- Output text
    hint = "Comment",             -- Cell action keymap hints
    -- For statusline
    output_error = "DiagnosticError",
    executing = "DiagnosticWarn", -- Executing indicator
    queued = "DiagnosticHint",    -- Queued indicator
  },
  -- Cell border action keymap hints
  border_hints = {
    enabled = true,        -- Show action hints on active cell border
    show_on_hover = true,  -- Show hints in Notebook mode
    show_on_edit = true,   -- Show hints in Cell mode
  },
  kernel = {
    auto_connect = false,  -- Auto-connect to kernel on notebook open
    show_status = true,    -- Show kernel status in statusline
    python_path = nil,     -- Custom Python path (otherwise auto-discovered)
  },
  images = {
    enabled = true,
    cache_dir = vim.fn.stdpath("cache") .. "/ipynb.nvim",
    max_width = nil,   -- nil = window width minus sign/number columns
    max_height = nil,  -- nil = window height minus scrolloff minus 1
  },
  inspector = {
    -- Keymaps while in cell variable inspector float window
    close = { "q", "<Esc>" },   -- Keys to close inspector window
    inspect = { "K", "<CR>" },  -- Keys to inspect variable under cursor
    -- Auto-hover inspect configuration
    auto_hover = {
      enabled = false,  -- Auto-show variable hover on CursorHold
      delay = 500,     -- Milliseconds before showing hover
    },
  },
  -- Cell folding configuration
  folding = {
    hide_output = false,  -- Hide output when folded (includes cell end marker in fold)
  },
  -- LSP formatting configuration -- vim.lsp.buf.format() integration
  format = {
    enabled = true,  -- Wrap vim.lsp.buf.format() to work with notebooks
    -- Each cell is formatted as an individual document
    -- with some formatters adding trailing blank lines.
    -- This option control how many blank lines to keep:
    trailing_blank_lines = 0,  -- # trailing blank lines to keep per cell when formatted
  },
  -- Shadow buffer location (use "workspace" if LSP needs project/module layout)
  shadow = {
    location = "temp",   -- "temp" (default) or "workspace"
    dir = ".ipynb.nvim", -- subdir used when location = "workspace" (opt-in)
  },
})
```
<!-- config:end -->

</details>

## ⌨️ Commands

| Command | Description | Config | Default Keymap |
|---------|-------------|--------|---------|
| `:NotebookCreate [path] [kernel]` | Create new notebook | | |
| `:NotebookSave` | Save notebook | | |
| `:NotebookInfo` | Show notebook and cell info | | |
| `:NotebookJumpToCell` | Open cell picker | `jump_to_cell` | `,j` |
| `:NotebookInsertCellBelow` | Insert cell below | `add_cell_below` | `,b` |
| `:NotebookInsertCellAbove` | Insert cell above | `add_cell_above` | `,a` |
| `:NotebookDeleteCell` | Delete current cell | | |
| `:NotebookCutCell` | Cut cell to register | `cut_cell` | `dd` |
| `:NotebookPasteCellBelow` | Paste cell below | `paste_cell_below` | `p` |
| `:NotebookPasteCellAbove` | Paste cell above | `paste_cell_above` | `P` |
| `:NotebookMoveCellUp` | Move cell up | `move_cell_up` | `<M-k>` |
| `:NotebookMoveCellDown` | Move cell down | `move_cell_down` | `<M-j>` |
| `:NotebookToggleCellType` | Toggle code/markdown | | |
| `:NotebookMakeMarkdown` | Convert to markdown | `make_markdown` | `,m` |
| `:NotebookMakeCode` | Convert to code | `make_code` | `,c` |
| `:NotebookMakeRaw` | Convert to raw | `make_raw` | `,w` |
| `:NotebookExecuteCell` | Execute cell, stay | `execute_cell` | `<C-CR>` |
| `:NotebookExecuteAndNext` | Execute cell, move next | `execute_and_next` | `<S-CR>` |
| `:NotebookExecuteAllBelow` | Execute current and below | `execute_all_below` | (unmapped) |
| `:NotebookExecuteAll` | Execute all code cells | | |
| `:NotebookOutput` | Open output in float | `open_output` | `,o` |
| `:NotebookClearOutput` | Clear cell output | `clear_output` | `,d` |
| `:NotebookClearAllOutputs` | Clear all outputs | `clear_all_outputs` | `,D` |
| `:NotebookFoldCell` | Toggle cell fold | `fold_toggle` | `,f` |
| `:NotebookFoldAll` | Fold all cells | | |
| `:NotebookUnfoldAll` | Unfold all cells | | |
| `:NotebookFormatCell` | Format cell via LSP | | |
| `:NotebookFormatAll` | Format all code cells | | |
| `:NotebookKernelStart [path]` | Start kernel | `kernel_start` | `,s` |
| `:NotebookKernelConnect <file>` | Connect to kernel | | |
| `:NotebookSetKernel <name>` | Set kernelspec | | |
| `:NotebookListKernels` | List available Jupyter kernels | | |
| `:NotebookKernelInterrupt` | Interrupt execution | `interrupt_kernel` | `<C-c>` |
| `:NotebookKernelRestart` | Restart kernel | `kernel_restart` | `,r` |
| `:NotebookKernelShutdown` | Shutdown kernel | `kernel_shutdown` | `,q` |
| `:NotebookKernelStatus` | Show kernel status | `kernel_info` | `,n` |
| `:NotebookInspect` | Inspect variable at cursor | `variable_inspect` | `,h` |
| `:NotebookInspectCell` | Show all cell variables | `cell_variables` | `,v` |
| `:NotebookToggleAutoHover` | Toggle auto-hover | `toggle_auto_hover` | `,H` |

Note: `vim.lsp.buf.format()` is wrapped to work with notebooks automatically.
Disable with `format.enabled = false`.

## 🚥 Statusline

The plugin provides a statusline component showing kernel status. Add it to your statusline (e.g., lualine):

```lua
-- lualine example
require("lualine").setup({
  sections = {
    lualine_x = {
      {
        require("ipynb.kernel").statusline,
        cond = require("ipynb.kernel").statusline_visible,
        color = require("ipynb.kernel").statusline_color,
      },
    },
  },
})
```

Shows language icon (from nvim-web-devicons) + status with theme-aware colors:

- `IDLE` (green, from `DiagnosticOk`)
- `BUSY` (yellow, from `DiagnosticWarn`)
- `DISC` (red, from `DiagnosticError`)

Disable with `kernel.show_status = false` in setup.

## 🩺 Troubleshooting

**Health check**

Run `:checkhealth ipynb` to verify all dependencies are properly configured.

**Parser not found**

The parser should auto-compile on first load. If it fails:

- Ensure nvim-treesitter is installed
- Run `:TSInstall! ipynb` to manually compile

**No LSP**

Ensure you have a language server installed for the notebook's language.
Check `:LspInfo` while in the notebook to see attached clients.

**Python imports unresolved in diagnostics, but code executes**

If you see diagnostics like `Import "numpy" could not be resolved` while notebook execution works:

- LSP and Jupyter kernel are separate processes and may use different Python environments
- Check kernel Python: run `import sys; print(sys.executable)` in a cell
- Configure your Python LSP (`pyright`/`basedpyright`) to use the same interpreter (for example, project `.venv`)
- For notebooks, consider `shadow.location = "workspace"` so LSP runs with project context instead of temp paths

**Kernel won't start**

Check `:NotebookKernelStatus` for the Python path being used.
Ensure `jupyter_client` is installed: `pip install jupyter_client`
For non-Python kernels, ensure the kernel is installed (e.g., IJulia, IRkernel).

**`input()` appears stuck**

The kernel is waiting for stdin. Enter text in the floating prompt and press `<CR>`.
Press `<Esc>` / `<C-c>` to cancel (the plugin interrupts the kernel).

**Images not showing**

Requires snacks.nvim and a terminal which fully supports the kitty graphics protocol (kitty, Ghostty). For tmux, set `allow-passthrough=on`.

**`[Image failed to load]` even when terminal support is true**

If `:lua print(require("snacks").image.supports_terminal())` returns `true` but images still fail:

- Run `:checkhealth snacks` (not just `:checkhealth ipynb`)
- Ensure ImageMagick tools are installed (`magick`/`convert`) for non-PNG conversion

## 🗺️ Roadmap

✅ **Working:**

- [x] Read/write .ipynb files
- [x] Cell navigation and editing
- [x] Kernel execution and output capture
- [x] Blocking stdin input prompts (`input()` / `getpass`)
- [x] Inline image rendering
- [x] Variable inspector (Jupyter inspect protocol, auto-hover)
- [x] Partial LSP support (diagnostics, completion, hover, definition, references, rename, formatting, document symbols, signature help, document highlight, inlay hints)
- [x] Multi-language support (Python, Julia, R, etc.)
- [x] Cell folding
- [x] Cell formatting via LSP (`:NotebookFormatCell`, `:NotebookFormatAll`, or `vim.lsp.buf.format()`)
- [x] Health check (`:checkhealth ipynb`)
- [x] Code lens (`textDocument/codeLens`) — server/project dependent (may require `shadow.location = "workspace"`)
- [x] Call hierarchy (`callHierarchy/*`) — requires symbols in a project/module (may require `shadow.location = "workspace"`)
- [x] Type hierarchy (`typeHierarchy/*`) — requires symbols in a project/module (may require `shadow.location = "workspace"`)
- [x] Selection range (`textDocument/selectionRange`) — requires Neovim 0.12+

🚧 **Not Tested (may or may not work):**

- Semantic tokens (`textDocument/semanticTokens`)
- Document links (`textDocument/documentLink`)

🚫 **Not Supported:**

- Code actions (`textDocument/codeAction`) - code actions can modify arbitrary ranges potentially spanning cell boundaries, making them tricky to implement in this notebook architecture
