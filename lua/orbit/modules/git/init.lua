local M = {}
local accepted

---@class Orbit.GitMarks # Marker text for unstaged changes.
---@field add string @default("▎") # Added line marker.
---@field change string @default("▎") # Changed line marker.
---@field delete string @default("") # Deleted line marker.
---@field topdelete string @default("") # Top-deleted line marker.
---@field changedelete string @default("▎") # Changed-and-deleted marker.
---@field untracked string @default("▎") # Untracked line marker.

---@class Orbit.GitStaged # Marker text for staged changes.
---@field add string @default(" ") # Staged addition marker.
---@field change string @default(" ") # Staged modification marker.
---@field delete string @default(" ") # Staged deletion marker.
---@field topdelete string @default("") # Staged top-deletion marker.
---@field changedelete string @default("▎") # Staged changed-and-deleted marker.

---@class Orbit.GitOptions # Lazy gitsigns integration.
---@field enabled boolean @default(true) @restart(true) # Include gitsigns in the plugin specs.
---@field marks Orbit.GitMarks @default({}) @restart(true) # Unstaged change markers.
---@field staged Orbit.GitStaged @default({}) @restart(true) # Staged change markers.

---@return Orbit.GitOptions?
function M.capture()
  return accepted and vim.deepcopy(accepted) or nil
end

---@param snapshot Orbit.GitOptions?
function M.restore(snapshot)
  accepted = snapshot and vim.deepcopy(snapshot) or nil
end

---@param opts? Orbit.GitOptions
function M.setup(opts)
  accepted = require("orbit.config").resolve_module("git", opts)
end

local function translate(marks)
  local signs = {}
  for name, text in pairs(marks) do
    signs[name] = { text = text }
  end
  return signs
end

---Return only the Lazy declaration; do not load gitsigns during setup.
---@return LazySpec
function M.spec()
  if not accepted or not accepted.enabled then
    return {}
  end
  local config = vim.deepcopy(accepted)
  return {
    {
      "lewis6991/gitsigns.nvim",
      event = "User FilePost",
      opts = {
        signs = translate(config.marks),
        signs_staged = translate(config.staged),
      },
    },
  }
end

return M
