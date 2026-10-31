-- Run with: nvim --headless -u NONE -l scripts/check_legacy_names.lua
local script = debug.getinfo(1, "S").source:sub(2)
local root = vim.fn.fnamemodify(script, ":p:h:h")
vim.opt.rtp:prepend(root)
assert(arg[1] == nil, "usage: check_legacy_names.lua")

local findings = require("orbit.tooling.legacy").scan(root)
if #findings > 0 then
  error(table.concat(findings, "\n"), 0)
end
print("No legacy source identifiers found.")
