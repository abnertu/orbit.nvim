-- Exercise Windows recovery ownership and safe ShaDa cleanup in Lua.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
local orbit = require("orbit")
local system = require("orbit.modules.system")
local shada = require("orbit.modules.system.shada")
local windows = vim.fn.has("win32") == 1
local passed = 0

local function check(label, fn)
  local ok, err = xpcall(fn, debug.traceback)
  assert(ok, "FAIL " .. label .. "\n" .. tostring(err))
  passed = passed + 1
  print("PASS " .. label)
end

local function exists(path)
  return vim.uv.fs_lstat(path) ~= nil
end

check("cleanup deletes only regular .tmp files", function()
  local dir = vim.fn.tempname() .. " shada with spaces"
  assert(vim.fn.mkdir(dir, "p") == 1)
  local function write(name)
    assert(vim.fn.writefile({ "fixture" }, vim.fs.joinpath(dir, name)) == 0)
  end
  write("main.shada")
  write("custom.shada")
  write("orphan.tmp")
  write("UPPER.TMP")
  write("not-a-tmp")
  assert(vim.fn.mkdir(vim.fs.joinpath(dir, "nested.tmp"), "p") == 1)

  local count, err = shada.clear({ dir, dir })
  assert(count == 2, tostring(err))
  assert(exists(vim.fs.joinpath(dir, "main.shada")))
  assert(exists(vim.fs.joinpath(dir, "custom.shada")))
  assert(exists(vim.fs.joinpath(dir, "not-a-tmp")))
  assert(exists(vim.fs.joinpath(dir, "nested.tmp")))
  assert(not exists(vim.fs.joinpath(dir, "orphan.tmp")))
  assert(not exists(vim.fs.joinpath(dir, "UPPER.TMP")))
  local again = shada.clear({ dir })
  assert(again == 0)
  vim.fn.delete(dir, "rf")
end)

check("missing directories are ignored and invalid paths fail", function()
  local dir = vim.fn.tempname() .. " missing shada"
  assert(shada.clear({ dir }) == 0)
  assert(vim.fn.writefile({ "not a directory" }, dir) == 0)
  local count, err = shada.clear({ dir })
  assert(count == nil and err:find("not a directory", 1, true))
  vim.fn.delete(dir)
end)

check("startup registers recovery only on Windows", function()
  orbit.setup()
  local command = vim.api.nvim_get_commands({}).ClearShada
  assert((command ~= nil) == windows)
  assert(package.loaded["orbit.modules.system.shada"] ~= nil)
end)

check("repeated setup never duplicates or overwrites recovery command", function()
  orbit.setup()
  assert((vim.api.nvim_get_commands({}).ClearShada ~= nil) == windows)
  if not windows then return end

  local snapshot = system.capture()
  system.setup({ enabled = false })
  assert(vim.api.nvim_get_commands({}).ClearShada == nil)
  vim.api.nvim_create_user_command("ClearShada", function() end, {})
  local ok, err = pcall(system.setup, { enabled = true })
  assert(not ok and tostring(err):find("refusing to overwrite", 1, true))
  assert(vim.api.nvim_get_commands({}).ClearShada ~= nil)
  vim.api.nvim_del_user_command("ClearShada")
  system.restore(snapshot)
  assert(vim.api.nvim_get_commands({}).ClearShada ~= nil)
end)

check("valid settings can disable the command without file changes", function()
  system.setup({ enabled = true, clear_shada = false })
  assert(vim.api.nvim_get_commands({}).ClearShada == nil)
  system.setup({ enabled = true })
  assert((vim.api.nvim_get_commands({}).ClearShada ~= nil) == windows)
end)

print(string.format("%d Windows ShaDa recovery tests passed.", passed))
