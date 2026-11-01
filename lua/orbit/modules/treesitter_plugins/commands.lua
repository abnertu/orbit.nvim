-- Register bulk parser installation after nvim-treesitter activates.
-- The parser list comes from the canonical Hangar registry.
local M = {}
local registered = false

---@return string[]
function M.parsers()
  local names = vim.tbl_keys(require("orbit.modules.hangar.registry").parser)
  table.sort(names)
  return names
end

-- Lazy activation is restart-only, so the command is registered once and
-- never replaces a user-owned TSInstallAll.
function M.setup()
  if registered then return end
  if vim.api.nvim_get_commands({}).TSInstallAll ~= nil then
    vim.notify("TSInstallAll already exists; Orbit leaves it unchanged",
      vim.log.levels.WARN, { title = "orbit.nvim Tree-sitter" })
    return
  end
  vim.api.nvim_create_user_command("TSInstallAll", function()
    require("nvim-treesitter").install(M.parsers())
  end, { desc = "Install all configured Tree-sitter parsers" })
  registered = true
end

return M
