-- Bound compatibility fixes for the upstream mouse-menu lifetime.
local M = {}
local installed = false

---@class Orbit.MenuMapping
---@field lhs string
---@field rhs? string
---@field callback? function
---@field noremap integer
---@field silent integer
---@field expr integer
---@field nowait integer
---@field desc? string
---@field buffer integer

---@class Orbit.MenuOwnedMap
---@field mode string
---@field lhs string
---@field buffer? integer
---@field previous? Orbit.MenuMapping
---@field callback function

---@class Orbit.MenuSession: Orbit.MenuSource
---@field maps Orbit.MenuOwnedMap[]

---@type Orbit.MenuSession?
local active

---@param mode string
---@param lhs string
---@param buffer? integer
---@return Orbit.MenuMapping?
local function mapping(mode, lhs, buffer)
  local maps = buffer and vim.api.nvim_buf_get_keymap(buffer, mode) or vim.api.nvim_get_keymap(mode)
  local key = vim.keycode(lhs)
  for _, value in ipairs(maps) do
    if vim.keycode(value.lhs) == key then return value end
  end
end

local function release()
  local session = active
  active = nil
  if not session then return end
  for _, owned in ipairs(session.maps) do
    if not owned.buffer or vim.api.nvim_buf_is_valid(owned.buffer) then
      local current = mapping(owned.mode, owned.lhs, owned.buffer)
      if current and current.callback == owned.callback then
        vim.keymap.del(owned.mode, owned.lhs, { buffer = owned.buffer })
        local before = owned.previous
        if before then
          local function restore() vim.fn.mapset(owned.mode, false, before) end
          if owned.buffer then vim.api.nvim_buf_call(owned.buffer, restore) else restore() end
        end
      end
    end
  end
end

---Close only upstream menu buffers, then release temporary input ownership.
function M.close()
  local state = package.loaded["menu.state"]
  local buffers = vim.deepcopy(state and state.bufids or {})
  local buffer = buffers[1]
  local closed = false
  if buffer and vim.api.nvim_buf_is_valid(buffer) then
    local quit = mapping("n", "q", buffer)
    if quit and type(quit.callback) == "function" then closed = pcall(quit.callback) end
  end
  local remaining = vim.tbl_filter(vim.api.nvim_buf_is_valid, buffers)
  if state and (not closed or #state.bufids > 0 or #remaining > 0) then
    -- Upstream allocates buffers and renders before installing close mappings.
    -- A failed render must not leave an unclosable session behind.
    local volt_state, events = package.loaded["volt.state"], package.loaded["volt.events"]
    for _, id in ipairs(buffers) do
      if vim.api.nvim_buf_is_valid(id) then
        local ok, err = pcall(vim.api.nvim_buf_delete, id, { force = true })
        if not ok then vim.notify(tostring(err), vim.log.levels.ERROR, { title = "Context Menu" }) end
      end
      if volt_state then volt_state[id] = nil end
      if events then
        events.bufs = vim.tbl_filter(function(value) return value ~= id end, events.bufs)
      end
    end
    state.bufs, state.bufids, state.nested_menu, state.config = {}, {}, "", nil
    if active and vim.api.nvim_win_is_valid(active.win)
      and vim.api.nvim_win_get_buf(active.win) == active.buf then
      vim.api.nvim_set_current_win(active.win)
    end
  end
  release()
end

---@param mode string
---@param lhs string
---@param buffer? integer
---@param callback function
---@param expr? boolean
local function own(mode, lhs, buffer, callback, expr)
  local session = assert(active)
  local previous = mapping(mode, lhs, buffer)
  vim.keymap.set(mode, lhs, callback, {
    buffer = buffer, expr = expr, silent = true, nowait = true,
    desc = "Context menu lifetime: " .. lhs,
  })
  session.maps[#session.maps + 1] = {
    mode = mode, lhs = lhs, buffer = buffer, previous = previous, callback = callback,
  }
end

local function own_input()
  local session = assert(active)
  if #session.maps > 0 then return end
  local function escape()
    vim.schedule(function() if active == session then M.close() end end)
    return "<Esc>"
  end
  local function click()
    vim.cmd.exec('"normal! \\<LeftMouse>"')
    local mouse = vim.fn.getmousepos()
    if active == session and (mouse.winid == 0
      or not vim.api.nvim_win_is_valid(mouse.winid)
      or vim.bo[vim.api.nvim_win_get_buf(mouse.winid)].filetype ~= "NvMenu") then
      M.close()
    end
  end
  for _, mode in ipairs({ "n", "x" }) do
    own(mode, "<Esc>", session.buf, escape, true)
    own(mode, "<LeftMouse>", nil, click)
    -- A buffer-local user binding must not bypass outside-click disposal.
    for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_loaded(buffer) and mapping(mode, "<LeftMouse>", buffer) then
        own(mode, "<LeftMouse>", buffer, click)
      end
    end
  end
end

---Install once at the restart-only Lazy config boundary.
function M.install()
  if installed then return end
  local mappings = require("menu.mappings")
  local auto_close = mappings.auto_close
  mappings.auto_close = function()
    if active then own_input() else auto_close() end
  end
  local group = vim.api.nvim_create_augroup("OrbitMenu", {})
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = group,
    callback = function()
      local session = active
      if not session then return end
      vim.schedule(function()
        if active ~= session then return end
        local state = package.loaded["menu.state"]
        if not state or #state.bufids == 0 then release() end
      end)
    end,
  })
  installed = true
end

---Use native right-click positioning before selecting the clicked buffer's items.
function M.open()
  M.close()
  local mouse = vim.fn.getmousepos()
  if mouse.winid == 0 or not vim.api.nvim_win_is_valid(mouse.winid) then return end
  vim.cmd.exec('"normal! \\<RightMouse>"')
  local buffer = vim.api.nvim_win_get_buf(mouse.winid)
  if vim.bo[buffer].filetype == "NvMenu" then return end
  vim.api.nvim_set_current_win(mouse.winid)
  active = { win = mouse.winid, buf = buffer, maps = {} }
  local ok, err = xpcall(function()
    local items = require("orbit.modules.menu.items")
    local entries = vim.bo[buffer].filetype == "NvimTree" and items.tree(active) or items.general(active)
    require("menu").open(entries, { mouse = true })
  end, debug.traceback)
  if not ok then
    pcall(M.close)
    vim.notify(tostring(err), vim.log.levels.ERROR, { title = "Context Menu" })
  end
end

return M
