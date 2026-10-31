-- Preview the LuaDoc-derived settings schema without modifying tracked files.
-- Intended for an isolated GitHub Actions job when a branch changes LuaDoc.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
assert(arg[1] == nil, "usage: nvim -l scripts/schema_preview.lua")

local result = require("orbit.tooling.schema").generate(root)
local chunk_size = 1024
local count = math.ceil(#result / chunk_size)
print(string.format("ORBIT_SCHEMA_BEGIN:%d:%d:%s",
  count, #result, vim.fn.sha256(result)))
for index = 1, count do
  local fragment = result:sub((index - 1) * chunk_size + 1, index * chunk_size)
  print(string.format("ORBIT_SCHEMA_PART:%d:%s",
    index, vim.json.encode(fragment)))
end
print(string.format("ORBIT_SCHEMA_END:%d:%d", count, #result))
