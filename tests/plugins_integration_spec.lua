-- End-to-end Lazy demand, local Git checkout, and spec import without network.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)

local orbit = require("orbit")
local plugins = require("orbit.modules.plugins")
local temp = vim.fn.tempname()
local source = vim.fs.joinpath(temp, "source")
local installed = vim.fs.joinpath(temp, "data", "lazy.nvim")
local lockfile = vim.fs.joinpath(temp, "lazy-lock.json")
local recorded = vim.fs.joinpath(temp, "loaded.txt")
local replay = vim.fs.joinpath(temp, "replayed.txt")
local features = vim.fs.joinpath(temp, "features.txt")
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

local function fixture(version)
  return string.format([=[
return {
  setup = function(specs, config)
    assert(specs[1].import == "plugins")
    assert(config.defaults.lazy == true)
    local items = require(specs[1].import)
    local icons, gitsigns_spec
    for _, entry in ipairs(items) do
      if entry[1] == "nvim-mini/mini.icons" then icons = entry end
      if entry[1] == "lewis6991/gitsigns.nvim" then gitsigns_spec = entry end
    end
    assert(icons and gitsigns_spec)
    -- Emulate Lazy's feature configuration boundary without fetching plugins.
    package.preload["mini.icons"] = function()
      return {
        setup = function(options)
          assert(vim.deep_equal(options, {}))
          vim.fn.writefile({"icons.setup"}, %q, "a")
        end,
        mock_nvim_web_devicons = function()
          vim.fn.writefile({"icons.mock"}, %q, "a")
        end,
      }
    end
    icons.config()
    package.loaded["mini.icons"] = nil
    package.preload["mini.icons"] = nil
    local gitsigns = {
      setup = function(options)
        assert(options.signs.change.text == "C")
        assert(options.signs.add.text == "▎")
        assert(options.signs_staged.add.text == "+")
        vim.fn.writefile({"gitsigns.setup"}, %q, "a")
      end,
    }
    gitsigns.setup(gitsigns_spec.opts)
    vim.fn.writefile({%q}, %q)
    vim.api.nvim_create_autocmd("BufReadPre", {
      group = vim.api.nvim_create_augroup("OrbitIntegrationLazyRead", {clear = true}),
      callback = function()
        vim.fn.writefile({"replayed"}, %q, "a")
      end,
    })
  end,
}
]=], features, features, features, version, recorded, replay)
end

vim.fn.mkdir(vim.fs.joinpath(source, "lua", "lazy"), "p")
git({ "init", "-b", "stable", source })
local entry = vim.fs.joinpath(source, "lua", "lazy", "init.lua")
local function commit_version(value)
  vim.fn.writefile(vim.split(fixture(value), "\n", {plain=true}), entry)
  git({ "-C", source, "add", "." })
  git({ "-C", source, "-c", "user.name=orbit.nvim",
    "-c", "user.email=tests@example.invalid", "commit", "-m", value })
  return git({ "-C", source, "rev-parse", "HEAD" })
end

local locked = commit_version("locked")
local stable = commit_version("newer")
assert(locked ~= stable)
vim.fn.writefile({ vim.json.encode({
  ["lazy.nvim"] = { commit = locked },
}) }, lockfile)

local earlier = 0
vim.api.nvim_create_autocmd("BufReadPre", {
  group = vim.api.nvim_create_augroup("OrbitIntegrationOldRead", {clear = true}),
  callback = function()
    earlier = earlier + 1
  end,
})

check("setup is hermetic and defers Git clone until demanded", function()
  orbit.setup({ modules = { plugins = {
    enabled = true,
    bootstrap = true,
    path = installed,
    source = source,
    lockfile = lockfile,
  }, git = { marks = { change = "C" }, staged = { add = "+" } } } })
  assert(plugins.status() == "pending")
  assert(vim.uv.fs_stat(installed) == nil)
  assert(vim.fn.filereadable(recorded) == 0)
  assert(vim.fn.filereadable(features) == 0)
end)

check("first file-read demand clones locked revision and imports real specs", function()
  local buffer = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_exec_autocmds("BufReadPre", {buffer=buffer, modeline=false})
  assert(plugins.status() == "loaded")
  assert(git({ "-C", installed, "rev-parse", "HEAD" }) == locked)
  assert(vim.deep_equal(vim.fn.readfile(recorded), {"locked"}))
  assert(vim.deep_equal(vim.fn.readfile(features),
    {"icons.setup", "icons.mock", "gitsigns.setup"}))
  assert(vim.deep_equal(vim.fn.readfile(replay), {"replayed"}))
  assert(earlier == 1, "earlier observer should run once")
end)

check("later demand runs file observers but not Lazy setup again", function()
  local buffer = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_exec_autocmds("BufReadPre", {buffer=buffer, modeline=false})
  assert(vim.deep_equal(vim.fn.readfile(recorded), {"locked"}))
  assert(vim.deep_equal(vim.fn.readfile(replay), {"replayed", "replayed"}))
  assert(vim.deep_equal(vim.fn.readfile(features),
    {"icons.setup", "icons.mock", "gitsigns.setup"}))
  assert(earlier == 2)
end)

vim.fn.delete(temp, "rf")
print(string.format("%d first-demand integration tests passed.", count))
