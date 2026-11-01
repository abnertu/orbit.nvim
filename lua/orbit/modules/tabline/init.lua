local M = {}

---@alias Orbit.TablineSnapshot {owned: boolean, original?: {tabline: string, showtabline: integer}, current: {tabline: string, showtabline: integer}}
local owned = false
---@type {tabline: string, showtabline: integer}?
local original
local group_name = "OrbitTabline"
local expression = "%!v:lua.require'orbit.modules.tabline.render'.render()"

---@class Orbit.TablineOptions # Orbit buffer and tab line.
---@field enabled? boolean @default(true) # Draw the Orbit tab line.

local function options()
  return { tabline = vim.go.tabline, showtabline = vim.go.showtabline }
end

local function sync(active)
  pcall(vim.api.nvim_del_augroup_by_name, group_name)
  local buffers = require("orbit.buffers")
  if not active then
    buffers.detach("tabline")
    return
  end
  buffers.attach("tabline")
  local group = vim.api.nvim_create_augroup(group_name, { clear = true })
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = group,
    callback = function() require("orbit.modules.tabline.render").define_highlights() end,
    desc = "Restore Orbit tab line highlight links",
  })
end

---@return Orbit.TablineSnapshot
function M.capture()
  return { owned = owned, original = original and vim.deepcopy(original), current = options() }
end

---@param snapshot Orbit.TablineSnapshot
function M.restore(snapshot)
  owned, original = snapshot.owned, snapshot.original and vim.deepcopy(snapshot.original)
  vim.go.tabline, vim.go.showtabline = snapshot.current.tabline, snapshot.current.showtabline
  sync(owned)
end

---@param opts? Orbit.TablineOptions
function M.setup(opts)
  opts = require("orbit.config").resolve_module("tabline", opts)
  if opts.enabled then
    if not owned then original, owned = options(), true end
    vim.go.tabline, vim.go.showtabline = expression, 2
  elseif owned then
    -- Keep a tab line the user set after Orbit took ownership.
    if vim.go.tabline == expression then
      vim.go.tabline, vim.go.showtabline = original.tabline, original.showtabline
    end
    owned, original = false, nil
  end
  sync(owned)
end

return M
