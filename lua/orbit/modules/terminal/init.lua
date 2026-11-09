local M = {}
---@type Orbit.TerminalOptions?
local accepted

---@alias Orbit.TerminalPosition 'sp'|'vsp'|'float'

---@alias Orbit.TerminalShellOption 'shell'|'shellcmdflag'|'shellredir'|'shellpipe'|'shellquote'|'shellxquote'|'shelltemp'
---@alias Orbit.TerminalShellValue string|boolean
---@alias Orbit.TerminalShellEntry {original: Orbit.TerminalShellValue, observed: Orbit.TerminalShellValue, source: integer, explicit: boolean, owned?: Orbit.TerminalShellValue}
---@alias Orbit.TerminalShellSnapshot {values: table<Orbit.TerminalShellOption, Orbit.TerminalShellValue>, entries: table<Orbit.TerminalShellOption, Orbit.TerminalShellEntry>, active: boolean}
---@alias Orbit.TerminalShellProfile {executable: string, interactive: string[], options: table<Orbit.TerminalShellOption, Orbit.TerminalShellValue>}
---@alias Orbit.TerminalSnapshot {options?: Orbit.TerminalOptions, shell?: Orbit.TerminalShellSnapshot}
---@alias Orbit.TerminalJobEnvironment {PATH: string}

---@class Orbit.TerminalOptions # Native terminal windows, shells and persistent sessions.
---@field enabled? boolean @default(true) # Allow terminal actions from keymaps and Lua.
---@field horizontal_size? integer @default(30) @minimum(5) @maximum(90) # Horizontal terminal height as an editor percentage.
---@field vertical_size? integer @default(20) @minimum(5) @maximum(90) # Vertical terminal width as an editor percentage.
---@field float_width? integer @default(80) @minimum(5) @maximum(100) # Floating terminal width as an editor percentage.
---@field float_height? integer @default(80) @minimum(5) @maximum(100) # Floating terminal height as an editor percentage.
---@field startinsert? boolean @default(true) # Enter terminal input mode after opening a session.

---@return Orbit.TerminalSnapshot
function M.capture()
  return {
    options = accepted and vim.deepcopy(accepted) or nil,
    shell = require("orbit.modules.terminal.shell").capture(),
  }
end

---@param snapshot Orbit.TerminalSnapshot
function M.restore(snapshot)
  require("orbit.modules.terminal.shell").restore(snapshot.shell)
  accepted = snapshot.options and vim.deepcopy(snapshot.options) or nil
end

---@param opts? Orbit.TerminalOptions
function M.setup(opts)
  local options = require("orbit.config").resolve_module("terminal", opts)
  require("orbit.modules.terminal.shell").setup(options.enabled)
  accepted = options
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
