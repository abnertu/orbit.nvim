-- Windows-only recovery command for stale ShaDa temporary files.
local M = {}
local owns_command = false

---@class Orbit.SystemOptions # Platform-specific recovery commands.
---@field enabled boolean @default(true) # Enable platform recovery commands.
---@field clear_shada boolean @default(true) # Offer a Windows ShaDa temporary-file cleanup command.

local function command_exists()
  return vim.api.nvim_get_commands({}).ClearShada ~= nil
end

local function register()
  assert(not command_exists(),
    "refusing to overwrite existing user command: ClearShada")
  vim.api.nvim_create_user_command("ClearShada", function()
    local count, err = require("orbit.modules.system.shada").clear()
    if count then
      vim.notify(string.format("Removed %d stale ShaDa temporary files", count),
        vim.log.levels.INFO, { title = "orbit.nvim system" })
    else
      vim.notify("ShaDa cleanup failed: " .. tostring(err),
        vim.log.levels.WARN, { title = "orbit.nvim system" })
    end
  end, { desc = "Remove stale ShaDa temporary files without touching main.shada" })
  owns_command = true
end

---@return table
function M.capture()
  return { owns_command = owns_command }
end

---@param snapshot table
function M.restore(snapshot)
  if owns_command then
    pcall(vim.api.nvim_del_user_command, "ClearShada")
    owns_command = false
  end
  if snapshot.owns_command then register() end
end

---@param opts? Orbit.SystemOptions
function M.setup(opts)
  opts = require("orbit.config").resolve_module("system", opts)
  local required = opts.enabled and opts.clear_shada and vim.fn.has("win32") == 1
  if not required and owns_command then
    vim.api.nvim_del_user_command("ClearShada")
    owns_command = false
  elseif required and not owns_command then
    register()
  end
end

return M
