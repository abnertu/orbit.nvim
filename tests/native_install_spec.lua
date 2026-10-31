-- Exercise a clean native pack/start install from an isolated local Git checkout.
-- This is a real package load, not an rtp:prepend of the source repository.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
local base = vim.fn.tempname() .. " orbit pack install with spaces"
local site = vim.fs.joinpath(base, "site")
local parent = vim.fs.joinpath(site, "pack", "orbit", "start")
local installed = vim.fs.joinpath(parent, "orbit.nvim")
local original_packpath = vim.o.packpath

local function run(argv)
  local result = vim.system(argv, { text = true, timeout = 120000 }):wait()
  assert(result.code == 0,
    "local package checkout failed: " .. tostring(result.stderr or result.stdout))
end

local ok, err = xpcall(function()
  assert(vim.fn.executable("git") == 1, "Git is required")
  assert(vim.fn.mkdir(parent, "p") == 1)
  run({ "git", "clone", "--local", "--quiet", root, installed })
  assert(vim.fn.filereadable(vim.fs.joinpath(installed,
    "lua", "orbit", "init.lua")) == 1)
  vim.opt.packpath:prepend(site)

  assert(package.loaded.orbit == nil, "orbit loaded before explicit packadd")
  vim.cmd.packadd("orbit.nvim")
  local orbit = require("orbit")
  local source = debug.getinfo(orbit.setup, "S").source
  assert(source:sub(1, 1) == "@", "Orbit setup is not loaded from a file")
  local path = vim.fs.normalize(source:sub(2))
  local dir = vim.fs.normalize(installed)
  assert(path:sub(1, #dir) == dir,
    "native package loaded the wrong source: " .. path)
  print("PASS isolated native pack/start checkout with explicit packadd")

  orbit.setup()
  local accepted = orbit.get_config()
  assert(type(accepted) == "table" and accepted.modules.plugins.enabled == false)
  assert(require("orbit.modules.plugins").status() == "disabled")
  assert(package.loaded.lazy == nil,
    "native package install must not download or import Lazy")
  assert(vim.api.nvim_get_commands({}).OrbitSettings ~= nil,
    "native installation did not register :OrbitSettings")
  assert(vim.fn.filereadable(vim.fs.joinpath(installed,
    "settings.schema.json")) == 1)
  orbit.setup()
  assert(vim.deep_equal(orbit.get_config(), accepted),
    "repeated initialization replaced accepted config")
  print("PASS installed init.lua setup, disabled plugin bootstrap and settings command")
end, debug.traceback)

vim.o.packpath = original_packpath
vim.fn.delete(base, "rf")
assert(ok, tostring(err))
print("Native package installation tests passed.")
