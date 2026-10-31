-- All managed tool consumers use one feature-state boundary. Never
-- require Hangar during setup when its Lazy owner is not active.
local M = {}

local function active()
  return package.loaded.hangar ~= nil
end

---@param category string
---@param name string
---@return boolean
function M.is_enabled(category, name)
  if not active() then
    return true
  end
  return require("hangar.state").is_enabled(category, name)
end

---@param category "formatter"|"linter"
---@param by_ft table
---@return table
function M.filter(category, by_ft)
  if not active() then
    return vim.deepcopy(by_ft)
  end
  return require("hangar").filter(category, by_ft)
end

return M
