-- Smart Escape behavior, with optional integrations consulted only if loaded.
-- This helper never imports a UI or completion plugin on an ordinary Escape.
local M = {}

local function active_menu()
  local state = package.loaded["menu.state"]
  return type(state) == "table"
    and type(state.bufids) == "table"
    and #state.bufids > 0
end

local function stop_snippet()
  local luasnip = package.loaded["luasnip"]
  if type(luasnip) == "table"
    and type(luasnip.session) == "table"
    and type(luasnip.session.current_nodes) == "table"
    and luasnip.session.current_nodes[vim.api.nvim_get_current_buf()]
    and type(luasnip.unlink_current) == "function"
  then
    luasnip.unlink_current()
    return
  end

  if vim.snippet and type(vim.snippet.stop) == "function" then
    vim.snippet.stop()
  end
end

---Return an expression-map result for Normal, Insert and Select modes.
---@return string
function M.escape()
  if active_menu() then
    vim.schedule(function()
      local ok, utils = pcall(require, "menu.utils")
      if ok and type(utils.delete_old_menus) == "function" then
        utils.delete_old_menus()
      end
    end)
    return ""
  end

  vim.cmd("nohlsearch")
  stop_snippet()
  return "<Esc>"
end

return M
