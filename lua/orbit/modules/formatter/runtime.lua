-- One formatting operation per buffer; asynchronous completion owns cleanup.
local M = {}
local pending = {}

function M.is_formatting(buf)
  return pending[buf] ~= nil
end

---@param buf? integer
---@return boolean
function M.format(buf)
  buf = buf and buf ~= 0 and buf or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(buf) then
    return false
  end
  if pending[buf] then
    vim.notify("This buffer is already being formatted", vim.log.levels.WARN)
    return false
  end

  local cleanup
  local autocmd = vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = buf,
    once = true,
    callback = function()
      if cleanup then cleanup() end
    end,
  })
  pending[buf] = autocmd

  cleanup = function()
    if pending[buf] ~= autocmd then return end
    pending[buf] = nil
    pcall(vim.api.nvim_del_autocmd, autocmd)
  end

  local ok, started = pcall(function()
    return require("conform").format({
      async = true, bufnr = buf, quiet = true,
    }, function(failure)
      if pending[buf] ~= autocmd then return end
      cleanup()
      if failure then
        vim.notify("Formatting failed: " .. tostring(failure), vim.log.levels.ERROR)
      end
    end)
  end)
  if not ok then
    cleanup()
    vim.notify("Formatting failed: " .. tostring(started), vim.log.levels.ERROR)
    return false
  end
  -- Conform returns false (and may call back synchronously) when no formatter
  -- is available. Do not report that a formatting request was accepted.
  if started == false then
    cleanup()
    return false
  end
  return true
end

return M
