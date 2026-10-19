-- Minimal init to try the plugin interactively (used by scripts/wln)
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
  local kernels = require('ipynb.kernels')
  local count, max = kernels.count(), kernels.get_max()
  local ok, _, hl_state = pcall(require('ipynb.kernel').statusline)
  local hl = ({ ready = 'DiagnosticOk', busy = 'DiagnosticWarn' })[ok and hl_state or ''] or 'Comment'
  return ('%%#%s#Kernels %s/%s%%*'):format(hl, count or '?', max or '?')
end
vim.o.laststatus = 2
vim.o.statusline = '%f %m%= %{%v:lua.WlnKernel()%} '

vim.g.mapleader = ' '
require('ipynb').setup({
  -- Easier keys for the try-it launcher: Space + one letter
  keymaps = {
    add_cell_below = '<leader>b',
    add_cell_above = '<leader>a',
    kernel_start = '<leader>s',
    menu_execute_cell = '<leader>r',
    menu_execute_and_next = '<leader>R',
    open_output = '<leader>o',
    yank_output = '<leader>y',
    output_panel = '<leader>p',
    kernel_list = '<leader>K',
    kernel_shutdown = '<leader>x',
    kernel_restart = '<leader>X',
    make_markdown = '<leader>m',
    make_code = '<leader>c',
  },
})
