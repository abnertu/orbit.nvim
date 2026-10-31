local M = {}

---@class Orbit.EditorOptions
---@field enabled boolean
---@field number boolean
---@field relativenumber boolean
---@field expandtab boolean
---@field shiftwidth integer
---@field tabstop integer
---@field autoread boolean
---@field clipboard string
---@field cursorlineopt string
---@field fileformats string
---@field laststatus integer
---@field mouse string
---@field numberwidth integer
---@field ruler boolean
---@field showmode boolean
---@field signcolumn string
---@field smartindent boolean
---@field splitkeep string
---@field undofile boolean

local options = {
  "number",
  "relativenumber",
  "expandtab",
  "shiftwidth",
  "tabstop",
  "autoread",
  "clipboard",
  "cursorlineopt",
  "fileformats",
  "laststatus",
  "mouse",
  "numberwidth",
  "ruler",
  "showmode",
  "signcolumn",
  "smartindent",
  "splitkeep",
  "undofile",
}

local function normal_buffer(buffer)
  return vim.api.nvim_buf_is_valid(buffer)
    and vim.api.nvim_buf_is_loaded(buffer)
    and vim.bo[buffer].buftype == ""
end

local function normal_window(window)
  if not vim.api.nvim_win_is_valid(window) then
    return false
  end
  local buffer = vim.api.nvim_win_get_buf(window)
  return normal_buffer(buffer)
    and vim.api.nvim_win_get_config(window).relative == ""
end

-- Global defaults do not update an existing buffer or window's local option.
local function apply_option(name, value)
  vim.api.nvim_set_option_value(name, value, { scope = "global" })

  local scope = vim.api.nvim_get_option_info2(name, {}).scope
  if scope == "buf" then
    for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
      if normal_buffer(buffer) then
        vim.api.nvim_set_option_value(name, value, { buf = buffer })
      end
    end
  elseif scope == "win" then
    for _, window in ipairs(vim.api.nvim_list_wins()) do
      if normal_window(window) then
        vim.api.nvim_set_option_value(name, value, { win = window })
      end
    end
  end
end

---Capture the actual values, including existing local overrides.
---@return table
function M.capture()
  local snapshot = {}
  for _, name in ipairs(options) do
    local previous = {
      global = vim.api.nvim_get_option_value(name, { scope = "global" }),
      buffers = {},
      windows = {},
    }
    local scope = vim.api.nvim_get_option_info2(name, {}).scope
    if scope == "buf" then
      for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
        if normal_buffer(buffer) then
          previous.buffers[buffer] = vim.api.nvim_get_option_value(name, { buf = buffer })
        end
      end
    elseif scope == "win" then
      for _, window in ipairs(vim.api.nvim_list_wins()) do
        if normal_window(window) then
          previous.windows[window] = vim.api.nvim_get_option_value(name, { win = window })
        end
      end
    end
    snapshot[name] = previous
  end
  return snapshot
end

---Restore global defaults first, then each captured local override.
---@param snapshot table
function M.restore(snapshot)
  for _, name in ipairs(options) do
    local previous = assert(snapshot[name], "missing editor option snapshot: " .. name)
    vim.api.nvim_set_option_value(name, previous.global, { scope = "global" })
    for buffer, value in pairs(previous.buffers) do
      if normal_buffer(buffer) then
        vim.api.nvim_set_option_value(name, value, { buf = buffer })
      end
    end
    for window, value in pairs(previous.windows) do
      if normal_window(window) then
        vim.api.nvim_set_option_value(name, value, { win = window })
      end
    end
  end
end

---@param opts? Orbit.EditorOptions
---@param previous? Orbit.EditorOptions
function M.setup(opts, previous)
  opts = require("orbit.config").resolve_module("editor", opts)
  if not opts.enabled then
    return
  end

  for _, name in ipairs(options) do
    -- After the first application, update only fields that changed.
    if not previous or not previous.enabled or previous[name] ~= opts[name] then
      apply_option(name, opts[name])
    end
  end
end

return M
