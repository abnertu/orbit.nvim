-- Explicit file-conversion actions preserved from the legacy leader keys.
-- No writes or reloads occur during module setup.
local M = {}

local function require_file()
  local name = vim.api.nvim_buf_get_name(0)
  assert(name ~= "", "file conversion requires a named buffer")
end

---Reload a DOS line-ending file and write it using Unix line endings.
function M.dos_to_unix()
  require_file()
  vim.cmd("edit ++ff=dos")
  vim.bo.fileformat = "unix"
  vim.cmd.write()
end

---Reload a Big5-encoded file and write its contents as UTF-8.
function M.big5_to_utf8()
  require_file()
  vim.cmd("edit ++enc=big5")
  vim.bo.fileencoding = "utf-8"
  vim.cmd.write()
end

return M
