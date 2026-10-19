-- Minimal init to try the plugin interactively (used by scripts/wlnb)
local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')
vim.opt.rtp:prepend(root)
vim.opt.rtp:append(root .. '/tree-sitter-ipynb')
local ts = vim.fn.stdpath('data') .. '/lazy/nvim-treesitter'
if vim.fn.isdirectory(ts) == 1 then
  vim.opt.rtp:append(ts)
end
local snacks = vim.fn.stdpath('data') .. '/lazy/snacks.nvim'
if vim.fn.isdirectory(snacks) == 1 then
  vim.opt.rtp:append(snacks)
  require('snacks').setup({ image = { enabled = true } })
end
vim.o.fillchars = 'eob: '
vim.o.termguicolors = true
vim.o.swapfile = false
-- Status line: running kernels / license limit, coloured by this notebook's kernel
-- (green = ready, yellow = running a cell, grey = not started)
function _G.WlnKernel()
  local text, hl = require('ipynb.kernels').status()
  return ('%%#%s#%s%%*'):format(hl, text)
end
vim.o.clipboard = 'unnamedplus' -- y copies to the system clipboard too
vim.o.laststatus = 2
vim.o.statusline = '%f %m%= %{%v:lua.WlnKernel()%} '

require('ipynb').setup({})
