-- Repeatable native Neovim startup profile; no external profilers or scripts.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)

local function measure(argv, label)
  local elapsed = {}
  for _ = 1, 5 do
    local start = vim.uv.hrtime()
    local result = vim.system(argv, { text = true, timeout = 30000 }):wait()
    assert(result.code == 0, label .. " failed: " ..
      tostring(result.stderr or result.stdout))
    elapsed[#elapsed + 1] = (vim.uv.hrtime() - start) / 1e6
  end
  table.sort(elapsed)
  print(string.format("%s process milliseconds: min=%.2f p50=%.2f max=%.2f",
    label, elapsed[1], elapsed[3], elapsed[5]))
  return elapsed
end

local nvim = vim.v.progpath
assert(type(nvim) == "string" and nvim ~= "", "Neovim executable not found")
local base = { nvim, "--headless", "-u", "NONE", "-c", "qa!" }
local root_literal = vim.json.encode(root)
local init_literal = vim.json.encode(root .. "/init.lua")
local with_orbit = {
  nvim, "--headless", "-u", "NONE",
  "--cmd", "lua vim.opt.rtp:prepend(" .. root_literal .. ")",
  "-c", "lua dofile(" .. init_literal .. ")",
  "-c", "lua assert(package.loaded['lazy'] == nil)",
  "-c", "qa!",
}

local clean = measure(base, "clean")
local configured = measure(with_orbit, "orbit")
-- A wide environmental ceiling avoids machine-speed-dependent benchmarks.
-- It catches a stuck or accidentally network-blocking default initialization.
assert(configured[5] < clean[3] * 50 + 5000,
  "orbit startup exceeded the generous no-network baseline ceiling")

local orbit = require("orbit")
local start = vim.uv.hrtime()
orbit.setup()
local first = (vim.uv.hrtime() - start) / 1e6
assert(package.loaded.lazy == nil, "default setup loaded Lazy")
assert(package.loaded.gitsigns == nil, "default setup loaded Gitsigns")
assert(package.loaded["mini.icons"] == nil, "default setup loaded icons")

local function group_count(event)
  return #vim.api.nvim_get_autocmds({
    group = "OrbitCoreEvents", event = event,
  })
end
local diagnostics = group_count("DiagnosticChanged")
local startup = group_count("VimEnter")
local repeats = {}
for _ = 1, 50 do
  local before = vim.uv.hrtime()
  orbit.setup()
  repeats[#repeats + 1] = (vim.uv.hrtime() - before) / 1e6
end
table.sort(repeats)
assert(group_count("DiagnosticChanged") == diagnostics)
assert(group_count("VimEnter") == startup)
assert(repeats[50] < 2000,
  "unchanged module reconfiguration exceeded 2 seconds")
assert(package.loaded.lazy == nil)
print(string.format(
  "Lua activation milliseconds: first=%.2f repeated_p50=%.2f repeated_p95=%.2f repeated_max=%.2f",
  first, repeats[25], repeats[48], repeats[50]
))
print("PASS measured process startup and idempotent Lua module activation")
