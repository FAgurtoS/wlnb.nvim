# .wlnb format (v1)

Plain text. A valid `.wl` file: every marker is a Wolfram comment.

## Rules
- A cell starts at a marker line: `(* ::cell:: <type> *)`
- Types: `input` | `output` | `markdown` | `raw`
- Cell body = all lines until the next marker (one trailing blank line trimmed).
- `input`: Wolfram code as-is.
- `output`: belongs to the preceding `input`. Whole body wrapped in ONE comment
  `(* ... *)`, content in InputForm. Any `*)` inside is escaped as `*\)`.
- `markdown` and `raw`: body wrapped in ONE comment `(* ... *)`. Inside, `(*` is escaped as `(\*` and `*)` as `*\)`.
- Canonical layout: header, blank line, cells separated by one blank line, single newline at EOF.
- Optional header on line 1: `(* ::wlnb:: v1 *)`.
- No ids, no absolute paths, no UI state.

## Decisions
- Images live in a sidecar file next to the notebook: `plot.wlnb` + `plot.wlnbi` (same name, extension
  `.wlnbi`). The notebook never holds image data, so it stays small and readable; the two files must be
  copied together (`:NotebookCopy dest` does both). If the sidecar is missing the notebook still opens and
  plot outputs read `-Graphics- [missing image <hash>]`. The sidecar is text too:

  ```
  (* ::wlnbi:: v1 *)
  (* Images for the notebook next to this file. Keep them together: copy both. *)

  (* ::assets:: *)
  (* Embedded images (base64 PNG) for the outputs above. Safe to delete: outputs fall back to text. *)

  (* ::asset:: 34a1aa3b44c5 png *)
  (*
  iVBORw0KGgoAAAANSUhEUgAA... (76 columns)
  *)
  ```

  In the notebook, a plot output is `(* -Graphics- <hash> *)` and a rendered result is its InputForm
  text followed by a last line `-Rendered- <hash>` (hash of the PNG bytes; the text is what gets copied,
  the image is only for viewing). ?Symbol info panels are saved the same way.
- Single-file mode: with the `assets = "embedded"` setting the same `::assets::` section is appended to
  the end of the notebook instead (everything from that line on can be cut with no loss of code).
- The reader accepts all three layouts (sidecar, embedded section, v0 `<notebook>.assets/<hash>.png`);
  saving writes the configured one and removes the v0 folder.
- Plot `<hash>` = hash of the cell code plus ALL previous input cells, in order (chained hash). If the
  cell's chained hash differs from the marker, the image is shown with a `[stale]` label.
- Plain `.wl`: `:NotebookExport x.wl` (or `scripts/wlnb-export nb.wlnb x.wl`) writes the code cells as
  they are and markdown/raw cells as comments, without outputs.
- Explicit exports (`Export[...]` in an input cell) are independent of this.
- No cell ids: order is implicit (an `output` belongs to the `input` right above it).
  May be added later as an optional `id=` attribute without breaking old files.

## Open questions
- Metadata (kernel, version): only in header.
