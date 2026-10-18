# wln.nvim plan (fork of ajbucci/ipynb.nvim)

Goal: edit Wolfram notebooks (.wlnb) in Neovim, agent-readable, outputs in InputForm (copyable).
Rule: small steps, one check each, commit per step. Don't read edit.lua/words.lua whole; grep.
Status marks: [ ] todo, [x] done.

- [ ] 0. FORMAT.md + examples/*.wlnb (3-4 samples) agreed
- [x] 1. Baseline: all upstream tests pass in the fork (Lua module stays `ipynb` for now; rename deferred). No Xcode CLT on this Mac: build the parser with `PATH=$PWD/scripts/zig-cc:$PATH` (needs `brew install zig tree-sitter-cli`)
- [x] 2. lua/ipynb/wlnb.lua (parse/serialize) wired into io.lua + BufReadCmd/BufWriteCmd for *.wlnb; tests/test_wlnb.lua. Check: open+save roundtrip is byte-identical
- [ ] 3. (postponed) Treesitter/highlight: wolfram injection for input cells (or reuse markers via cells.lua)
- [x] 4. python/wolfram_bridge.py drives WolframKernel over pipes (stdlib only, same JSON protocol as kernel_bridge.py); kernel.lua picks it when kernelspec is wolframscript. Interrupt = kill + fresh kernel (state lost; a piped kernel dies on SIGINT). Start takes ~9 s. Original note: Wolfram Jupyter kernel via existing kernel_bridge.py. Check: 1+1 -> 2
- [~] 5. (text part done: results saved as InputForm in the .wlnb; image PNG shown via execute_result image/png but not persisted yet) Outputs as InputForm (ToString[expr, InputForm]), stored in file, float to copy
- [x] 5b. Kernel control: interrupt, restart, shutdown (bridge must handle them; plugin already has :NotebookKernelInterrupt/Restart/Shutdown + keymaps). Restart marks all outputs [stale]. Check: infinite loop is interrupted; after restart, x is undefined
- [ ] 6. Plots -> PNG via images.lua; TeXForm optional
- [ ] 7. Optional: own wolframscript bridge, LSP, .wln <-> .wlnb converter

Env: wolframscript found at /usr/local/bin; `jupyter` NOT found -> step 4 likely needs own bridge (step 7 moves up).
