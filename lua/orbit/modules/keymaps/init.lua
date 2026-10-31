local M = {}
local active_mapping

---@class Orbit.KeymapsOptions
---@field enabled boolean
---@field leader string
---@field save string

-- Resolve the key sequence before changing mapleader. Retain the physical
-- mapping so a later leader change cannot orphan the previous mapping.
local function expand_leader(lhs, leader)
  return (lhs:gsub("<[Ll][Ee][Aa][Dd][Ee][Rr]>", function()
    return leader
  end))
end

local function mapping_at(lhs)
  local mapping = vim.fn.maparg(lhs, "n", false, true)
  if type(mapping) == "table" and not vim.tbl_isempty(mapping) then
    return vim.deepcopy(mapping)
  end
  return false
end

local function restore_mapping(lhs, mapping)
  pcall(vim.keymap.del, "n", lhs)
  if mapping == false then
    return
  end
  vim.keymap.set("n", lhs, mapping.callback or mapping.rhs, {
    remap = mapping.noremap == 0,
    silent = mapping.silent == 1,
    expr = mapping.expr == 1,
    nowait = mapping.nowait == 1,
    desc = mapping.desc,
  })
end

---Capture the owned mapping and the new target's prior binding.
---@param opts Orbit.KeymapsOptions
---@return table
function M.capture(opts)
  local affected = {}
  if active_mapping then
    affected[active_mapping] = mapping_at(active_mapping)
  end
  if opts.enabled then
    local target = expand_leader(opts.save, opts.leader)
    if affected[target] == nil then
      affected[target] = mapping_at(target)
    end
  end
  return {
    leader = vim.g.mapleader,
    active = active_mapping,
    affected = affected,
  }
end

---@param snapshot table
function M.restore(snapshot)
  if active_mapping then
    pcall(vim.keymap.del, "n", active_mapping)
  end
  for lhs, previous in pairs(snapshot.affected) do
    restore_mapping(lhs, previous)
  end
  vim.g.mapleader = snapshot.leader
  active_mapping = snapshot.active
end

---@param opts? Orbit.KeymapsOptions
function M.setup(opts)
  opts = require("orbit.config").resolve_module("keymaps", opts)
  if active_mapping then
    pcall(vim.keymap.del, "n", active_mapping)
    active_mapping = nil
  end

  if not opts.enabled then
    return
  end

  vim.g.mapleader = opts.leader
  local key = expand_leader(opts.save, opts.leader)
  vim.keymap.set("n", key, "<cmd>write<cr>", {
    desc = "Save the current buffer",
    silent = true,
  })
  active_mapping = key
end

return M
