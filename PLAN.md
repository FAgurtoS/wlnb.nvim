# wln.nvim plan (fork of ajbucci/ipynb.nvim)

Goal: edit Wolfram notebooks (.wlnb) in Neovim, agent-readable, outputs in InputForm (copyable).
Rule: small steps, one check each, commit per step. Don't read edit.lua/words.lua whole; grep.
Status marks: [ ] todo, [x] done.

- [ ] 0. FORMAT.md + examples/*.wlnb (3-4 samples) agreed
- [ ] 1. Boot: plugin loads under new name; `:e x.ipynb` still works
- [ ] 2. io.lua: read_wlnb/write_wlnb + ftdetect. Check: open+save roundtrip is byte-identical
- [ ] 3. Treesitter/highlight: wolfram injection for input cells (or reuse markers via cells.lua)
- [ ] 4. Kernel: Wolfram Jupyter kernel via existing kernel_bridge.py. Check: 1+1 -> 2
- [ ] 5. Outputs as InputForm (ToString[expr, InputForm]), stored in file, float to copy
- [ ] 5b. Kernel control: interrupt, restart, shutdown (bridge must handle them; plugin already has :NotebookKernelInterrupt/Restart/Shutdown + keymaps). Restart marks all outputs [obsoleto]. Check: infinite loop is interrupted; after restart, x is undefined
- [ ] 6. Plots -> PNG via images.lua; TeXForm optional
- [ ] 7. Optional: own wolframscript bridge, LSP, .wln <-> .wlnb converter

Env: wolframscript found at /usr/local/bin; `jupyter` NOT found -> step 4 likely needs own bridge (step 7 moves up).
