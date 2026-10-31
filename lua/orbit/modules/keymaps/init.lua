local M = {}
local owned = {}

---@class Orbit.KeymapsOptions # Minimal key mappings owned by orbit.nvim.
---@field enabled boolean @default(true) # Register the module mappings.
---@field leader string @default(" ") @minLength(1) # Leader key set before module mappings.
---@field save string @default("<leader>w") @minLength(1) # Normal-mode mapping that writes the current buffer.

-- Store physical keys, not <leader> aliases, so reconfiguration restores the
-- previous mappings even after mapleader changes.
local function expand_leader(lhs, leader)
  return (lhs:gsub("<[Ll][Ee][Aa][Dd][Ee][Rr]>", function()
    return leader
  end))
end

local definitions = {
  { name = "save", rhs = "<cmd>write<cr>", desc = "Save the current buffer" },
  { lhs = "<leader>bn", rhs = function() vim.cmd.enew() end,
    desc = "Open a new buffer" },
  { lhs = "<leader>fd", rhs = function()
    require("orbit.modules.keymaps.project").cd_to_root()
  end, desc = "Change directory to the current project root" },
  { lhs = "<leader>tf", rhs = function()
    vim.diagnostic.open_float()
  end, desc = "Show diagnostics in a floating window" },
}

local function mapping_at(lhs)
  local mapping = vim.fn.maparg(lhs, "n", false, true)
  if type(mapping) == "table" and not vim.tbl_isempty(mapping) then
    return vim.deepcopy(mapping)
  end
  return false
end

local function restore_mapping(lhs, mapping)
  pcall(vim.keymap.del, "n", lhs)
  if mapping == false then return end
  vim.keymap.set("n", lhs, mapping.callback or mapping.rhs, {
    remap = mapping.noremap == 0,
    silent = mapping.silent == 1,
    expr = mapping.expr == 1,
    nowait = mapping.nowait == 1,
    desc = mapping.desc,
  })
end

local function targets(opts)
  local result, seen = {}, {}
  if not opts.enabled then return result end
  for _, definition in ipairs(definitions) do
    local lhs = expand_leader(definition.lhs or opts[definition.name], opts.leader)
    assert(not seen[lhs], "duplicate leader mapping: " .. lhs)
    seen[lhs] = true
    result[#result + 1] = {
      lhs = lhs,
      rhs = definition.rhs,
      desc = definition.desc,
    }
  end
  return result
end

---Capture the old physical mappings and the proposed targets.
---@param opts Orbit.KeymapsOptions
---@return table
function M.capture(opts)
  local affected = {}
  for lhs in pairs(owned) do affected[lhs] = mapping_at(lhs) end
  for _, target in ipairs(targets(opts)) do
    if affected[target.lhs] == nil then
      affected[target.lhs] = mapping_at(target.lhs)
    end
  end
  return {
    leader = vim.g.mapleader,
    owned = vim.deepcopy(owned),
    affected = affected,
  }
end

---@param snapshot table
function M.restore(snapshot)
  for lhs, entry in pairs(owned) do
    restore_mapping(lhs, snapshot.affected[lhs] or entry.original)
  end
  for lhs, mapping in pairs(snapshot.affected) do
    restore_mapping(lhs, mapping)
  end
  vim.g.mapleader = snapshot.leader
  owned = vim.deepcopy(snapshot.owned)
end

---@param opts? Orbit.KeymapsOptions
function M.setup(opts)
  opts = require("orbit.config").resolve_module("keymaps", opts)
  local next_targets = targets(opts)
  local desired = {}
  for _, target in ipairs(next_targets) do desired[target.lhs] = true end

  for lhs, entry in pairs(owned) do
    if not desired[lhs] then restore_mapping(lhs, entry.original) end
  end
  if opts.enabled then vim.g.mapleader = opts.leader end

  local next_owned = {}
  for _, target in ipairs(next_targets) do
    local previous = owned[target.lhs]
    local original = previous and previous.original or mapping_at(target.lhs)
    vim.keymap.set("n", target.lhs, target.rhs, {
      desc = target.desc,
      silent = true,
    })
    next_owned[target.lhs] = { original = original }
  end
  owned = next_owned
end

return M
