-- Verify restart-only settings are deferred without blocking safe live updates.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)

local orbit = require("orbit")
local events = require("orbit.modules.events")
local commands = require("orbit.modules.commands")
local path = vim.fn.tempname() .. ".json"
local passed = 0

local function write(options)
  assert(vim.fn.writefile({ vim.json.encode(options) }, path) == 0)
end

local function check(name, fn)
  local ok, err = xpcall(fn, debug.traceback)
  if not ok then
    vim.fn.delete(path)
    error("FAIL " .. name .. "\n" .. tostring(err), 0)
  end
  passed = passed + 1
  print("PASS " .. name)
end

check("first saved setup applies startup-only settings", function()
  write({ modules = { events = {
    startup_buffer = false,
    directory_argument = false,
  } } })
  local ok, err = orbit.setup_from_file(path)
  assert(ok, tostring(err))
  assert(events.capture().active.startup_buffer == false)
  assert(events.capture().active.directory_argument == false)
  assert(vim.tbl_isempty(orbit.get_pending_restart()))
end)

check("reload applies safe fields and defers startup-only changes", function()
  write({ modules = { events = {
    startup_buffer = true,
    directory_argument = true,
    diagnostics_redraw = false,
  } } })
  local ok, err = orbit.reload_from_file(path)
  assert(ok, tostring(err))
  local effective = orbit.get_config().modules.events
  assert(effective.startup_buffer == false)
  assert(effective.directory_argument == false)
  assert(effective.diagnostics_redraw == false)
  assert(vim.deep_equal(effective, events.capture().active))
  local pending = orbit.get_pending_restart()
  assert(pending["orbit.modules.events.startup_buffer"] == true)
  assert(pending["orbit.modules.events.directory_argument"] == true)
  assert(vim.tbl_count(pending) == 2)
end)

check("repeated reload does not reactivate unchanged effective modules", function()
  local previous = events.setup
  events.setup = function()
    error("unchanged event module must not reactivate")
  end
  local ok, err = orbit.reload_from_file(path)
  events.setup = previous
  assert(ok, tostring(err))
  assert(vim.tbl_count(orbit.get_pending_restart()) == 2)
end)

check("invalid settings preserve effective and pending state", function()
  local effective = orbit.get_config()
  local pending = orbit.get_pending_restart()
  assert(vim.fn.writefile({ '{"modules":{"events":{"startup_buffer":3}}}' }, path) == 0)
  local ok, err = orbit.reload_from_file(path)
  assert(not ok and type(err) == "string")
  assert(vim.deep_equal(orbit.get_config(), effective))
  assert(vim.deep_equal(orbit.get_pending_restart(), pending))
end)

check("failed live activation restores effective and pending state", function()
  local effective = orbit.get_config()
  local pending = orbit.get_pending_restart()
  write({ modules = {
    events = {
      startup_buffer = true,
      directory_argument = true,
      diagnostics_redraw = true,
    },
    commands = { name = "OrbitRestartBroken" },
  } })
  local previous = commands.setup
  commands.setup = function(opts)
    previous(opts)
    error("injected restart reload failure")
  end
  local ok, err = orbit.reload_from_file(path)
  commands.setup = previous
  assert(not ok and tostring(err):find("injected restart reload failure", 1, true))
  assert(vim.deep_equal(orbit.get_config(), effective))
  assert(vim.deep_equal(orbit.get_pending_restart(), pending))
  assert(vim.deep_equal(events.capture().active, effective.modules.events))
  assert(vim.api.nvim_get_commands({}).OrbitRestartBroken == nil)
end)

check("reverting pending fields clears the restart requirement", function()
  write({ modules = { events = {
    startup_buffer = false,
    directory_argument = false,
    diagnostics_redraw = false,
  } } })
  local ok, err = orbit.reload_from_file(path)
  assert(ok, tostring(err))
  assert(vim.tbl_isempty(orbit.get_pending_restart()))
end)

vim.fn.delete(path)
print(string.format("%d restart-only settings tests passed.", passed))
