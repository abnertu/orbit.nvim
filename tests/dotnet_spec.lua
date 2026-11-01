-- Verify the dotnet-cli owner declaration, settings and DAP delegation.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
local orbit = require("orbit")
local feature = require("orbit.modules.dotnet")
local passed = 0
local function check(label, fn)
  local ok, err = xpcall(fn, debug.traceback)
  assert(ok, "FAIL " .. label .. "\n" .. tostring(err))
  passed = passed + 1
  print("PASS " .. label)
end

check("default spec declares every .NET entry point without loading it", function()
  assert(#feature.spec() == 0)
  orbit.setup()
  local spec = feature.spec()[1]
  assert(spec[1] == "Orbit-Lua/dotnet-cli.nvim")
  assert(spec.dependencies[1] == "Orbit-Lua/comet.nvim")
  assert(vim.deep_equal(spec.cmd, {
    "DotnetManager", "DotnetBuild", "DotnetPublish",
    "DotnetGlobalJson", "DotnetDebug", "DotnetAttach",
  }))
  assert(spec.ft == "cs")
  assert(spec.keys[1][1] == "<leader>ud" and spec.keys[1][2] == "<cmd>DotnetManager<CR>")
  assert(package.loaded["dotnet-cli"] == nil)
end)

check("bundled spec import collects the dotnet owner", function()
  local found = false
  for _, item in ipairs(require("orbit.plugins")) do
    if item[1] == "Orbit-Lua/dotnet-cli.nvim" then found = true end
  end
  assert(found, "orbit.plugins must include dotnet-cli")
end)

check("CoreCLR registration delegates to dotnet-cli", function()
  local calls = 0
  package.loaded["dotnet-cli"] = { setup_dap = function() calls = calls + 1; return true end }
  local ok = require("orbit.modules.dap.runtime").apply_adapter({}, "coreclr", true, {})
  package.loaded["dotnet-cli"] = nil
  assert(ok and calls == 1)
end)

check("invalid manager keys are rejected and options are restart-only", function()
  local accepted = orbit.get_config()
  local ok, err = pcall(orbit.setup, { modules = { dotnet = { manager_key = "" } } })
  assert(not ok and tostring(err):find("manager_key", 1, true))
  assert(vim.deep_equal(orbit.get_config(), accepted))
  orbit.setup({ modules = { dotnet = { enabled = false } } })
  assert(#feature.spec() == 1, "enabled is restart-only")
  assert(orbit.get_pending_restart()["orbit.modules.dotnet.enabled"] == false)
end)

check("a disabled owner contributes no spec", function()
  feature.setup({ enabled = false })
  assert(#feature.spec() == 0)
end)

print(string.format("%d dotnet tests passed.", passed))
