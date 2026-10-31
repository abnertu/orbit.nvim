local M = {}
local wrapped = false

function M.setup(opts)
  local snacks = require("snacks")
  if not wrapped then
    local redraw = snacks.util.redraw_range
    assert(type(redraw) == "function", "Snacks redraw_range API is missing")
    snacks.util.redraw_range = function(...)
      local ok, err = pcall(redraw, ...)
      if not ok and not tostring(err):match("Invalid window id: %d+") then
        error("Snacks redraw failed: " .. tostring(err), 0)
      end
    end
    wrapped = true
  end
  snacks.setup(opts)
end

return M
