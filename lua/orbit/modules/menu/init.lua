-- Context-menu declarations stay inert until Lazy activates the feature.
local M = {}
local accepted

---@class Orbit.MenuOptions # Mouse context menus for files and the tree explorer.
---@field enabled? boolean @default(true) @restart(true) # Contribute mouse context-menu mappings and Lazy specifications.

---@return Orbit.MenuOptions?
function M.capture()
  return accepted and vim.deepcopy(accepted) or nil
end

---@param snapshot Orbit.MenuOptions?
function M.restore(snapshot)
  accepted = snapshot and vim.deepcopy(snapshot) or nil
end

---@param opts? Orbit.MenuOptions
function M.setup(opts)
  accepted = require("orbit.config").resolve_module("menu", opts)
end

---@return LazySpec
function M.spec()
  if not accepted or not accepted.enabled then return {} end
  local keys = {}
  for _, lhs in ipairs({ "<RightMouse>", "<2-RightMouse>", "<3-RightMouse>", "<4-RightMouse>" }) do
    keys[#keys + 1] = {
      lhs, function() require("orbit.modules.menu.runtime").open() end,
      mode = { "n", "v" }, desc = "Open context menu",
    }
  end
  return { {
    "Orbit-Lua/menu", dependencies = { "Orbit-Lua/volt" }, keys = keys,
    config = function() require("orbit.modules.menu.runtime").install() end,
  } }
end

return M
