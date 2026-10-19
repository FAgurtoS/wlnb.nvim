local dest, err = require('ipynb.wln').convert(arg[1], arg[2])
if not dest then
  io.stderr:write('wln-convert: ' .. tostring(err) .. '\n')
  os.exit(1)
end
print('Wrote ' .. dest)
