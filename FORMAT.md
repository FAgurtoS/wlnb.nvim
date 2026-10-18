# .wlnb format (draft v0)

Plain text. A valid `.wl` file: every marker is a Wolfram comment.

## Rules
- A cell starts at a marker line: `(* ::cell:: <type> *)`
- Types: `input` | `output` | `markdown` | `raw`
- Cell body = all lines until the next marker (one trailing blank line trimmed).
- `input`: Wolfram code as-is.
- `output`: belongs to the preceding `input`. Whole body wrapped in ONE comment
  `(* ... *)`, content in InputForm. Any `*)` inside is escaped as `*\)`.
- `markdown`: body wrapped in ONE comment `(* ... *)`.
- Optional header on line 1: `(* ::wlnb:: v0 *)`.
- No ids, no absolute paths, no UI state.

## Decisions
- Images are NOT stored in the file. Plot outputs are written as `(* -Graphics- <hash> *)`.
- Portable: PNGs live in `<notebook>.assets/<hash>.png` next to the file and are versioned/copied with it.
- `<hash>` = hash of the cell code plus ALL previous input cells, in order (chained hash).
- On open, the marker names the PNG; it is always shown. If the cell's current chained hash differs from `<hash>`, it is shown dimmed with an `[stale]` label.
- Orphan PNGs (referenced by no marker) are removed by a cleanup command.
- Explicit exports (`Export[...]` in an input cell) are independent of this folder.
- No cell ids: order is implicit (an `output` belongs to the `input` right above it).
  May be added later as an optional `id=` attribute without breaking old files.

## Open questions
- Metadata (kernel, version): only in header.
