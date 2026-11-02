-- Comet b30afe9 exposes no window-highlight option. Its presence check for
-- Volt groups must not choose the appearance of the Dotnet Manager.
local M = {}
local installed = false

---@param opts DotnetCliConfig
function M.setup(opts)
  if installed then return end
  local dotnet = require("dotnet-cli")
  dotnet.setup(opts)
  local open = dotnet.open
  dotnet.open = function()
    open()
    local state = require("comet.state")
    local manager = state.is_open() and state.get() or nil
    if not manager then return end
    for _, window in ipairs({ manager.input_win, manager.list_win, manager.output_win }) do
      if vim.api.nvim_win_is_valid(window) then
        vim.wo[window].winhighlight = "Normal:NormalFloat,NormalNC:NormalFloat,FloatBorder:FloatBorder,FloatTitle:FloatTitle"
      end
    end
  end
  installed = true
end

return M
