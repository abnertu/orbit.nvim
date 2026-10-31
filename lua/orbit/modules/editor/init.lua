local M = {}

---@class Orbit.EditorOptions
---@field enabled boolean
---@field number boolean
---@field relativenumber boolean
---@field expandtab boolean
---@field shiftwidth integer
---@field tabstop integer

local options = { "number", "relativenumber", "expandtab", "shiftwidth", "tabstop" }

-- A global default does not replace the local value of an existing buffer or
-- window. Apply both so setup() affects the current editing session as well.
local function apply_option(name, value)
  vim.api.nvim_set_option_value(name, value, { scope = "global" })

  local scope = vim.api.nvim_get_option_info2(name, {}).scope
  if scope == "buf" then
    for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_loaded(buffer) and vim.bo[buffer].buftype == "" then
        vim.api.nvim_set_option_value(name, value, { buf = buffer })
      end
    end
  elseif scope == "win" then
    for _, window in ipairs(vim.api.nvim_list_wins()) do
      local buffer = vim.api.nvim_win_get_buf(window)
      if vim.bo[buffer].buftype == "" and vim.api.nvim_win_get_config(window).relative == "" then
        vim.api.nvim_set_option_value(name, value, { win = window })
      end
    end
  end
end

---@param opts? Orbit.EditorOptions
function M.setup(opts)
  opts = require("orbit.config").resolve_module("editor", opts)
  if not opts.enabled then
    return
  end

  for _, name in ipairs(options) do
    apply_option(name, opts[name])
  end
end

return M
