# .wlnb format (draft v0)

Plain text. A valid `.wl` file: every marker is a Wolfram comment.

## Rules
- A cell starts at a marker line: `(* ::cell:: <type> *)`
- Types: `input` | `output` | `markdown` | `raw`
- Cell body = all lines until the next marker (one trailing blank line trimmed).
- `input`: Wolfram code as-is.
- `output`: belongs to the preceding `input`. Whole body wrapped in ONE comment
  `(* ... *)`, content in InputForm. Any `*)` inside is escaped as `*\)`.
- `markdown`: each line prefixed with `(* ` ... ` *)`? NO: body wrapped in ONE comment.
- Optional header on line 1: `(* ::wlnb:: v0 *)`.
- No ids, no absolute paths, no UI state.

## Open questions
- Output images: sidecar file `name.assets/<n>.png` referenced by `(* ::image:: path *)`.
- Metadata (kernel, version): only in header.
