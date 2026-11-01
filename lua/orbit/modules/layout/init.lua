local M = {}
local accepted

---@class Orbit.LayoutOptions # Edgy side layouts for Trouble views.
---@field enabled? boolean @default(true) @restart(true) # Include the Edgy layout spec.
---@field toggle_key? string @default("<leader>ue") @minLength(1) @restart(true) # Toggle all side layouts.
---@field select_key? string @default("<leader>uE") @minLength(1) @restart(true) # Select a side-layout window.
---@field size_percent? integer @default(30) @minimum(5) @maximum(90) @restart(true) # Side width or height as a percent of the editor.

---@return Orbit.LayoutOptions?
function M.capture()
  return accepted and vim.deepcopy(accepted) or nil
end

---@param snapshot Orbit.LayoutOptions?
function M.restore(snapshot)
  accepted = snapshot and vim.deepcopy(snapshot) or nil
end

---@param opts? Orbit.LayoutOptions
function M.setup(opts)
  accepted = require("orbit.config").resolve_module("layout", opts)
end

---@return LazySpec
function M.spec()
  if not accepted or not accepted.enabled then
    return {}
  end
  local c = vim.deepcopy(accepted)
  return {
    {
      "folke/edgy.nvim",
      event = "VeryLazy",
      keys = {
        { c.toggle_key, function() require("edgy").toggle() end, desc = "edgy toggle" },
        { c.select_key, function() require("edgy").select() end, desc = "edgy select window" },
      },
      opts = function()
        return require("orbit.modules.layout.views").build(c.size_percent / 100)
      end,
    },
  }
end

return M
