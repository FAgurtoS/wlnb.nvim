-- Wolfram symbol completion (in-process LSP server)
-- Run with: nvim --headless -u tests/minimal_init.lua -l tests/test_completion.lua

local h = require('tests.helpers')
local completion = require('ipynb.completion')

print('')
print(string.rep('=', 60))
print('Running completion tests')
print(string.rep('=', 60))
print('')

h.run_test('items_match_case_insensitively_and_carry_usage', function()
  local items = completion.items('integ')
  local labels = {}
  for _, item in ipairs(items) do
    labels[item.label] = item
  end
  h.assert_true(labels.Integrate ~= nil, 'Integrate offered for "integ"')
  h.assert_true(labels.Integrate.documentation.value:find('Integrate%[') ~= nil, 'usage attached')
  h.assert_eq(#(completion.items("S")), 0) -- needs two characters
  h.assert_true(#completion.items('Plot') > 3, 'Plot, Plot3D, PlotRange...')
end)

h.run_test('lsp_server_answers_completion_requests_for_a_cell_buffer', function()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].filetype = 'wolfram'
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'x = 1', 'y = Integ' })
  vim.api.nvim_set_current_buf(buf)
  completion.attach(buf)
  h.assert_true(vim.wait(3000, function()
    return #vim.lsp.get_clients({ bufnr = buf, name = 'wlnb-symbols' }) == 1
  end, 50), 'client attached')
  local params = {
    textDocument = vim.lsp.util.make_text_document_params(buf),
    position = { line = 1, character = 9 },
  }
  local res = vim.lsp.buf_request_sync(buf, 'textDocument/completion', params, 3000)
  local found = false
  for _, r in pairs(res or {}) do
    for _, item in ipairs(r.result and r.result.items or {}) do
      if item.label == 'Integrate' then
        found = true
      end
    end
  end
  h.assert_true(found, 'Integrate offered at "Integ|"')
end)

local success = h.summary()
if success then
  vim.cmd('qa!')
else
  vim.cmd('cquit 1')
end
