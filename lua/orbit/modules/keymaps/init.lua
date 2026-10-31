local M = {}
local active_mapping

---@class Orbit.KeymapsOptions
---@field enabled boolean
---@field leader string
---@field save string

---@param opts? Orbit.KeymapsOptions
function M.setup(opts)
  opts = require("orbit.config").resolve_module("keymaps", opts)
  if active_mapping then
    pcall(vim.keymap.del, "n", active_mapping)
    active_mapping = nil
  end

  if not opts.enabled then
    return
  end

  vim.g.mapleader = opts.leader
  vim.keymap.set("n", opts.save, "<cmd>write<cr>", {
    desc = "Save the current buffer",
    silent = true,
  })
  active_mapping = opts.save
end

return M
