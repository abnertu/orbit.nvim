-- Build the upstream preview binary only at Lazy's explicit build boundary.
local M = {}

---@param windows boolean
---@param mac boolean
---@param machine string
---@return string
function M.platform_name(windows, mac, machine)
  if windows then return "win" end
  if mac then return machine == "arm64" and "macos-arm64" or "macos" end
  return "linux"
end

local function current_platform()
  return M.platform_name(vim.fn.has("win32") == 1, vim.fn.has("mac") == 1,
    vim.uv.os_uname().machine)
end

---@param directory string
---@param platform string
---@return string
function M.executable(directory, platform)
  return vim.fs.joinpath(directory, "app", "bin",
    "markdown-preview-" .. platform .. (platform == "win" and ".exe" or ""))
end

---@param plugin {dir: string}
---@param timeout? integer
function M.build_preview(plugin, timeout)
  assert(plugin and type(plugin.dir) == "string" and plugin.dir ~= "",
    "Markdown preview plugin directory is required")
  local info = vim.json.decode(table.concat(vim.fn.readfile(
    vim.fs.joinpath(plugin.dir, "package.json")), "\n"))
  local version = info.version
  assert(type(version) == "string" and
    version:match("^[0-9A-Za-z][0-9A-Za-z%.%+%-]*$"),
    "Markdown preview package version is invalid")

  local platform = current_platform()
  local executable = M.executable(plugin.dir, platform)
  local function installed()
    if not vim.uv.fs_stat(executable) then return false end
    local result = vim.system({ executable, "--version" }, { text = true }):wait(10000)
    return result.code == 0 and vim.trim(result.stdout or "") == version
  end
  if installed() then return end

  -- The relative .cmd path is required when Windows excludes cwd from PATH.
  local command = platform == "win"
      and { "cmd.exe", "/d", "/c", ".\\install.cmd", "v" .. version }
    or { "bash", "./install.sh", "v" .. version }
  local result = vim.system(command, {
    cwd = vim.fs.joinpath(plugin.dir, "app"), text = true,
  }):wait(timeout or 120000)
  assert(result.code == 0,
    "Markdown preview installation failed:\n" ..
    (result.stderr or "") .. (result.stdout or ""))
  assert(installed(),
    "Markdown preview installer did not produce the expected executable version")
end

return M
