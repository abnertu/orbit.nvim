-- Theme controls backed by native Neovim colorschemes and vim.ui.
-- This does not import an external theme picker or recreate old UI caches.
local M = {}

local function apply(name)
  if type(name) ~= "string" or name == "" then return false end
  local ok, err = pcall(vim.cmd.colorscheme, name)
  if not ok then
    vim.notify("[theme] " .. tostring(err), vim.log.levels.WARN)
  end
  return ok
end

---Offer all currently installed runtime colorschemes.
function M.select()
  local names = vim.fn.getcompletion("", "color")
  if type(names) ~= "table" or #names == 0 then
    vim.notify("[theme] no colorschemes available", vim.log.levels.WARN)
    return
  end
  table.sort(names)
  vim.ui.select(names, { prompt = "Select colorscheme" }, function(choice)
    if not choice or not apply(choice) then return end
    if not package.loaded["orbit.modules.theme.runtime"] then return end
    -- The theme owner saves the choice only to an existing settings file.
    local saved, err = require("orbit.modules.theme.runtime").persist(choice)
    if not saved then
      vim.notify("[theme] " .. choice .. " applies to this session: " .. tostring(err),
        vim.log.levels.INFO)
    end
  end)
end

---Reapply the active colorscheme without importing theme-cache plugins.
---@return boolean
function M.reload()
  local current = vim.g.colors_name
  if type(current) ~= "string" or current == "" then
    vim.notify("[theme] no active colorscheme", vim.log.levels.WARN)
    return false
  end
  local ok = apply(current)
  if ok then
    vim.notify("Theme reloaded", vim.log.levels.INFO,
      { title = "orbit.nvim theme" })
  end
  return ok
end

return M
