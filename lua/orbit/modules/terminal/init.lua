local M = {}
---@type Orbit.TerminalOptions?
local accepted

---@alias Orbit.TerminalPosition 'sp'|'vsp'|'float'

---@class Orbit.TerminalOptions # Native terminal windows, shells and persistent sessions.
---@field enabled? boolean @default(true) # Allow terminal actions from keymaps and Lua.
---@field horizontal_size? integer @default(30) @minimum(5) @maximum(90) # Horizontal terminal height as an editor percentage.
---@field vertical_size? integer @default(20) @minimum(5) @maximum(90) # Vertical terminal width as an editor percentage.
---@field float_width? integer @default(80) @minimum(5) @maximum(100) # Floating terminal width as an editor percentage.
---@field float_height? integer @default(80) @minimum(5) @maximum(100) # Floating terminal height as an editor percentage.
---@field startinsert? boolean @default(true) # Enter terminal input mode after opening a session.

---@return Orbit.TerminalOptions?
function M.capture()
  return accepted and vim.deepcopy(accepted) or nil
end

---@param snapshot Orbit.TerminalOptions?
function M.restore(snapshot)
  accepted = snapshot and vim.deepcopy(snapshot) or nil
end

---@param opts? Orbit.TerminalOptions
function M.setup(opts)
  accepted = require("orbit.config").resolve_module("terminal", opts)
end

---@return Orbit.TerminalOptions?
function M.current_options()
  return accepted and vim.deepcopy(accepted) or nil
end

---@param pos Orbit.TerminalPosition
---@param id? string
---@return integer?
function M.open(pos, id)
  if accepted and accepted.enabled then
    return require("orbit.modules.terminal.runtime").open(pos, id, accepted)
  end
end

---@param pos Orbit.TerminalPosition
---@param id string
---@return boolean
function M.toggle(pos, id)
  if not accepted or not accepted.enabled then
    return false
  end
  return require("orbit.modules.terminal.runtime").toggle(pos, id, accepted)
end

return M
