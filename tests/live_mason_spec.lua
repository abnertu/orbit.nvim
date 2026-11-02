-- Install and uninstall a real Mason package through Orbit's Mason owner.
-- Requires Git and network. The Mason root and registry are isolated and pinned.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
local windows = vim.fn.has("win32") == 1
local pin = { "https://github.com/mason-org/mason.nvim.git", "2a6940af80375532e5e9e7c1f2fc6319a1b7a69d" }
local registry = "github:mason-org/mason-registry@2026-10-27-top-perch"
local package_name, package_version = "stylua", "v2.6.0"
local workspace = vim.fn.tempname() .. " live mason with spaces"

local function run(argv)
  local result = vim.system(argv, { text = true, timeout = 300000 }):wait()
  assert(result.code == 0, vim.inspect(argv) ..
    " failed: " .. tostring(result.stderr or "") .. tostring(result.stdout or ""))
  return result.stdout or ""
end

local function wait(predicate, message)
  assert(vim.wait(300000, predicate, 100), message)
end

local ok, err = xpcall(function()
  assert(vim.fn.executable("git") == 1, "Git is required")
  local plugin = vim.fs.joinpath(workspace, "mason.nvim")
  assert(vim.fn.mkdir(plugin, "p") == 1)
  run({ "git", "init", plugin })
  run({ "git", "-C", plugin, "fetch", "--depth", "1", pin[1], pin[2] })
  run({ "git", "-C", plugin, "checkout", "--detach", "FETCH_HEAD" })
  assert(vim.trim(run({ "git", "-C", plugin, "rev-parse", "HEAD" })) == pin[2])
  vim.opt.rtp:prepend(plugin)

  require("orbit").setup({ modules = { mason = { registry = registry } } })
  local spec = require("orbit.modules.mason").spec()[1]
  assert(spec[1] == "williamboman/mason.nvim", "Orbit did not declare Mason")
  local install_root = vim.fs.joinpath(vim.fs.normalize(vim.uv.fs_realpath(workspace)), "mason root")
  local path_before = vim.env.PATH
  require("mason").setup(vim.tbl_extend("force", spec.opts, { install_root_dir = install_root }))
  assert(vim.env.PATH == path_before, "Orbit's skip PATH mode changed PATH")
  assert(require("mason.settings").current.registries[1] == registry, "Orbit did not pass its registry")
  assert(vim.api.nvim_get_commands({}).MasonInstall, "Mason did not define MasonInstall")

  local registry_api = require("mason-registry")
  local refreshed = false
  registry_api.refresh(function() refreshed = true end)
  wait(function() return refreshed end, "Mason did not load the pinned registry")
  local package = registry_api.get_package(package_name)
  local installed, failure = false, nil
  package:install({ version = package_version }, function(success, result)
    installed, failure = success, not success and tostring(result) or nil
  end)
  wait(function() return installed or failure ~= nil end, package_name .. " install did not finish")
  assert(installed, package_name .. " install failed: " .. tostring(failure))
  local binary = vim.fs.joinpath(install_root, "bin", package_name .. (windows and ".cmd" or ""))
  if windows and not vim.uv.fs_stat(binary) then
    binary = vim.fs.joinpath(install_root, "bin", package_name .. ".exe")
  end
  assert(vim.uv.fs_stat(binary), "Mason did not link " .. binary)
  local version = vim.system({ binary, "--version" }, { text = true }):wait(30000)
  assert(version.code == 0 and version.stdout:find(package_version:sub(2), 1, true),
    "installed " .. package_name .. " reported " .. vim.inspect(version))
  print("PASS Mason installs " .. package_name .. " " .. package_version .. " into the isolated root")

  local removed = false
  package:uninstall({}, function(success) removed = success end)
  wait(function() return removed end, package_name .. " uninstall did not finish")
  assert(not package:is_installed(), package_name .. " is still installed")
  assert(not vim.uv.fs_stat(binary), "Mason left " .. binary)
  print("PASS Mason uninstalls " .. package_name .. " from the isolated root")
end, debug.traceback)

vim.fn.delete(workspace, "rf")
assert(ok, tostring(err))
print("Real Mason install integration passed.")
