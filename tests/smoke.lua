-- Run with: nvim --headless -u NONE --cmd 'set rtp^=.' -l tests/smoke.lua
-- Verify the actual configuration entry point before targeted setup calls.
dofile("init.lua")

local orbit = require("orbit")

orbit.setup({ modules = { editor = { shiftwidth = 4 } } })
assert(vim.o.shiftwidth == 4, "editor options did not apply to the current buffer")
assert(vim.api.nvim_get_option_value("shiftwidth", { scope = "global" }) == 4, "editor default did not update")
local next_buffer = vim.api.nvim_create_buf(true, false)
vim.api.nvim_set_current_buf(next_buffer)
assert(vim.bo[next_buffer].shiftwidth == 4, "new buffers did not inherit editor defaults")
vim.api.nvim_buf_delete(next_buffer, { force = true })
assert(orbit.get_config().modules.editor.shiftwidth == 4)
assert(orbit.get_config().modules.keymaps.enabled == true)

local ok = pcall(function()
  orbit.setup({ modules = { editor = { shiftwidth = 99 } } })
end)
assert(not ok, "invalid configuration must fail")
assert(vim.o.shiftwidth == 4, "invalid configuration changed editor options")
assert(orbit.get_config().modules.editor.shiftwidth == 4, "failed setup replaced accepted config")

local direct = require("orbit.modules.editor")
direct.setup({ number = false })
assert(vim.o.number == false, "direct module setup did not apply defaults")

-- Disabling a module removes its mapping without erasing editor configuration.
orbit.setup({ modules = { keymaps = { enabled = false } } })
assert(orbit.get_config().modules.keymaps.enabled == false)
assert(vim.fn.maparg("<leader>w", "n") == "", "disabled module left its mapping")

print("orbit.nvim smoke test passed")
