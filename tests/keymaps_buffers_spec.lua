-- Exercise mapped buffer deletion with real Neovim buffers and failed setups.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
local orbit = require("orbit")
local commands = require("orbit.modules.commands")
local passed = 0
local function check(name, fn)
  local ok, err = xpcall(fn, debug.traceback)
  assert(ok, "FAIL " .. name .. "\n" .. tostring(err))
  passed = passed + 1
  print("PASS " .. name)
end

local function mapping(lhs)
  return vim.fn.maparg(lhs, "n", false, true)
end

vim.keymap.set("n", " bD", "<cmd>echo 'original others'<cr>")
vim.keymap.set("n", " x", "<cmd>echo 'original close'<cr>")
vim.keymap.set("n", ",bD", "<cmd>echo 'comma others'<cr>")
vim.keymap.set("n", ",x", "<cmd>echo 'comma close'<cr>")
local original = {
  other = mapping(" bD").rhs, close = mapping(" x").rhs,
  comma_other = mapping(",bD").rhs, comma_close = mapping(",x").rhs,
}

local previous = vim.api.nvim_get_current_buf()
local saved = {}
for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
  if vim.api.nvim_buf_is_valid(buffer) then
    saved[buffer] = vim.bo[buffer].buflisted
    vim.bo[buffer].buflisted = false
  end
end

check("setup does not import buffer actions or delete buffers", function()
  local scratch = vim.api.nvim_create_buf(true, false)
  orbit.setup()
  assert(package.loaded["orbit.modules.keymaps.buffer_actions"] == nil)
  assert(vim.api.nvim_buf_is_valid(scratch))
  assert(type(mapping(" bD").callback) == "function")
  assert(type(mapping(" x").callback) == "function")
  vim.api.nvim_buf_delete(scratch, { force = true })
end)

check("bulk cleanup preserves current and excludes special or unlisted buffers", function()
  local current = vim.api.nvim_create_buf(true, false)
  local first = vim.api.nvim_create_buf(true, false)
  local second = vim.api.nvim_create_buf(true, false)
  local unlisted = vim.api.nvim_create_buf(false, true)
  local special = vim.api.nvim_create_buf(true, false)
  vim.bo[special].buftype = "nofile"
  vim.api.nvim_set_current_buf(current)
  mapping(" bD").callback()
  assert(vim.api.nvim_buf_is_valid(current))
  assert(not vim.api.nvim_buf_is_valid(first))
  assert(not vim.api.nvim_buf_is_valid(second))
  assert(vim.api.nvim_buf_is_valid(unlisted))
  assert(vim.api.nvim_buf_is_valid(special))
  vim.api.nvim_set_current_buf(previous)
  for _, b in ipairs({ current, unlisted, special }) do
    if vim.api.nvim_buf_is_valid(b) then
      vim.api.nvim_buf_delete(b, { force = true })
    end
  end
end)

check("modified candidates abort bulk deletion before any buffer is removed", function()
  local current = vim.api.nvim_create_buf(true, false)
  local first = vim.api.nvim_create_buf(true, false)
  local modified = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_lines(modified, 0, -1, false, { "unsaved" })
  vim.api.nvim_set_current_buf(current)
  local ok, err = pcall(function() mapping(" bD").callback() end)
  assert(not ok and tostring(err):find("unsaved", 1, true))
  assert(vim.api.nvim_buf_is_valid(first))
  assert(vim.api.nvim_buf_is_valid(modified))
  assert(vim.api.nvim_buf_is_valid(current))
  vim.bo[modified].modified = false
  mapping(" bD").callback()
  assert(not vim.api.nvim_buf_is_valid(modified))
  assert(not vim.api.nvim_buf_is_valid(first))
  vim.api.nvim_set_current_buf(previous)
  vim.api.nvim_buf_delete(current, { force = true })
end)

check("current close refuses unsaved content then safely deletes it", function()
  local current = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_set_current_buf(current)
  vim.api.nvim_buf_set_lines(current, 0, -1, false, { "unsaved" })
  local ok, err = pcall(function() mapping(" x").callback() end)
  assert(not ok and tostring(err):find("unsaved", 1, true))
  assert(vim.api.nvim_buf_is_valid(current))
  vim.bo[current].modified = false
  mapping(" x").callback()
  assert(not vim.api.nvim_buf_is_valid(current))
end)

check("special buffers cannot be closed through the normal-file action", function()
  local special = vim.api.nvim_create_buf(true, false)
  vim.bo[special].buftype = "nofile"
  vim.api.nvim_set_current_buf(special)
  local ok, err = pcall(function() mapping(" x").callback() end)
  assert(not ok and tostring(err):find("special", 1, true))
  assert(vim.api.nvim_buf_is_valid(special))
  vim.api.nvim_set_current_buf(previous)
  vim.api.nvim_buf_delete(special, { force = true })
end)

check("leader changes restore user keys in both physical namespaces", function()
  orbit.setup({ modules = { keymaps = { leader = "," } } })
  assert(mapping(" bD").rhs == original.other)
  assert(mapping(" x").rhs == original.close)
  assert(type(mapping(",bD").callback) == "function")
  assert(type(mapping(",x").callback) == "function")
end)

check("collision and downstream rollback leave mappings unchanged", function()
  local accepted = orbit.get_config()
  local ok, err = pcall(orbit.setup, { modules = {
    keymaps = { leader = ",", save = "<leader>x" },
  } })
  assert(not ok and tostring(err):find("duplicate leader mapping", 1, true))
  assert(vim.deep_equal(orbit.get_config(), accepted))
  local before = commands.setup
  commands.setup = function() error("injected buffer actions failure") end
  ok, err = pcall(orbit.setup, { modules = {
    keymaps = { leader = ";" },
    commands = { enabled = false },
  } })
  commands.setup = before
  assert(not ok and tostring(err):find("injected buffer actions failure", 1, true))
  assert(vim.g.mapleader == ",")
  assert(mapping(" bD").rhs == original.other)
  assert(type(mapping(",x").callback) == "function")
end)

check("disable restores all original buffer shortcut bindings", function()
  orbit.setup({ modules = { keymaps = { enabled = false } } })
  assert(mapping(" bD").rhs == original.other)
  assert(mapping(" x").rhs == original.close)
  assert(mapping(",bD").rhs == original.comma_other)
  assert(mapping(",x").rhs == original.comma_close)
end)

vim.api.nvim_set_current_buf(previous)
for buffer, listed in pairs(saved) do
  if vim.api.nvim_buf_is_valid(buffer) then vim.bo[buffer].buflisted = listed end
end
print(string.format("%d buffer action tests passed.", passed))
