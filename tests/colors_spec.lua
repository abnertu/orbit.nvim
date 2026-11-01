-- Verify color previews for hex codes, LSP style ownership and rollback.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
local orbit = require("orbit")
local commands = require("orbit.modules.commands")
local runtime = require("orbit.modules.colors.runtime")
local passed = 0
local function check(label, fn)
  local ok, err = xpcall(fn, debug.traceback)
  assert(ok, "FAIL " .. label .. "\n" .. tostring(err))
  passed = passed + 1
  print("PASS " .. label)
end

local function swatches(buffer)
  local result = {}
  for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buffer, runtime.namespace, 0, -1,
    { details = true })) do
    local chunk = mark[4].virt_text[1]
    result[#result + 1] = { row = mark[2], col = mark[3], hl = chunk[2], text = chunk[1] }
  end
  return result
end

local function settle()
  vim.wait(200, function() return false end)
end

check("only standalone 3, 6 and 8 digit codes match", function()
  local found = runtime.matches("a #fff b #12ab9C c #11223344 d #12345 x#ffffff #abcdefg")
  assert(#found == 3, vim.inspect(found))
  assert(found[1].hex == "ffffff" and found[1].col == 2)
  assert(found[2].hex == "12ab9C" and found[3].hex == "112233")
end)

check("setup draws one swatch per visible code with its color", function()
  orbit.setup()
  local buffer = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_set_current_buf(buffer)
  vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { "border = #ff0000", "plain", "fill: #0f0;" })
  vim.api.nvim_exec_autocmds("TextChanged", { buffer = buffer })
  settle()
  local marks = swatches(buffer)
  assert(#marks == 2, vim.inspect(marks))
  assert(marks[1].row == 0 and marks[1].col == 9 and marks[1].text == "󱓻 ")
  assert(vim.api.nvim_get_hl(0, { name = marks[1].hl }).fg == 0xff0000)
  assert(vim.api.nvim_get_hl(0, { name = marks[2].hl }).fg == 0x00ff00)
  vim.api.nvim_exec_autocmds("TextChanged", { buffer = buffer })
  settle()
  assert(#swatches(buffer) == 2, "refresh must not stack swatches")
end)

check("edits refresh swatches and special buffers stay untouched", function()
  local buffer = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(buffer, 1, 2, false, { "now #0000ff" })
  vim.api.nvim_exec_autocmds("TextChanged", { buffer = buffer })
  settle()
  assert(#swatches(buffer) == 3)
  local scratch = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(scratch, 0, -1, false, { "#ffffff" })
  vim.api.nvim_set_current_buf(scratch)
  settle()
  assert(#swatches(scratch) == 0, "nofile buffers must not get swatches")
  vim.api.nvim_set_current_buf(buffer)
end)

check("colorscheme changes recreate swatch highlights", function()
  local buffer = vim.api.nvim_get_current_buf()
  vim.cmd.colorscheme("habamax")
  settle()
  local mark = swatches(buffer)[1]
  assert(vim.api.nvim_get_hl(0, { name = mark.hl }).fg == 0xff0000)
end)

check("LSP colors follow the lsp option", function()
  assert(vim.lsp.document_color.is_enabled())
  orbit.setup({ modules = { colors = { lsp = false } } })
  assert(not vim.lsp.document_color.is_enabled())
  orbit.setup()
  assert(vim.lsp.document_color.is_enabled())
end)

check("later module failure restores previews and LSP state", function()
  local buffer = vim.api.nvim_get_current_buf()
  local prior = commands.setup
  commands.setup = function() error("injected colors rollback") end
  local ok = pcall(orbit.setup, { modules = { colors = { enabled = false },
    commands = { name = "OrbitColorsFail" } } })
  commands.setup = prior
  assert(not ok)
  settle()
  assert(#swatches(buffer) == 3, "rollback must redraw swatches")
  assert(vim.lsp.document_color.is_enabled())
end)

check("disabling removes swatches and observers", function()
  local buffer = vim.api.nvim_get_current_buf()
  orbit.setup({ modules = { colors = { enabled = false } } })
  assert(#swatches(buffer) == 0)
  assert(not pcall(vim.api.nvim_get_autocmds, { group = "OrbitColors" }))
  assert(vim.lsp.document_color.is_enabled(), "disabling must restore the prior LSP state")
  vim.lsp.document_color.enable(false)
  orbit.setup({ modules = { colors = { enabled = true, lsp = true } } })
  assert(vim.lsp.document_color.is_enabled())
  orbit.setup({ modules = { colors = { enabled = false } } })
  assert(not vim.lsp.document_color.is_enabled(), "a user-disabled LSP state must return")
end)

print(string.format("%d color preview tests passed.", passed))
