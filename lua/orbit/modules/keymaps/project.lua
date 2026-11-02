-- Resolve the current file root without a shell dependency.
local M = {}

-- Keep the marker precedence, including Git worktree .git files.
local markers = {
  ".git", ".hg", ".svn", ".bzr",
  "package.json", "pyproject.toml", "setup.py", "requirements.txt",
  "Pipfile", "Cargo.toml", "go.mod", "composer.json", "Gemfile",
  "Makefile", "CMakeLists.txt", "meson.build", "build.gradle",
  "build.gradle.kts", "pom.xml", ".idea", ".vscode",
}

---Get the project root. Explicit paths do not use the current buffer's LSP.
---@param path? string
---@return string
function M.root(path)
  local filename = path or vim.api.nvim_buf_get_name(0)
  if path == nil then
    for _, client in ipairs(vim.lsp.get_clients({ bufnr = 0 })) do
      local directory = client.config and client.config.root_dir
      if type(directory) == "string" and directory ~= "" then
        return vim.fs.normalize(directory)
      end
    end
  end

  if filename == "" then return vim.fs.normalize(vim.fn.getcwd()) end
  local expanded = vim.fs.normalize(vim.fn.expand(filename))
  local directory = vim.fn.isdirectory(expanded) == 1
    and expanded or vim.fs.dirname(expanded)
  for _, marker in ipairs(markers) do
    local result = vim.fs.find(marker, { path = directory, upward = true })[1]
    if result then return vim.fs.dirname(result) end
  end
  return directory
end

function M.cd_to_root()
  vim.api.nvim_set_current_dir(M.root())
end

return M
