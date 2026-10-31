-- Shared SQLFluff project context for Conform and nvim-lint.
-- This adapter owns tool arguments, not module settings.
local M = {}

local source = debug.getinfo(1, "S").source:sub(2)
local root = vim.fn.fnamemodify(source, ":p:h:h:h")
M.fallback_config = vim.fs.joinpath(root, "config", "sqlfluff.cfg")

local config_names = {
  ".sqlfluff", "pep8.ini", "pyproject.toml", "setup.cfg", "tox.ini",
}
local project_markers = {
  ".git", ".hg", ".svn", ".bzr", "package.json", "pyproject.toml",
  "setup.py", "requirements.txt", "Pipfile", "Cargo.toml", "go.mod",
  "composer.json", "Gemfile", "Makefile", "CMakeLists.txt",
  "meson.build", "build.gradle", "build.gradle.kts", "pom.xml",
  ".idea", ".vscode",
}

local function directory(filename)
  if not filename or filename == "" then
    return vim.fn.getcwd()
  end
  return vim.fn.fnamemodify(filename, ":p:h")
end

local function declares_sqlfluff(path)
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok then return false end
  local toml = vim.fs.basename(path) == "pyproject.toml"
  for _, line in ipairs(lines) do
    if toml then
      if line:match("^%s*%[tool%.sqlfluff%]") or
        line:match("^%s*%[tool%.sqlfluff%.")
      then
        return true
      end
    elseif line:match("^%s*%[sqlfluff%]") or
      line:match("^%s*%[sqlfluff:")
    then
      return true
    end
  end
  return false
end

---@param filename? string
---@return string?
function M.find_config(filename)
  local candidates = vim.fs.find(config_names, {
    path = directory(filename), upward = true, type = "file",
    limit = math.huge,
  })
  for _, path in ipairs(candidates) do
    if declares_sqlfluff(path) then return path end
  end
end

---@param filename? string
---@return string
function M.cwd(filename)
  local start = directory(filename)
  -- Keep the legacy marker priority: a repository root wins over a
  -- closer package manifest when both are present.
  for _, marker in ipairs(project_markers) do
    local found = vim.fs.find(marker, {
      path = start, upward = true, limit = 1,
    })
    if found[1] then return vim.fs.dirname(found[1]) end
  end
  return start
end

local function args(operation, filename)
  local result = { operation }
  if operation == "lint" then
    result[#result + 1] = "--format=json"
  end
  if filename and filename ~= "" then
    vim.list_extend(result, { "--stdin-filename", filename })
  end
  if not M.find_config(filename) then
    vim.list_extend(result, { "--config", M.fallback_config })
  end
  result[#result + 1] = "-"
  return result
end

---@param filename? string
---@return string[]
function M.format_args(filename)
  return args("format", filename)
end

---@param filename? string
---@return string[]
function M.lint_args(filename)
  return args("lint", filename)
end

return M
