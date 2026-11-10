-- Verify the telemetry.lua declaration and its restart-only enablement.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
local orbit = require("orbit")
local dev = require("orbit.modules.dev")
local passed = 0

local function check(label, fn)
  local ok, err = xpcall(fn, debug.traceback)
  assert(ok, "FAIL " .. label .. "\n" .. tostring(err))
  passed = passed + 1
  print("PASS " .. label)
end

check("default setup declares telemetry.lua as a lazy plugin", function()
  assert(#dev.spec() == 0)
  orbit.setup()
  local specs = dev.spec()
  assert(#specs == 1 and specs[1][1] == "Orbit-Lua/telemetry.lua")
  assert(specs[1].lazy == true and specs[1].version == "^0.1")
  assert(package.loaded.telemetry == nil)
end)

check("bundled spec import collects telemetry.lua once", function()
  local found = 0
  for _, item in ipairs(require("orbit.plugins")) do
    if item[1] == "Orbit-Lua/telemetry.lua" then
      found = found + 1
    end
  end
  assert(found == 1)
end)

check("enablement is restart-only and a disabled module returns no spec", function()
  orbit.setup({ modules = { dev = { enabled = false } } })
  assert(orbit.get_config().modules.dev.enabled == true)
  assert(orbit.get_pending_restart()["orbit.modules.dev.enabled"] == false)
  local before = dev.capture()
  dev.setup({ enabled = false })
  assert(#dev.spec() == 0)
  dev.restore(before)
  assert(#dev.spec() == 1)
end)

print(string.format("%d dev module tests passed.", passed))
