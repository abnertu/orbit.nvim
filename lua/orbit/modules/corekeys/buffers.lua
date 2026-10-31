-- Buffer cycling follows the legacy tab-local order when available.
-- No plugin or global variable is required to load this module.
local M = {}

local function eligible(buffer)
  return type(buffer) == "number"
    and vim.api.nvim_buf_is_valid(buffer)
    and vim.api.nvim_buf_is_loaded(buffer)
    and vim.api.nvim_get_option_value("buflisted", { buf = buffer })
end

local function listed_buffers()
  local tab_buffers = vim.t.bufs
  if type(tab_buffers) == "table" and #tab_buffers > 0 then
    local valid = vim.tbl_filter(eligible, tab_buffers)
    if #valid > 0 then return valid end
  end

  return vim.tbl_filter(eligible, vim.api.nvim_list_bufs())
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
