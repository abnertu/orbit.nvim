local M = {}
local wrapped = false

---@param opts snacks.Config
function M.setup(opts)
  local snacks = require("snacks")
  if opts.dashboard and opts.dashboard.enabled then
    vim.api.nvim_create_autocmd("User", {
      group = vim.api.nvim_create_augroup("OrbitSnacksStartup", { clear = true }),
      pattern = "LazyVimStarted",
      once = true,
      callback = function()
        vim.schedule(function()
          local dashboard = package.loaded["snacks.dashboard"]
          if dashboard then
            dashboard.update()
          end
        end)
      end,
      desc = "Refresh dashboard startup statistics after Lazy's UI timing completes",
    })
  end
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
