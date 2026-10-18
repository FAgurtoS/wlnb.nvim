# Install everything with: brew bundle
# (macOS / Homebrew. The Python side needs nothing extra: wolfram_bridge.py uses only the stdlib.)

# Compiles the tree-sitter parser used to find cells
brew "tree-sitter-cli"
# C compiler for that parser when Xcode Command Line Tools are not installed (see scripts/zig-cc)
brew "zig"

# Terminal with the kitty graphics protocol (inline plot images) and iTerm-like Cmd+D / Cmd+T shortcuts.
# Needs `macos-option-as-alt = true` in ~/.config/ghostty/config for the Alt keymaps.
cask "ghostty"

# Optional. Only needed by snacks.nvim for non-PNG images; scripts/magick-shim covers PNG
# when the Homebrew build is broken for your macOS version.
# brew "imagemagick"

# Wolfram Engine / Mathematica (wolframscript) is not in Homebrew core: install it from Wolfram.
