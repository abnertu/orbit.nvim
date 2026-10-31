-- Pure Lua buffer operations replacing tabufline and the destructive %bd|e#.
-- No external plugin import or implicit writes.
local M = {}

local function normal(buffer)
  return vim.api.nvim_buf_is_valid(buffer) and vim.bo[buffer].buftype == ""
end

local function protected(buffer)
  return vim.api.nvim_buf_is_loaded(buffer) and vim.bo[buffer].modified
end

local function listed_others(current)
  local result = {}
  for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
    if buffer ~= current and normal(buffer) and vim.bo[buffer].buflisted then
      result[#result + 1] = buffer
    end
  end
  return result
end

---Close the current normal buffer without discarding unsaved changes.
function M.close_current()
  local buffer = vim.api.nvim_get_current_buf()
  assert(normal(buffer), "cannot close a special buffer")
  assert(not protected(buffer), "buffer has unsaved changes: " .. buffer)
  vim.api.nvim_buf_delete(buffer, { force = false })
end

---Keep the current buffer and delete other listed normal buffers.
---Reject the entire operation when any candidate has unsaved edits.
---@return integer
function M.close_others()
  local current = vim.api.nvim_get_current_buf()
  assert(normal(current), "cannot clean buffers from a special buffer")
  local others = listed_others(current)
  for _, buffer in ipairs(others) do
    assert(not protected(buffer),
      "other buffer has unsaved changes: " .. buffer)
  end
  for _, buffer in ipairs(others) do
    vim.api.nvim_buf_delete(buffer, { force = false })
  end
  return #others
end

return M
