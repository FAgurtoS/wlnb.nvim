---
name: wlnb
description: Edit and run a Wolfram Language notebook (.wlnb) that is open in Neovim with wlnb.nvim, or edit a .wlnb file directly. Use when the user mentions a .wlnb notebook, wlnb.nvim, or asks to add, change, run or read cells of a Wolfram notebook open in nvim.
---

# wln notebooks (.wlnb)

A `.wlnb` file is plain text and a valid `.wl` file. Cells are separated by marker comments:

```
(* ::wlnb:: v1 *)

(* ::cell:: input *)
Integrate[Sin[x]^2, x]

(* ::cell:: output *)
(* x/2 - Sin[2 x]/4 *)

(* ::cell:: markdown *)
(* Some **text** *)
```

- `input` is Wolfram code. An `output` belongs to the input right above it and is InputForm text in one comment.
- `markdown` and `raw` bodies are wrapped in one comment (`(*` is written `(\*`, `*)` is written `*\)`).
- Images are not in the notebook: they live in a sidecar `<name>.wlnbi` next to it (base64 PNG, long lines; never read or edit it). Outputs refer to them as `(* -Graphics- <hash> *)` or a last `-Rendered- <hash>` line. If the notebook was saved in embedded mode, the images are in a section starting at `(* ::assets:: *)` at the end: skip it. Always move or copy a notebook together with its `.wlnbi` (`:NotebookCopy` inside Neovim does both).
- Full spec: `FORMAT.md` in the wlnb.nvim repository (`~/wlnb.nvim`).

## Two ways to work

**1. Notebook is NOT open in Neovim:** edit the file directly. Keep the layout canonical (blank line between cells, one newline at the end). Do not write outputs yourself: they are produced by running the cells.

**2. Notebook IS open in Neovim (use this when the user is looking at it):** do NOT edit the file on disk, because Neovim holds the cells in memory and would overwrite your change on `:w`. Use the control script instead (Neovim finds itself; no setup):

```sh
~/wlnb.nvim/scripts/wlnb-agent list   notebook.wlnb          # cells: index, type, first line, outputs, state
~/wlnb.nvim/scripts/wlnb-agent get    notebook.wlnb 3        # source + output texts of cell 3
echo 'x = 5; x^2' | ~/wlnb.nvim/scripts/wlnb-agent set notebook.wlnb 3
echo '# Title'   | ~/wlnb.nvim/scripts/wlnb-agent insert notebook.wlnb 2 markdown   # after cell 2 (0 = top)
~/wlnb.nvim/scripts/wlnb-agent delete notebook.wlnb 4
~/wlnb.nvim/scripts/wlnb-agent run    notebook.wlnb 3 --wait  # start kernel if needed, run, wait for the result
~/wlnb.nvim/scripts/wlnb-agent save   notebook.wlnb           # writes the .wlnb (and PNGs)
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

## Plain .wl and PDF

`~/wlnb.nvim/scripts/wlnb-export notebook.wlnb out.wl` writes just the code (markdown as comments, no outputs); `out.pdf` builds a PDF (needs pandoc and xelatex).

## Converting

`~/wlnb.nvim/scripts/wlnb-convert notebook.nb` (Mathematica to .wlnb), `... notebook.wlnb out.nb` (back), and the same with `.wln` for WLJS. Conversions of `.nb` and legacy `.wln` use a one-shot kernel (one license slot).
