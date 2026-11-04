-- Development tools that Lazy installs but no editor feature loads.
local M = {}
---@type Orbit.DevOptions?
local accepted

---@class Orbit.DevOptions # Development tools for Orbit's own test runner.
---@field enabled? boolean @default(true) @restart(true) # Install telemetry.nvim, which `scripts/test.lua` uses to report suites.

---@return Orbit.DevOptions?
function M.capture()
  return accepted and vim.deepcopy(accepted) or nil
end

---@param snapshot Orbit.DevOptions?
function M.restore(snapshot)
  accepted = snapshot and vim.deepcopy(snapshot) or nil
end

---@param opts? Orbit.DevOptions
function M.setup(opts)
  accepted = require("orbit.config").resolve_module("dev", opts)
end

---Declare telemetry.nvim on its default branch. The editor never loads it;
---`scripts/test.lua` finds the Lazy checkout under `stdpath("data")`.
---@return LazySpec
function M.spec()
  if not accepted or not accepted.enabled then
    return {}
  end
  return {
    { "Orbit-Lua/telemetry.nvim", lazy = true },
  }
end

return M
