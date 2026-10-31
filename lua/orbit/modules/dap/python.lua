-- Keep Python debugpy adapter paths platform-specific and independent of Python packages.
local M = {}

function M.venv_executable(name)
  local environment = vim.env.VIRTUAL_ENV
  if not environment or environment == "" then return nil end
  local win = vim.fn.has("win32") == 1
  return vim.fs.joinpath(
    vim.fs.normalize(environment), win and "Scripts" or "bin",
    name .. (win and ".exe" or "")
  )
end

function M.venv_python()
  return M.venv_executable(vim.fn.has("win32") == 1 and "pythonw" or "python")
end

return M
