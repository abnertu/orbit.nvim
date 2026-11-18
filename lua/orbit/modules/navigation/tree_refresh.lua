-- Refresh nvim-tree when filesystem watchers are off. A reload rescans every
-- expanded directory synchronously, so only events that can change the tree
-- request one. Writing an existing file or focusing the tree does not.
local M = {}

local group_name = "OrbitTreeRefresh"
local pending = false
---@type table<integer, boolean>
local creating = {}

---Reload a visible tree once for all requests of the current event-loop turn.
function M.request()
  if pending then
    return
  end
  pending = true
  vim.schedule(function()
    pending = false
    local api = require("nvim-tree.api")
    if api.tree.is_visible({ any_tabpage = true }) then
      api.tree.reload()
    end
  end)
end

---Install the refresh events. Repeated calls replace the earlier autocommands.
function M.attach()
  local group = vim.api.nvim_create_augroup(group_name, { clear = true })
  vim.api.nvim_create_autocmd("BufWritePre", {
    group = group,
    callback = function(event)
      creating[event.buf] = vim.bo[event.buf].buftype == "" and vim.uv.fs_stat(event.match) == nil
    end,
  })
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = group,
    callback = function(event)
      if creating[event.buf] then
        M.request()
      end
      creating[event.buf] = nil
    end,
  })
  vim.api.nvim_create_autocmd({ "FocusGained", "TermLeave", "ShellCmdPost" }, {
    group = group,
    callback = M.request,
  })
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "OilActionsPost",
    callback = M.request,
  })
end

return M
