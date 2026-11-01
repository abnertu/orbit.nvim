-- Blink 1.x can release an older preview timeout after a newer preview starts.
-- Keep its automatic insertion and 20ms release, but expire only the latest one.
-- Compatibility boundary: blink.cmp v1.10.2, lib/cmdline_events.lua.
local M = {}

---@class Orbit.BlinkCmdlineEvents
---@field ignore_next_cursor_moved boolean

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

---Install only from the completion owner's restart-only Lazy config boundary.
function M.install()
  local events = require("blink.cmp.lib.cmdline_events")
  assert(type(events.suppress_events_for_callback) == "function",
    "unsupported Blink commandline event API")
  events.suppress_events_for_callback = suppress
end

return M
