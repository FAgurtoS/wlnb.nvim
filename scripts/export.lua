local src, dest = arg[1], arg[2]
local cells = require('ipynb.wlnb').read(src)
dest = dest or (src:gsub('%.wlnb$', '.pdf'))
local out, err = require('ipynb.export').export(cells, dest, vim.fn.fnamemodify(src, ':t:r'))
if not out then
  io.stderr:write('wlnb-export: ' .. tostring(err) .. '\n')
  os.exit(1)
end
print('Wrote ' .. out)
