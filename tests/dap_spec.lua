-- DAP debugpy, Hangar state and UI callbacks through real module entry points.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
local orbit = require("orbit")
local owner = require("orbit.modules.dap")
local runtime = require("orbit.modules.dap.runtime")
local definitions = require("orbit.modules.dap.definitions")
local passed = 0
local function check(name, fn)
  local ok, err = xpcall(fn, debug.traceback)
  assert(ok, "FAIL " .. name .. "\n" .. tostring(err))
  passed = passed + 1
  print("PASS " .. name)
end

check("DAP import is inert and retains the Windows-capable fork and keys", function()
  assert(#owner.spec() == 0)
  orbit.setup()
  local specs = owner.spec()
  assert(#specs == 2)
  assert(specs[1][1] == "Orbit-Lua/nvim-dap")
  assert(#specs[1].keys == 8)
  assert(specs[1].keys[1][1] == "<leader>dt")
  assert(specs[1].keys[8][1] == "<leader>do")
  assert(specs[2][1] == "rcarriga/nvim-dap-ui")
  assert(specs[2].dependencies[2] == "nvim-neotest/nvim-nio")
  assert(specs[2].keys[1][1] == "<leader>du")
  assert(package.loaded.dap == nil)
end)

local opts = orbit.get_config().modules.dap
local defs = definitions.build(opts)
local python = defs.adapters.python

check("Python attach keeps the default server host and port", function()
  local received
  python(function(spec) received = spec end, { request = "attach" })
  assert(received.type == "server")
  assert(received.host == "127.0.0.1" and received.port == "8001")
  python(function(spec) received = spec end, {
    request = "attach", connect = { host = "localhost", port = "5432" },
  })
  assert(received.host == "localhost" and received.port == "5432")
end)

check("launch without an active venv does not start an adapter", function()
  local original, warnings = vim.env.VIRTUAL_ENV, {}
  vim.env.VIRTUAL_ENV = nil
  local old_notify = vim.notify
  vim.notify = function(message, level)
    assert(level == vim.log.levels.WARN)
    warnings[#warnings + 1] = message
  end
  local called = false
  python(function() called = true end, { request = "launch" })
  vim.notify = old_notify
  vim.env.VIRTUAL_ENV = original
  assert(not called and #warnings == 1)
  assert(warnings[1]:find("virtual environment", 1, true))
end)

check("Python launch chooses platform-aware virtual environment executables", function()
  local original = vim.env.VIRTUAL_ENV
  local environment = vim.fn.tempname()
  local is_win = vim.fn.has("win32") == 1
  local folder = vim.fs.joinpath(environment, is_win and "Scripts" or "bin")
  vim.fn.mkdir(folder, "p")
  local suffix = is_win and ".exe" or ""
  vim.fn.writefile({ "" }, vim.fs.joinpath(folder, "debugpy" .. suffix))
  vim.env.VIRTUAL_ENV = environment
  local received
  local ok, err = pcall(python, function(spec)
    received = spec
  end, { request = "launch" })
  vim.env.VIRTUAL_ENV = original
  vim.fn.delete(environment, "rf")
  assert(ok, tostring(err))
  assert(received.type == "executable")
  assert(vim.deep_equal(received.args, { "-m", "debugpy.adapter" }))
  assert(received.command:find(is_win and "pythonw.exe" or "python", 1, true))
end)

local dap = {
  adapters = {}, configurations = {},
  listeners = {
    before = { terminate = {}, event_exited = {}, event_terminated = {} },
  },
}
local ui_calls = { setup = 0, toggle = 0, restart = 0, watched = 0, closed = 0 }

package.preload.dap = function()
  dap.restart = function() ui_calls.restart = ui_calls.restart + 1 end
  return dap
end
package.preload.dapui = function()
  return {
    setup = function() ui_calls.setup = ui_calls.setup + 1 end,
    toggle = function() ui_calls.toggle = ui_calls.toggle + 1 end,
    float_element = function(name, opts)
      assert(name == "watches" and opts.enter == true)
      ui_calls.watched = ui_calls.watched + 1
    end,
    close = function() ui_calls.closed = ui_calls.closed + 1 end,
  }
end

package.loaded.hangar = {}
package.preload["hangar.state"] = function()
  return {
    is_enabled = function(category, name)
      assert(category == "dap")
      return name == "python"
    end,
  }
end

check("Hangar enables only selected adapters and Python configurations", function()
  owner.spec()[1].config()
  assert(type(dap.adapters.python) == "function")
  assert(dap.adapters.coreclr == nil)
  assert(#dap.configurations.python == 2)
  assert(dap.configurations.python[1].program == "$" .. "{file}")
  owner.spec()[1].config()
  assert(#dap.configurations.python == 2)
  local text, hl = runtime.adapter_status(dap, "python")
  assert(text == "registered 2 cfg" and hl == "DiagnosticOk")
end)

check("adapter toggles do not create duplicates or delete unrelated adapters", function()
  dap.adapters.extra = function() end
  assert(runtime.apply_adapter(dap, "python", true, defs))
  assert(#dap.configurations.python == 2)
  assert(runtime.apply_adapter(dap, "python", false, defs))
  assert(dap.adapters.python == nil and dap.configurations.python == nil)
  assert(dap.adapters.extra ~= nil)
  assert(runtime.apply_adapter(dap, "python", true, defs))
  assert(#dap.configurations.python == 2)
end)

check("DAP UI listeners and shortcuts initialize exactly once", function()
  local item = owner.spec()[2]
  item.config(nil, {})
  item.config(nil, {})
  assert(ui_calls.setup == 1)
  item.keys[1][2]()
  item.keys[2][2]()
  item.keys[3][2]()
  assert(ui_calls.toggle == 1 and ui_calls.restart == 1 and ui_calls.watched == 1)
  dap.listeners.before.terminate.orbit_dapui()
  dap.listeners.before.event_exited.orbit_dapui()
  assert(ui_calls.closed == 2)
end)

check("Hangar adapter options point to the same DAP definitions", function()
  local h = require("orbit.modules.hangar.runtime")
  local settings = require("orbit").get_config().modules.hangar
  local hangar = h.options(settings)
  assert(hangar.adapters.dap.runtime() == runtime)
  local captured = hangar.adapters.dap.options()
  assert(captured.enabled.python and captured.enabled.coreclr)
  assert(captured.configurations.python[2].request == "attach")
end)

check("invalid port and restart-only disable preserve accepted config", function()
  local before = orbit.get_config()
  local ok, err = pcall(orbit.setup, {
    modules = { dap = { python_port = "" } },
  })
  assert(not ok and tostring(err):find("python_port", 1, true))
  assert(vim.deep_equal(orbit.get_config(), before))
  orbit.setup({ modules = { dap = { python = false } } })
  assert(orbit.get_config().modules.dap.python)
  assert(orbit.get_pending_restart()["orbit.modules.dap.python"] == false)
end)

package.loaded.hangar = nil
package.loaded["hangar.state"], package.preload["hangar.state"] = nil, nil
package.loaded.dap, package.preload.dap = nil, nil
package.loaded.dapui, package.preload.dapui = nil, nil
print(string.format("%d DAP tests passed.", passed))
