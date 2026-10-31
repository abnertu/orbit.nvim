local M = {}

---@class Orbit.EditorOptions
---@field enabled boolean
---@field number boolean
---@field relativenumber boolean
---@field expandtab boolean
---@field shiftwidth integer
---@field tabstop integer

---@param opts? Orbit.EditorOptions
function M.setup(opts)
  opts = require("orbit.config").resolve_module("editor", opts)
  if not opts.enabled then
    return
  end

  for _, name in ipairs({
    "number",
    "relativenumber",
    "expandtab",
    "shiftwidth",
    "tabstop",
  }) do
    vim.api.nvim_set_option_value(name, opts[name], { scope = "global" })
  end
end

return M
