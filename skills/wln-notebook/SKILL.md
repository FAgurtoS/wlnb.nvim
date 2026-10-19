---
name: wln-notebook
description: Edit and run a Wolfram Language notebook (.wlnb) that is open in Neovim with wln.nvim, or edit a .wlnb file directly. Use when the user mentions a .wlnb notebook, wln.nvim, or asks to add, change, run or read cells of a Wolfram notebook open in nvim.
---

# wln notebooks (.wlnb)

A `.wlnb` file is plain text and a valid `.wl` file. Cells are separated by marker comments:

```
(* ::wlnb:: v0 *)

(* ::cell:: input *)
Integrate[Sin[x]^2, x]

(* ::cell:: output *)
(* x/2 - Sin[2 x]/4 *)

(* ::cell:: markdown *)
(* Some **text** *)
```

- `input` is Wolfram code. An `output` belongs to the input right above it and is InputForm text in one comment.
- `markdown` and `raw` bodies are wrapped in one comment (`(*` is written `(\*`, `*)` is written `*\)`).
- Plot outputs are `(* -Graphics- <hash> *)`; the PNG lives in `<notebook>.assets/<hash>.png`. Never edit these by hand.
- Full spec: `FORMAT.md` in the wln.nvim repository (`~/wln.nvim`).

## Two ways to work

**1. Notebook is NOT open in Neovim:** edit the file directly. Keep the layout canonical (blank line between cells, one newline at the end). Do not write outputs yourself: they are produced by running the cells.

**2. Notebook IS open in Neovim (use this when the user is looking at it):** do NOT edit the file on disk, because Neovim holds the cells in memory and would overwrite your change on `:w`. Use the control script instead (Neovim finds itself; no setup):

```sh
~/wln.nvim/scripts/wln-agent list   notebook.wlnb          # cells: index, type, first line, outputs, state
~/wln.nvim/scripts/wln-agent get    notebook.wlnb 3        # source + output texts of cell 3
echo 'x = 5; x^2' | ~/wln.nvim/scripts/wln-agent set notebook.wlnb 3
echo '# Title'   | ~/wln.nvim/scripts/wln-agent insert notebook.wlnb 2 markdown   # after cell 2 (0 = top)
~/wln.nvim/scripts/wln-agent delete notebook.wlnb 4
~/wln.nvim/scripts/wln-agent run    notebook.wlnb 3 --wait  # start kernel if needed, run, wait for the result
~/wln.nvim/scripts/wln-agent save   notebook.wlnb           # writes the .wlnb (and PNGs)
```

Every command prints JSON with `"ok": true|false`. Cell indexes are 1-based and shift after insert/delete, so run `list` again after structural changes.

Rules:
- Read (`get`) a cell before changing it. Change only what was asked.
- `run` prints the output texts as InputForm. Error and `Message` text is in the same list.
- Do not delete cells or outputs unless asked. Do not call `save` unless the user wants it on disk (they may prefer `:w` themselves).
- If the error says a cell is being edited, tell the user to press `Esc` in Neovim and retry.
- If it says the license limit was reached (the free Wolfram Engine allows 2 kernels; WLJS kernels count), ask the user to stop a kernel (`:NotebookKernels` in Neovim, or in WLJS); do not kill processes yourself.
- If no running Neovim has the notebook, the script says so: fall back to way 1 or ask the user to open it.
- Avoid `Print` in cells you write (its text is merged into the output); prefer returning values.

## Converting

`~/wln.nvim/scripts/wln-convert notebook.wln` (WLJS to .wlnb) and `... notebook.wlnb out.wln` (back).
