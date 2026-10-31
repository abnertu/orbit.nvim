local M = {}
local accepted

---@class Orbit.HangarOptions # Managed development tools and persistent state.
---@field enabled boolean @default(true) @restart(true) # Include Hangar during Lazy startup.
---@field command string @default("Hangar") @minLength(1) @restart(true) # Command for the Hangar UI.
---@field key string @default("<leader>us") @minLength(1) @restart(true) # Mapping for the Hangar UI.
---@field state_file string @default("") @restart(true) # Optional state JSON path override.
---@field border 'rounded'|'single'|'double'|'solid'|'shadow'|'none' @default("rounded") @restart(true) # Hangar window border.

function M.capture()
  return accepted and vim.deepcopy(accepted) or nil
end

function M.restore(snapshot)
  accepted = snapshot and vim.deepcopy(snapshot) or nil
end

---@param opts? Orbit.HangarOptions
function M.setup(opts)
  accepted = require("orbit.config").resolve_module("hangar", opts)
end

---@return table[]
function M.spec()
  if not accepted or not accepted.enabled then
    return {}
  end
  local opts = vim.deepcopy(accepted)
  return {
    { "MunifTanjim/nui.nvim", lazy = true },
    {
      "Orbit-Lua/hangar.nvim",
      version = "^0.3",
      lazy = false,
      priority = 900,
      dependencies = { "MunifTanjim/nui.nvim" },
      config = function()
        require("orbit.modules.hangar.runtime").setup(opts)
      end,
    },
  }
end

return M
