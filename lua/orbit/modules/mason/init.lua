local M = {}
local accepted

---@class Orbit.MasonOptions # Lazy Mason package manager integration.
---@field enabled? boolean @default(true) @restart(true) # Enable Mason commands.
---@field path_mode? 'skip'|'prepend'|'append' @default("skip") @restart(true) # Mason PATH handling policy.
---@field max_concurrent_installers? integer @default(10) @minimum(1) @maximum(64) @restart(true) # Concurrent package installation limit.
---@field registry? string @default("github:mason-org/mason-registry") @minLength(1) @restart(true) # Primary Mason registry.
---@field pending_icon? string @default(" ") @restart(true) # Pending package icon.
---@field installed_icon? string @default(" ") @restart(true) # Installed package icon.
---@field uninstalled_icon? string @default(" ") @restart(true) # Uninstalled package icon.

---@return Orbit.MasonOptions?
function M.capture()
  return accepted and vim.deepcopy(accepted) or nil
end

---@param snapshot Orbit.MasonOptions?
function M.restore(snapshot)
  accepted = snapshot and vim.deepcopy(snapshot) or nil
end

---@param opts? Orbit.MasonOptions
function M.setup(opts)
  accepted = require("orbit.config").resolve_module("mason", opts)
end

---@return LazySpec
function M.spec()
  if not accepted or not accepted.enabled then
    return {}
  end
  local c = vim.deepcopy(accepted)
  return {
    {
      "williamboman/mason.nvim",
      cmd = { "Mason", "MasonInstall", "MasonUpdate" },
      opts = {
        PATH = c.path_mode,
        ui = {
          icons = {
            package_pending = c.pending_icon,
            package_installed = c.installed_icon,
            package_uninstalled = c.uninstalled_icon,
          },
        },
        max_concurrent_installers = c.max_concurrent_installers,
        registries = { c.registry },
      },
    },
  }
end

return M
