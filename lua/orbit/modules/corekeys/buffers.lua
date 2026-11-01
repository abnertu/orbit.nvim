-- Buffer cycling follows the tab-local order owned by orbit.buffers.
-- No plugin or global variable is required to load this module.
local M = {}

local function listed_buffers()
  return require("orbit.buffers").list()
end

local function current_index(buffers)
  local current = vim.api.nvim_get_current_buf()
  for index, buffer in ipairs(buffers) do
    if buffer == current then return index end
  end
end

function M.next()
  local buffers = listed_buffers()
  if #buffers == 0 then return end
  local index = current_index(buffers) or 0
  vim.api.nvim_set_current_buf(buffers[index == #buffers and 1 or index + 1])
end

function M.prev()
  local buffers = listed_buffers()
  if #buffers == 0 then return end
  local index = current_index(buffers) or 1
  vim.api.nvim_set_current_buf(buffers[index == 1 and #buffers or index - 1])
end

return M
