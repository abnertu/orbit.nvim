-- Blink 1.x can release an older preview timeout after a newer preview starts.
-- Keep its automatic insertion and 20ms release, but expire only the latest one.
-- Compatibility boundary: blink.cmp v1.10.2, lib/cmdline_events.lua.
local M = {}

---@class Orbit.BlinkCmdlineEvents
---@field ignore_next_cursor_moved boolean
---@field listen fun(self: Orbit.BlinkCmdlineEvents, listeners: Orbit.BlinkCmdlineListeners)

---@class Orbit.BlinkCmdlineListeners
---@field on_char_added fun(char: string, ignored: boolean)
---@field on_cursor_moved fun(event: string, ignored: boolean)
---@field on_leave fun()

---@type table<Orbit.BlinkCmdlineEvents, integer>
local generations = setmetatable({}, { __mode = "k" })

---@param events Orbit.BlinkCmdlineEvents
---@param callback fun()
local function suppress(events, callback)
  local generation = (generations[events] or 0) + 1
  generations[events] = generation
  local before = vim.fn.getcmdpos()
  callback()
  if vim.api.nvim_get_mode().mode ~= "c" then return end
  events.ignore_next_cursor_moved = true
  if vim.fn.getcmdpos() == before then
    vim.defer_fn(function()
      if generations[events] == generation then
        events.ignore_next_cursor_moved = false
      end
    end, 20)
  end
end

-- Blink registers its listeners after asynchronous matcher initialization.
-- Handle text already entered during that gap, after completion setup finishes.
---@param events Orbit.BlinkCmdlineEvents
local function recover_first_input(events)
  local group = vim.api.nvim_create_augroup("OrbitCompletionCmdline", { clear = true })
  local revision = 0
  vim.api.nvim_create_autocmd({ "CmdlineEnter", "CmdlineLeave", "CmdlineChanged" }, {
    group = group,
    callback = function() revision = revision + 1 end,
  })
  local listen = events.listen
  events.listen = function(self, listeners)
    events.listen = listen
    listen(self, listeners)
    local pending = revision
    local text, position = vim.fn.getcmdline(), vim.fn.getcmdpos()
    vim.schedule(function()
      vim.api.nvim_clear_autocmds({ group = group })
      if pending ~= revision or vim.api.nvim_get_mode().mode ~= "c"
        or vim.fn.getcmdtype() ~= ":" or vim.fn.getcmdline() ~= text
        or vim.fn.getcmdpos() ~= position
      then return end
      local prefix = text:sub(1, position - 1)
      local char = vim.fn.strcharpart(prefix, vim.fn.strchars(prefix) - 1, 1)
      if char ~= "" then listeners.on_char_added(char, false) end
    end)
  end
end

---Install only from the completion owner's restart-only Lazy config boundary.
---@param cmdline_enabled boolean
function M.install(cmdline_enabled)
  local events = require("blink.cmp.lib.cmdline_events")
  assert(type(events.suppress_events_for_callback) == "function",
    "unsupported Blink commandline event API")
  events.suppress_events_for_callback = suppress
  if cmdline_enabled then
    assert(type(events.listen) == "function", "unsupported Blink commandline listener API")
    recover_first_input(events)
  end
end

return M
