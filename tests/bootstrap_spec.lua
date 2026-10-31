-- Exercise a local Git source; CI must never fetch plugins from the network.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
local bootstrap = require("orbit.lazy_bootstrap")
local temp = vim.fn.tempname()
local source = vim.fs.joinpath(temp, "source")
local destination = vim.fs.joinpath(temp, "data", "lazy.nvim")
local lockfile = vim.fs.joinpath(temp, "lazy-lock.json")
local count = 0

local function git(args)
  local command = { "git" }
  vim.list_extend(command, args)
  local result = vim.system(command, { text = true }):wait(15000)
  assert(result.code == 0,
    table.concat(command, " ") .. ": " .. tostring(result.stderr))
  return vim.trim(result.stdout)
end

local function check(name, fn)
  local ok, err = xpcall(fn, debug.traceback)
  assert(ok, "FAIL " .. name .. "\n" .. tostring(err))
  count = count + 1
  print("PASS " .. name)
end

vim.fn.mkdir(vim.fs.joinpath(source, "lua", "lazy"), "p")
git({ "init", "-b", "stable", source })
local module_path = vim.fs.joinpath(source, "lua", "lazy", "init.lua")
local function commit_module(content)
  vim.fn.writefile({ content }, module_path)
  git({ "-C", source, "add", "." })
  git({ "-C", source, "-c", "user.name=orbit.nvim",
    "-c", "user.email=tests@example.invalid", "commit", "-m", "fixture" })
  return git({ "-C", source, "rev-parse", "HEAD" })
end

local locked = commit_module("return { version = 'locked' }")
local newer = commit_module("return { version = 'newer' }")
assert(locked ~= newer)
vim.fn.writefile({ vim.json.encode({
  ["lazy.nvim"] = { commit = locked },
}) }, lockfile)

local function options(path)
  return {
    path = path or destination,
    bootstrap = true,
    source = source,
    lockfile = lockfile,
  }
end

check("absent checkout without bootstrap never contacts Git", function()
  local requested = options()
  requested.bootstrap = false
  local ok, err = pcall(bootstrap.ensure, requested)
  assert(not ok and tostring(err):find("not installed", 1, true))
  assert(vim.uv.fs_stat(destination) == nil)
end)

check("first checkout uses locked commit instead of newer stable", function()
  local chosen = bootstrap.ensure(options())
  assert(vim.fs.normalize(chosen) == vim.fs.normalize(destination))
  assert(git({ "-C", chosen, "rev-parse", "HEAD" }) == locked)
  assert(table.concat(vim.fn.readfile(
    vim.fs.joinpath(chosen, "lua", "lazy", "init.lua")), "\n"):
      find("locked", 1, true))
end)

check("existing checkout is preserved without external commands", function()
  local settings = options()
  settings.source = vim.fs.joinpath(temp, "nonexistent")
  settings.lockfile = vim.fs.joinpath(temp, "missing")
  assert(bootstrap.ensure(settings) == vim.fs.normalize(destination))
  assert(git({ "-C", destination, "rev-parse", "HEAD" }) == locked)
end)

check("bad lock revisions fail without leaving a checkout", function()
  local invalid_path = vim.fs.joinpath(temp, "data", "broken")
  vim.fn.writefile({ vim.json.encode({
    ["lazy.nvim"] = { commit = "not-a-commit" },
  }) }, lockfile)
  local ok, err = pcall(bootstrap.ensure, options(invalid_path))
  assert(not ok and tostring(err):find("invalid lazy.nvim commit", 1, true))
  assert(vim.uv.fs_stat(invalid_path) == nil)
end)

check("unknown locked revisions fail and remove partial clones", function()
  local missing_commit_path = vim.fs.joinpath(temp, "data", "missing-commit")
  vim.fn.writefile({ vim.json.encode({
    ["lazy.nvim"] = { commit = string.rep("0", 40) },
  }) }, lockfile)
  local ok, err = pcall(bootstrap.ensure, options(missing_commit_path))
  assert(not ok and tostring(err):find("locked Lazy revision", 1, true))
  assert(vim.uv.fs_stat(missing_commit_path) == nil)
end)

vim.fn.delete(temp, "rf")
print(string.format("%d locked-bootstrap tests passed.", count))
