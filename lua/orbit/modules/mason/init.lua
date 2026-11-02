local M = {}
---@type Orbit.MasonOptions?
local accepted

---@class Orbit.MasonOptions # Lazy Mason package manager integration.
---@field enabled? boolean @default(true) @restart(true) # Enable Mason commands.
---@field path_mode? 'skip'|'prepend'|'append' @default("prepend") @restart(true) # Where Mason's bin directory goes on PATH at startup.
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

---Add Mason's bin directory to PATH once, so servers resolve before Mason loads.
---@param mode 'skip'|'prepend'|'append'
function M.add_bin_to_path(mode)
  if mode == "skip" then
    return
  end
  local bin = vim.fs.joinpath(vim.fn.stdpath("data"), "mason", "bin")
  local separator = vim.fn.has("win32") == 1 and ";" or ":"
  local path = vim.env.PATH or ""
  for entry in vim.gsplit(path, separator, { plain = true }) do
    if vim.fs.normalize(entry) == vim.fs.normalize(bin) then
      return
    end
  end
  vim.env.PATH = mode == "prepend" and (bin .. separator .. path) or (path .. separator .. bin)
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
      -- Mason loads only on its commands; Orbit owns PATH at startup instead.
      init = function()
        M.add_bin_to_path(c.path_mode)
      end,
      ---@type MasonSettings
      opts = {
        PATH = "skip",
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
