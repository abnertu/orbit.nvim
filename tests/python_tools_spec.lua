-- Test Pyright regeneration through its user command and real filesystem.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
local orbit = require("orbit")
local owner = require("orbit.modules.python_tools")
local runtime = require("orbit.modules.python_tools.runtime")
local original_cwd = vim.fn.getcwd()
local original_job = vim.fn.jobstart
local original_select = vim.ui.select
local original_notify = vim.notify
local project = vim.fn.tempname() .. " python project with spaces"
local done = 0
assert(vim.fn.mkdir(vim.fs.joinpath(project, "typings", "pkg"), "p") == 1)
local target = vim.fs.joinpath(project, "typings", "pkg")
assert(vim.fn.writefile({ "old stub" }, vim.fs.joinpath(target, "old.pyi")) == 0)

local function check(name, fn)
  local ok, err = xpcall(fn, debug.traceback)
  assert(ok, "FAIL " .. name .. "\n" .. tostring(err))
  done = done + 1
  print("PASS " .. name)
end
local function old_exists()
  return vim.fn.filereadable(vim.fs.joinpath(target, "old.pyi")) == 1
end
local function restore_old()
  if vim.fn.isdirectory(target) == 0 then assert(vim.fn.mkdir(target, "p") == 1) end
  assert(vim.fn.writefile({ "old stub" }, vim.fs.joinpath(target, "old.pyi")) == 0)
end
local function assert_no_backup()
  local scan = vim.uv.fs_scandir(vim.fs.joinpath(project, "typings"))
  while scan do
    local name = vim.uv.fs_scandir_next(scan)
    if not name then break end
    assert(not name:match("^%.orbit%-stub%-"), "backup leaked: " .. name)
  end
end

check("root setup owns command without importing a Python process", function()
  assert(package.loaded["orbit.modules.python_tools.runtime"])
  orbit.setup()
  assert(vim.api.nvim_get_commands({}).PyrightReCreateStub)
  assert(old_exists())
end)

check("spawn failure restores original directory after delayed selection", function()
  vim.api.nvim_set_current_dir(project)
  local choose, notified, seen
  vim.notify = function(msg) notified = msg end
  vim.ui.select = function(items, opts, cb)
    assert(vim.deep_equal(items, { "pkg" }))
    assert(opts.prompt == "Choose existing stub")
    choose = cb
  end
  vim.fn.jobstart = function(argv, opts)
    assert(vim.deep_equal(argv, { "pyright", "--createstub", "pkg" }))
    seen = opts.cwd
    return -1
  end
  vim.cmd.PyrightReCreateStub()
  local other = vim.fn.tempname() .. " second project"
  assert(vim.fn.mkdir(other, "p") == 1)
  vim.api.nvim_set_current_dir(other)
  choose("pkg")
  assert(vim.fs.normalize(seen) == vim.fs.normalize(project))
  assert(notified and notified:find("Could not start", 1, true))
  assert(old_exists())
  assert_no_backup()
  vim.api.nvim_set_current_dir(project)
  vim.fn.delete(other, "rf")
end)

check("nonzero exit restores old stub after partial generation", function()
  vim.ui.select = function(_, _, cb) cb("pkg") end
  local notified
  vim.notify = function(msg) notified = msg end
  vim.fn.jobstart = function(_, opts)
    assert(vim.fn.mkdir(target, "p") == 1)
    assert(vim.fn.writefile({ "partial" }, vim.fs.joinpath(target, "partial.pyi")) == 0)
    opts.on_exit(1, 3)
    return 1
  end
  vim.cmd.PyrightReCreateStub()
  assert(vim.wait(2000, function() return notified ~= nil end, 10))
  assert(notified:find("code 3", 1, true))
  assert(old_exists())
  assert(vim.fn.filereadable(vim.fs.joinpath(target, "partial.pyi")) == 0)
  assert_no_backup()
end)

check("successful replacement removes old stub only after new output exists", function()
  vim.fn.jobstart = function(_, opts)
    assert(vim.fn.mkdir(target, "p") == 1)
    assert(vim.fn.writefile({ "new stub" }, vim.fs.joinpath(target, "new.pyi")) == 0)
    opts.on_exit(1, 0)
    return 1
  end
  local notified
  vim.notify = function(msg) notified = msg end
  vim.cmd.PyrightReCreateStub()
  assert(vim.wait(2000, function() return notified ~= nil end, 10))
  assert(not old_exists())
  assert(vim.fn.filereadable(vim.fs.joinpath(target, "new.pyi")) == 1)
  assert_no_backup()
  restore_old()
end)

check("unsafe selections and concurrent requests are rejected", function()
  for _, name in ipairs({ ".", "..", "x/y", "x\\y", "x:y", ".orbit-stub-1" }) do
    local called
    assert(not runtime.recreate(project, name, function(ok, err)
      called = err
      assert(not ok)
    end))
    assert(called == "Invalid stub selection")
  end
  local exit
  vim.fn.jobstart = function(_, opts)
    exit = opts.on_exit
    return 1
  end
  assert(runtime.recreate(project, "pkg", function() end))
  local message
  assert(not runtime.recreate(project, "pkg", function(_, err)
    message = err
  end))
  assert(message == "This stub is already being regenerated")
  exit(1, 1)
  assert(vim.wait(2000, old_exists, 10))
  assert_no_backup()
end)

check("disable restores user commands and detects collisions", function()
  owner.setup({ recreate_stub = false })
  assert(vim.api.nvim_get_commands({}).PyrightReCreateStub == nil)
  vim.api.nvim_create_user_command("PyrightReCreateStub", function() end, {})
  local ok, err = pcall(owner.setup, { recreate_stub = true })
  assert(not ok and tostring(err):find("refusing to overwrite", 1, true))
  vim.api.nvim_del_user_command("PyrightReCreateStub")
  owner.setup({ recreate_stub = true })
  assert(vim.api.nvim_get_commands({}).PyrightReCreateStub)
end)

vim.api.nvim_set_current_dir(original_cwd)
vim.fn.jobstart = original_job
vim.ui.select = original_select
vim.notify = original_notify
vim.fn.delete(project, "rf")
print(string.format("%d Python stub recovery tests passed.", done))
