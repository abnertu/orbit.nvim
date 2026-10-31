-- Run with: nvim --headless -u NONE -l scripts/generate_schema.lua [--check]
local script = debug.getinfo(1, "S").source:sub(2)
local root = vim.fn.fnamemodify(script, ":p:h:h")
vim.opt.rtp:prepend(root)

local generator = require("orbit.tooling.schema")
local command = arg[1]
assert(command == nil or command == "--check", "usage: generate_schema.lua [--check]")
assert(arg[2] == nil, "usage: generate_schema.lua [--check]")

if command == "--check" then
  local ok, message = generator.check(root)
  assert(ok, message)
  print("Generated schema is current.")
else
  generator.write(root)
  print("Generated settings.schema.json.")
end
