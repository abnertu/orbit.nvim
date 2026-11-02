-- Own LSP navigation only in attached buffers; keep native keys elsewhere.
local M = {}
local active = false
---@type integer?
local group
---@type table<integer, table<string, Orbit.NavigationOwned>>
local owned = {}
local group_name = "OrbitLspNavigation"
local actions = {
  gd = "definition",
  gD = "declaration",
  gI = "implementation",
  gy = "type_definition",
  gR = "references",
}

---@param buffer integer
---@param key string
---@return Orbit.NavigationBinding|false
local function mapping(buffer, key)
  return vim.api.nvim_buf_call(buffer, function()
    local item = vim.fn.maparg(key, "n", false, true)
    return item.buffer == 1 and item or false
  end)
end

---@param buffer integer
---@param key string
---@param previous Orbit.NavigationBinding|false
local function restore_mapping(buffer, key, previous)
  pcall(vim.keymap.del, "n", key, { buffer = buffer })
  if not previous then
    return
  end
  vim.api.nvim_buf_call(buffer, function()
    vim.fn.mapset("n", false, previous)
  end)
end

---@param buffer integer
local function release(buffer)
  if vim.api.nvim_buf_is_valid(buffer) then
    for key, entry in pairs(owned[buffer] or {}) do
      local current = mapping(buffer, key)
      if current and current.callback == entry.callback then
        restore_mapping(buffer, key, entry.previous)
      end
    end
  end
  owned[buffer] = nil
end

---@param buffer integer
local function refresh(buffer)
  if not vim.api.nvim_buf_is_valid(buffer) then
    owned[buffer] = nil
    return
  end
  if not active then
    return
  end
  if #vim.lsp.get_clients({ bufnr = buffer }) == 0 then
    release(buffer)
    return
  end
  owned[buffer] = owned[buffer] or {}
  for key, action in pairs(actions) do
    if not owned[buffer][key] then
      local callback = function()
        vim.lsp.buf[action]()
      end
      owned[buffer][key] = { previous = mapping(buffer, key), callback = callback }
      vim.keymap.set("n", key, callback, {
        buffer = buffer,
        silent = true,
        nowait = key == "gR",
        desc = "LSP " .. action:gsub("_", " "),
      })
    end
  end
end

local function sync_group()
  if not active then
    if group then
      vim.api.nvim_del_augroup_by_id(group)
      group = nil
    end
    return
  end
  if group then
    return
  end
  local exists, entries = pcall(vim.api.nvim_get_autocmds, { group = group_name })
  assert(
    not exists or #entries == 0,
    "refusing to overwrite an existing " .. group_name .. " group"
  )
  group = vim.api.nvim_create_augroup(group_name, {})
  vim.api.nvim_create_autocmd("LspAttach", {
    group = group,
    ---@param event vim.api.keyset.create_autocmd.callback_args
    callback = function(event)
      refresh(event.buf)
    end,
    desc = "Install Orbit navigation for an attached LSP buffer",
  })
  vim.api.nvim_create_autocmd("LspDetach", {
    group = group,
    ---@param event vim.api.keyset.create_autocmd.callback_args
    callback = function(event)
      vim.schedule(function()
        refresh(event.buf)
      end)
    end,
    desc = "Restore navigation after the last LSP client detaches",
  })
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = group,
    ---@param event vim.api.keyset.create_autocmd.callback_args
    callback = function(event)
      owned[event.buf] = nil
    end,
    desc = "Release navigation ownership for deleted buffers",
  })
end

---@return Orbit.NavigationSnapshot
function M.capture()
  local buffers, current = {}, {}
  for buffer in pairs(owned) do
    buffers[buffer] = true
  end
  for _, client in ipairs(vim.lsp.get_clients()) do
    for buffer in pairs(client.attached_buffers) do
      buffers[buffer] = true
    end
  end
  for buffer in pairs(buffers) do
    if vim.api.nvim_buf_is_valid(buffer) then
      current[buffer] = {}
      for key in pairs(actions) do
        current[buffer][key] = mapping(buffer, key)
      end
    end
  end
  return { active = active, owned = vim.deepcopy(owned), current = current }
end

---@param snapshot Orbit.NavigationSnapshot
function M.restore(snapshot)
  for _, buffer in ipairs(vim.tbl_keys(owned)) do
    release(buffer)
  end
  for buffer, entries in pairs(snapshot.current) do
    if vim.api.nvim_buf_is_valid(buffer) then
      for key, previous in pairs(entries) do
        restore_mapping(buffer, key, previous)
      end
    end
  end
  active, owned = snapshot.active, vim.deepcopy(snapshot.owned)
  sync_group()
end

---@param enabled boolean
function M.setup(enabled)
  active = enabled
  sync_group()
  if not active then
    for _, buffer in ipairs(vim.tbl_keys(owned)) do
      release(buffer)
    end
    return
  end
  for _, client in ipairs(vim.lsp.get_clients()) do
    for buffer in pairs(client.attached_buffers) do
      refresh(buffer)
    end
  end
end

return M
