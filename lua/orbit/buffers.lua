-- Own the tab-local order of listed buffers for cycling and tab lines.
-- Consumers attach by name; the autocommand group lives while any owner
-- remains. Order is derived state and is not part of module snapshots.
local M = {}

local group_name = "OrbitBufferOrder"
---@type table<string, true>
local owners = {}
---@type table<integer, integer[]>
local order = {}

---@param buffer any
---@return boolean
local function eligible(buffer)
  return type(buffer) == "number"
    and vim.api.nvim_buf_is_valid(buffer)
    and vim.api.nvim_buf_is_loaded(buffer)
    and vim.bo[buffer].buflisted
end

---@param tab integer
---@param buffer integer
local function append(tab, buffer)
  if not eligible(buffer) then return end
  local list = order[tab] or {}
  if not vim.list_contains(list, buffer) then list[#list + 1] = buffer end
  order[tab] = list
end

---@param buffer integer
local function forget(buffer)
  for tab, list in pairs(order) do
    order[tab] = vim.tbl_filter(function(item) return item ~= buffer end, list)
  end
end

local function prune_tabs()
  for tab in pairs(order) do
    if not vim.api.nvim_tabpage_is_valid(tab) then order[tab] = nil end
  end
end

-- Seed existing tabs: the current tab receives every listed buffer, other
-- tabs receive the buffers their windows show.
local function seed()
  order = {}
  local current = vim.api.nvim_get_current_tabpage()
  for _, buffer in ipairs(vim.api.nvim_list_bufs()) do append(current, buffer) end
  for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
    if tab ~= current then
      for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
        append(tab, vim.api.nvim_win_get_buf(win))
      end
    end
  end
end

local function activate()
  seed()
  local group = vim.api.nvim_create_augroup(group_name, { clear = true })
  vim.api.nvim_create_autocmd({ "BufAdd", "BufEnter" }, {
    group = group,
    callback = function(args)
      -- BufAdd runs before the buffer loads; recheck after the event settles.
      local tab = vim.api.nvim_get_current_tabpage()
      append(tab, args.buf)
      if args.event == "BufAdd" then
        vim.schedule(function()
          if vim.api.nvim_tabpage_is_valid(tab) then append(tab, args.buf) end
        end)
      end
    end,
  })
  vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
    group = group,
    callback = function(args) forget(args.buf) end,
  })
  vim.api.nvim_create_autocmd("TabClosed", { group = group, callback = prune_tabs })
end

---Start tracking for `owner`. Repeated attachment by one owner is a no-op.
---@param owner string
function M.attach(owner)
  local active = next(owners) ~= nil
  owners[owner] = true
  if not active then activate() end
end

---Stop tracking for `owner`; the last owner removes the group and state.
---@param owner string
function M.detach(owner)
  owners[owner] = nil
  if next(owners) == nil then
    pcall(vim.api.nvim_del_augroup_by_name, group_name)
    order = {}
  end
end

---@param owner string
---@return boolean
function M.attached(owner)
  return owners[owner] == true
end

---Return loaded listed buffers of a tab in first-entry order. Without
---tracked entries, return every loaded listed buffer in handle order.
---@param tab? integer
---@return integer[]
function M.list(tab)
  tab = tab or vim.api.nvim_get_current_tabpage()
  local valid = vim.tbl_filter(eligible, order[tab] or {})
  if #valid > 0 then return valid end
  return vim.tbl_filter(eligible, vim.api.nvim_list_bufs())
end

---Delete a listed normal buffer while keeping every window that shows it.
---Each such window moves to the neighbour in this tab's order, or to a new
---empty buffer. Modified and special buffers are refused.
---@param buffer integer
---@return boolean, string?
function M.close(buffer)
  if not eligible(buffer) or vim.bo[buffer].buftype ~= "" then
    return false, "cannot close a special or unlisted buffer"
  end
  if vim.bo[buffer].modified then
    return false, "buffer has unsaved changes: " .. vim.api.nvim_buf_get_name(buffer)
  end
  local list = M.list()
  local index = 1
  for position, item in ipairs(list) do
    if item == buffer then index = position end
  end
  local replacement = list[index + 1] or list[index - 1]
  if replacement == buffer then replacement = nil end
  for _, win in ipairs(vim.fn.win_findbuf(buffer)) do
    if replacement then
      vim.api.nvim_win_set_buf(win, replacement)
    else
      replacement = vim.api.nvim_create_buf(true, false)
      vim.api.nvim_win_set_buf(win, replacement)
    end
  end
  vim.api.nvim_buf_delete(buffer, { force = false })
  return true
end

return M
