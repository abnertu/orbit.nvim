-- The terminal owner validates settings and restores options without discarding sessions.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
local orbit = require("orbit")
local terminal = require("orbit.modules.terminal")

orbit.setup({ modules = { terminal = { enabled = false } } })
assert(package.loaded["orbit.modules.terminal.runtime"] == nil)
assert(terminal.open("sp") == nil and terminal.toggle("sp", "owner") == false)
assert(package.loaded["orbit.modules.terminal.runtime"] == nil)

orbit.setup({ modules = { terminal = { horizontal_size = 40, startinsert = false } } })
local runtime = require("orbit.modules.terminal.runtime")
local spawned = 0
runtime.spawn = function()
  spawned = spawned + 1
  return spawned
end
runtime.start_insert = function()
  error("startinsert=false must not enter input mode")
end
runtime.is_live_terminal = function()
  return true
end
local origin = vim.api.nvim_get_current_win()
local buffer = terminal.open("sp", "owner")
assert(vim.api.nvim_win_get_height(0) == math.floor(vim.o.lines * 0.4))
assert(terminal.toggle("sp", "owner"))
assert(vim.api.nvim_get_current_win() == origin)

orbit.setup({ modules = { terminal = { enabled = false } } })
assert(not terminal.toggle("sp", "owner"))
assert(vim.api.nvim_buf_is_valid(buffer), "disabling must preserve the saved session")
orbit.setup({ modules = { terminal = { horizontal_size = 25, startinsert = false } } })
assert(terminal.toggle("sp", "owner"))
assert(vim.api.nvim_get_current_buf() == buffer and spawned == 1)
assert(vim.api.nvim_win_get_height(0) == math.floor(vim.o.lines * 0.25))

local accepted = terminal.current_options()
local commands = require("orbit.modules.commands")
local setup = commands.setup
commands.setup = function()
  error("terminal owner rollback")
end
local ok, err = pcall(orbit.setup, {
  modules = { terminal = { horizontal_size = 60 }, commands = { enabled = false } },
})
commands.setup = setup
assert(not ok and tostring(err):find("terminal owner rollback", 1, true))
assert(vim.deep_equal(terminal.current_options(), accepted))
assert(vim.api.nvim_get_current_buf() == buffer)

local path = vim.fn.tempname() .. ".json"
vim.fn.writefile({ '{"modules":{"terminal":{"enabled":false}}}' }, path)
assert(orbit.setup_from_file(path))
assert(not terminal.current_options().enabled)
vim.fn.writefile({ '{"modules":{"terminal":{"horizontal_size":101}}}' }, path)
assert(not orbit.reload_from_file(path))
assert(not terminal.current_options().enabled)
vim.fn.delete(path)
vim.api.nvim_win_close(0, true)
vim.api.nvim_buf_delete(buffer, { force = true })
print("PASS terminal settings, lazy activation, session preservation and rollback")
