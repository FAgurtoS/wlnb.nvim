-- Minimal init to try the plugin interactively (used by scripts/wln)
local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')
vim.opt.rtp:prepend(root)
vim.opt.rtp:append(root .. '/tree-sitter-ipynb')
local ts = vim.fn.stdpath('data') .. '/lazy/nvim-treesitter'
if vim.fn.isdirectory(ts) == 1 then
  vim.opt.rtp:append(ts)
end
vim.o.fillchars = 'eob: '
vim.o.termguicolors = true
vim.o.swapfile = false
vim.g.mapleader = ' '
require('ipynb').setup({})
