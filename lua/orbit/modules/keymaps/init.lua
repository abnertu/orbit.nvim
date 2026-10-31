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
  { name = "save", mode = "n", rhs = "<cmd>write<cr>",
    desc = "Save the current buffer" },
  { lhs = "<leader>bn", mode = "n", rhs = function() vim.cmd.enew() end,
    desc = "Open a new buffer" },
  { lhs = "<leader>bD", mode = "n", rhs = function()
    require("orbit.modules.keymaps.buffer_actions").close_others()
  end, desc = "Close other unmodified listed buffers" },
  { lhs = "<leader>x", mode = "n", rhs = function()
    require("orbit.modules.keymaps.buffer_actions").close_current()
  end, desc = "Close the current unmodified buffer" },
  { lhs = "<leader>fd", mode = "n", rhs = function()
    require("orbit.modules.keymaps.project").cd_to_root()
  end, desc = "Change directory to the current project root" },
  { lhs = "<leader>tf", mode = "n", rhs = function()
    vim.diagnostic.open_float()
  end, desc = "Show diagnostics in a floating window" },
  { lhs = "<leader>fu", mode = "n", rhs = function()
    require("orbit.modules.keymaps.conversion").dos_to_unix()
  end, desc = "Convert DOS line endings to Unix" },
  { lhs = "<leader>fi", mode = "n", rhs = function()
    require("orbit.modules.keymaps.conversion").big5_to_utf8()
  end, desc = "Convert Big5 file encoding to UTF-8" },
  { lhs = "<leader>uc", mode = "n", rhs = function()
    local config = require("orbit").get_config()
    local commands = config and config.modules.commands
    if not commands or not commands.enabled then
      vim.notify("orbit.nvim settings command is disabled", vim.log.levels.WARN)
      return
    end
    -- Resolve the command on demand so renaming it does not orphan this key.
    vim.cmd[commands.name]()
  end, desc = "Open orbit.nvim settings" },
  { lhs = "<leader>/", mode = "n", rhs = "gcc", remap = true,
    desc = "Toggle line comment" },
  { lhs = "<leader>/", mode = "v", rhs = "gc", remap = true,
    desc = "Toggle selected comments" },
}

local function identity(mode, lhs)
  return mode .. ":" .. lhs
end

local function mapping_at(mode, lhs)
  local mapping = vim.fn.maparg(lhs, mode, false, true)
  if type(mapping) == "table" and not vim.tbl_isempty(mapping) then
    return vim.deepcopy(mapping)
  end
  return false
end

local function restore_mapping(mode, lhs, mapping)
  pcall(vim.keymap.del, mode, lhs)
  if mapping == false then return end
  vim.keymap.set(mode, lhs, mapping.callback or mapping.rhs, {
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
    local mode = definition.mode
    local key = identity(mode, lhs)
    assert(not seen[key], "duplicate leader mapping: " .. lhs)
    seen[key] = true
    result[#result + 1] = {
      key = key, mode = mode, lhs = lhs,
      rhs = definition.rhs,
      desc = definition.desc,
      remap = definition.remap,
    }
  end
  return result
end

---Capture the old physical mappings and the proposed targets in each mode.
---@param opts Orbit.KeymapsOptions
---@return table
function M.capture(opts)
  local affected = {}
  for key, previous in pairs(owned) do
    affected[key] = {
      mode = previous.mode,
      lhs = previous.lhs,
      current = mapping_at(previous.mode, previous.lhs),
    }
  end
  for _, target in ipairs(targets(opts)) do
    if affected[target.key] == nil then
      affected[target.key] = {
        mode = target.mode,
        lhs = target.lhs,
        current = mapping_at(target.mode, target.lhs),
      }
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
  for _, entry in pairs(owned) do
    pcall(vim.keymap.del, entry.mode, entry.lhs)
  end
  for _, entry in pairs(snapshot.affected) do
    restore_mapping(entry.mode, entry.lhs, entry.current)
  end
  vim.g.mapleader = snapshot.leader
  owned = vim.deepcopy(snapshot.owned)
end

---@param opts? Orbit.KeymapsOptions
function M.setup(opts)
  opts = require("orbit.config").resolve_module("keymaps", opts)
  local next_targets = targets(opts)
  local desired = {}
  for _, target in ipairs(next_targets) do desired[target.key] = true end

  for key, entry in pairs(owned) do
    if not desired[key] then
      restore_mapping(entry.mode, entry.lhs, entry.original)
    end
  end
  if opts.enabled then vim.g.mapleader = opts.leader end

  local next_owned = {}
  for _, target in ipairs(next_targets) do
    local previous = owned[target.key]
    local original = previous and previous.original or
      mapping_at(target.mode, target.lhs)
    vim.keymap.set(target.mode, target.lhs, target.rhs, {
      remap = target.remap == true,
      desc = target.desc,
      silent = true,
    })
    next_owned[target.key] = {
      mode = target.mode, lhs = target.lhs, original = original,
    }
  end
  owned = next_owned
end

return M
