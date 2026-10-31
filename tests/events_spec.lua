-- Exercise owned Neovim events and their state during a failed transaction.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)

local orbit = require("orbit")
local commands = require("orbit.modules.commands")
local passed = 0

local function check(name, fn)
  local ok, err = xpcall(fn, debug.traceback)
  assert(ok, "FAIL " .. name .. "\n" .. tostring(err))
  passed = passed + 1
  print("PASS " .. name)
end

local function count(event)
  return #vim.api.nvim_get_autocmds({ group = "OrbitCoreEvents", event = event })
end

local function redraw_calls()
  local old, calls = vim.cmd.redrawstatus, 0
  vim.cmd.redrawstatus = function()
    calls = calls + 1
  end
  local ok, err = xpcall(function()
    vim.api.nvim_exec_autocmds("DiagnosticChanged", { modeline = false })
  end, debug.traceback)
  vim.cmd.redrawstatus = old
  assert(ok, tostring(err))
  return calls
end

check("startup registers only the owned core event callbacks", function()
  orbit.setup()
  assert(count("DiagnosticChanged") == 1)
  assert(count("VimEnter") == 2)
  assert(redraw_calls() == 1)
end)

check("reconfiguration does not stack autocommands", function()
  orbit.setup({ modules = { events = { diagnostics_redraw = false } } })
  assert(count("DiagnosticChanged") == 1)
  assert(count("VimEnter") == 2)
  assert(redraw_calls() == 0)
end)

check("a later failure restores the previous event settings", function()
  local accepted = orbit.get_config()
  local previous = commands.setup
  commands.setup = function(opts)
    previous(opts)
    error("injected command failure")
  end
  local ok, err = pcall(orbit.setup, { modules = {
    events = { diagnostics_redraw = true },
    commands = { name = "OrbitBroken" },
  } })
  commands.setup = previous
  assert(not ok and tostring(err):find("injected command failure", 1, true))
  assert(vim.deep_equal(orbit.get_config(), accepted))
  assert(redraw_calls() == 0)
  assert(count("DiagnosticChanged") == 1)
  assert(vim.api.nvim_get_commands({}).OrbitBroken == nil)
end)

check("disabling event behavior keeps callbacks inert", function()
  orbit.setup({ modules = { events = { enabled = false } } })
  assert(redraw_calls() == 0)
  assert(count("DiagnosticChanged") == 1)
  assert(count("VimEnter") == 2)
end)

check("reenabling restores diagnostic redraw without duplicates", function()
  orbit.setup({ modules = { events = { diagnostics_redraw = true } } })
  assert(redraw_calls() == 1)
  assert(count("DiagnosticChanged") == 1)
end)

check("directory startup event changes cwd and deletes its argument buffer", function()
  local oldcwd = vim.fn.getcwd()
  local directory = vim.fn.tempname()
  vim.fn.mkdir(directory, "p")
  local buffer = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_set_current_buf(buffer)
  local ok, err = xpcall(function()
    vim.api.nvim_exec_autocmds("VimEnter", {
      pattern = directory,
      modeline = false,
    })
    local actual = vim.fs.normalize(vim.fn.getcwd())
    local expected = vim.fs.normalize(directory)
    if vim.fn.has("win32") == 1 then
      actual, expected = actual:lower(), expected:lower()
    end
    assert(actual == expected, "directory argument did not change cwd")
    assert(vim.wait(1000, function()
      return not vim.api.nvim_buf_is_valid(buffer)
    end, 10), "argument buffer was not removed")
  end, debug.traceback)
  vim.api.nvim_set_current_dir(oldcwd)
  vim.fn.delete(directory, "rf")
  assert(ok, tostring(err))
end)

print(string.format("%d core event tests passed.", passed))
