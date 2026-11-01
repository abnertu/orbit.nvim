local M = {}
local accepted

---@class Orbit.ThemeOptions # Colorscheme, highlight overrides and saved theme selection.
---@field enabled? boolean @default(true) @restart(true) # Include the colorscheme plugin and highlight owner.
---@field colorscheme? string @default("tokyonight-night") @minLength(1) # Colorscheme applied at startup and on change.
---@field highlights? boolean @default(true) # Apply Orbit highlight overrides after each colorscheme.

---@alias Orbit.ThemeSnapshot {options?: Orbit.ThemeOptions, runtime: Orbit.ThemeRuntimeState}

---@return Orbit.ThemeSnapshot
function M.capture()
  return {
    options = accepted and vim.deepcopy(accepted) or nil,
    runtime = require("orbit.modules.theme.runtime").capture(),
  }
end

---@param snapshot Orbit.ThemeSnapshot
function M.restore(snapshot)
  accepted = snapshot.options and vim.deepcopy(snapshot.options) or nil
  require("orbit.modules.theme.runtime").restore(snapshot.runtime)
end

---@param opts? Orbit.ThemeOptions
function M.setup(opts)
  accepted = require("orbit.config").resolve_module("theme", opts)
  require("orbit.modules.theme.runtime").update(accepted)
end

---@return Orbit.ThemeOptions?
function M.current_options()
  return accepted and vim.deepcopy(accepted) or nil
end

---Declare the default colorscheme plugin; it starts the theme runtime.
---@return LazySpec
function M.spec()
  if not accepted or not accepted.enabled then
    return {}
  end
  return {
    {
      "folke/tokyonight.nvim",
      lazy = false,
      priority = 1000,
      opts = {},
      config = function(_, opts)
        require("tokyonight").setup(opts)
        require("orbit.modules.theme.runtime").start()
      end,
    },
  }
end

return M
