local M = {}
local accepted

---@class Orbit.IconsOptions # Optional mini.icons integration.
---@field enabled boolean @default(true) @restart(true) # Include mini.icons in the Lazy specification.
---@field mock_devicons boolean @default(true) @restart(true) # Provide an nvim-web-devicons compatibility adapter.

---Capture settings without loading or installing plugins.
---@return Orbit.IconsOptions?
function M.capture()
  return accepted and vim.deepcopy(accepted) or nil
end

---@param snapshot Orbit.IconsOptions?
function M.restore(snapshot)
  accepted = snapshot and vim.deepcopy(snapshot) or nil
end

---@param opts? Orbit.IconsOptions
function M.setup(opts)
  accepted = require("orbit.config").resolve_module("icons", opts)
end

---Return a Lazy spec without requiring external plugin code.
---@return LazySpec
function M.spec()
  if not accepted or not accepted.enabled then
    return {}
  end

  local options = vim.deepcopy(accepted)
  return {
    {
      "nvim-mini/mini.icons",
      lazy = false,
      config = function()
        local mini = require("mini.icons")
        mini.setup({})
        if options.mock_devicons then
          mini.mock_nvim_web_devicons()
        end
      end,
    },
  }
end

return M
