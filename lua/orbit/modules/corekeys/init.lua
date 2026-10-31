local M = {}
local owned = {}

---@class Orbit.CorekeysOptions # Core file and window navigation mappings.
---@field enabled boolean @default(true) # Register the core mappings.
---@field save string @default("<C-s>") @minLength(1) # Save the current buffer.
---@field window_left string @default("<C-h>") @minLength(1) # Focus the left window.
---@field window_right string @default("<C-l>") @minLength(1) # Focus the right window.
---@field window_up string @default("<C-k>") @minLength(1) # Focus the upper window.
---@field window_down string @default("<C-j>") @minLength(1) # Focus the lower window.

-- Preserve the selected range and visual selection when moving lines.
local function move_visual(direction)
  vim.api.nvim_feedkeys(vim.keycode("<Esc>"), "x", false)
  if direction == "down" then
    vim.cmd("'<,'>move '>+1")
  else
    vim.cmd("'<,'>move '<-2")
  end
  vim.cmd("normal! gv-gv")
end

local definitions = {
  { field = "save", mode = "n", rhs = "<cmd>write<cr>", desc = "Save the current buffer" },
  { field = "window_left", mode = "n", rhs = "<C-w>h", desc = "Focus left window" },
  { field = "window_right", mode = "n", rhs = "<C-w>l", desc = "Focus right window" },
  { field = "window_up", mode = "n", rhs = "<C-w>k", desc = "Focus upper window" },
  { field = "window_down", mode = "n", rhs = "<C-w>j", desc = "Focus lower window" },
  -- Plugin-independent legacy editing keys use fixed slots. They share the
  -- owner lifecycle with the configurable save and window navigation keys.
  { lhs = "<C-c>", mode = "n", rhs = "<cmd>%y+<cr>", desc = "Copy the whole file" },
  { lhs = ";", mode = "n", rhs = ":", desc = "Enter command mode" },
  { lhs = "<", mode = "n", rhs = "<<", desc = "Decrease line indent" },
  { lhs = ">", mode = "n", rhs = ">>", desc = "Increase line indent" },
  { lhs = "<", mode = "x", rhs = "<gv", desc = "Decrease indent and keep selection" },
  { lhs = ">", mode = "x", rhs = ">gv", desc = "Increase indent and keep selection" },
  { lhs = "p", mode = "x", rhs = "P", desc = "Paste without replacing the unnamed register" },
  { lhs = "J", mode = "x", rhs = function() move_visual("down") end,
    desc = "Move selected lines down" },
  { lhs = "K", mode = "x", rhs = function() move_visual("up") end,
    desc = "Move selected lines up" },
  { lhs = "jk", mode = "i", rhs = "<Esc>", desc = "Leave insert mode" },
  { lhs = "Q", mode = "n", rhs = "q", desc = "Record a macro" },
  { lhs = "q", mode = "n", rhs = "<Nop>", desc = "Reserve lowercase q" },
  { lhs = "K", mode = "n", rhs = "<Nop>", desc = "Reserve K for an attached LSP" },
  { lhs = "<C-x>", mode = "t", rhs = "<C-\\><C-n>", desc = "Leave terminal mode" },
}

local function identity(mode, lhs)
  return mode .. ":" .. lhs
end

local function mapping(mode, lhs)
  local current = vim.fn.maparg(lhs, mode, false, true)
  if type(current) == "table" and not vim.tbl_isempty(current) then
    return vim.deepcopy(current)
  end
  return false
end

local function restore_mapping(mode, lhs, previous)
  pcall(vim.keymap.del, mode, lhs)
  if previous == false then
    return
  end
  vim.keymap.set(mode, lhs, previous.callback or previous.rhs, {
    remap = previous.noremap == 0,
    silent = previous.silent == 1,
    expr = previous.expr == 1,
    nowait = previous.nowait == 1,
    desc = previous.desc,
  })
end

local function targets(opts)
  local result = {}
  if not opts.enabled then
    return result
  end
  local seen = {}
  for _, definition in ipairs(definitions) do
    local lhs = definition.lhs or opts[definition.field]
    local key = identity(definition.mode, lhs)
    assert(not seen[key], "duplicate core mapping: " .. lhs)
    seen[key] = true
    result[#result + 1] = {
      mode = definition.mode,
      lhs = lhs,
      key = key,
      rhs = definition.rhs,
      desc = definition.desc,
    }
  end
  return result
end

---Capture effective bindings at both existing and proposed key sequences.
---@param opts Orbit.CorekeysOptions
---@return table
function M.capture(opts)
  local affected = {}
  for key, previous in pairs(owned) do
    affected[key] = {
      mode = previous.mode,
      lhs = previous.lhs,
      current = mapping(previous.mode, previous.lhs),
    }
  end
  for _, target in ipairs(targets(opts)) do
    if not affected[target.key] then
      affected[target.key] = {
        mode = target.mode,
        lhs = target.lhs,
        current = mapping(target.mode, target.lhs),
      }
    end
  end
  return { owned = vim.deepcopy(owned), affected = affected }
end

---@param snapshot table
function M.restore(snapshot)
  for _, previous in pairs(owned) do
    pcall(vim.keymap.del, previous.mode, previous.lhs)
  end
  for _, entry in pairs(snapshot.affected) do
    restore_mapping(entry.mode, entry.lhs, entry.current)
  end
  owned = vim.deepcopy(snapshot.owned)
end

---@param opts? Orbit.CorekeysOptions
function M.setup(opts)
  opts = require("orbit.config").resolve_module("corekeys", opts)
  local next_targets = targets(opts)
  local desired = {}
  for _, target in ipairs(next_targets) do
    desired[target.key] = true
  end

  -- Restore the original bindings before releasing previously owned slots.
  for key, previous in pairs(owned) do
    if not desired[key] then
      restore_mapping(previous.mode, previous.lhs, previous.original)
    end
  end

  local next_owned = {}
  for _, target in ipairs(next_targets) do
    local previous = owned[target.key]
    local original = previous and previous.original or
      mapping(target.mode, target.lhs)
    vim.keymap.set(target.mode, target.lhs, target.rhs, {
      desc = target.desc,
      silent = true,
    })
    next_owned[target.key] = {
      mode = target.mode,
      lhs = target.lhs,
      original = original,
    }
  end

  owned = next_owned
end

return M
