-- Launch and attach real debugpy sessions through Orbit's DAP owner.
-- Requires Git, network and Python; missing tools fail the test.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
local windows = vim.fn.has("win32") == 1
local pins = {
  { "https://github.com/Orbit-Lua/nvim-dap.git", "e03a0f2b786ccbf3398ed445d9700df8ed1e7627" },
  { "https://github.com/rcarriga/nvim-dap-ui.git", "cc9dd33aade7f20bae414d0cba163bc60d4d4b43" },
  { "https://github.com/nvim-neotest/nvim-nio.git", "edcc181a875301dd21840189aa2f2f9ad69fc172" },
}
local debugpy_version = "1.8.22"
local workspace = vim.fn.tempname() .. " live debugpy with spaces"
local debuggee

local function run(argv)
  local result = vim.system(argv, { text = true, timeout = 300000 }):wait()
  assert(result.code == 0, vim.inspect(argv) ..
    " failed: " .. tostring(result.stderr or result.stdout))
  return result.stdout or ""
end

local function wait(predicate, message)
  assert(vim.wait(60000, predicate, 50), message)
end

local ok, err = xpcall(function()
  local python = windows and "python" or "python3"
  assert(vim.fn.executable("git") == 1, "Git is required")
  assert(vim.fn.executable(python) == 1, "Python is required")
  for index, pin in ipairs(pins) do
    local directory = vim.fs.joinpath(workspace, "plugin" .. index)
    assert(vim.fn.mkdir(directory, "p") == 1)
    run({ "git", "init", directory })
    run({ "git", "-C", directory, "fetch", "--depth", "1", pin[1], pin[2] })
    run({ "git", "-C", directory, "checkout", "--detach", "FETCH_HEAD" })
    assert(vim.trim(run({ "git", "-C", directory, "rev-parse", "HEAD" })) == pin[2])
    vim.opt.rtp:prepend(directory)
  end

  -- An isolated virtual environment is the adapter's documented contract.
  local venv = vim.fs.joinpath(workspace, "venv")
  run({ python, "-m", "venv", venv })
  local venv_python = vim.fs.joinpath(venv, windows and "Scripts/python.exe" or "bin/python")
  run({ venv_python, "-m", "pip", "install", "--disable-pip-version-check",
    "debugpy==" .. debugpy_version })
  vim.env.VIRTUAL_ENV = venv

  local program = vim.fs.joinpath(workspace, "program.py")
  assert(vim.fn.writefile({
    "total = 0",
    "for value in range(3):",
    "    total += value",
    "print('orbit-debugpy', total)",
  }, program) == 0)

  require("orbit").setup()
  local specs = require("orbit.modules.dap").spec()
  specs[1].config()
  specs[2].config(specs[2], specs[2].opts or {})
  local dap = require("dap")
  assert(type(dap.adapters.python) == "function", "Orbit did not register debugpy")
  print("PASS Orbit registers the debugpy adapter through Lazy config")

  vim.cmd.edit(vim.fn.fnameescape(program))
  local buffer = vim.api.nvim_get_current_buf()
  require("dap.breakpoints").set({}, buffer, 4)

  local function debug_session(configuration, label)
    local stopped, terminated = nil, false
    dap.listeners.after.event_stopped.orbit_live = function(session, body)
      stopped = { thread = body.threadId, session = session }
    end
    dap.listeners.after.event_terminated.orbit_live = function() terminated = true end
    dap.run(configuration)
    wait(function() return stopped ~= nil end, label .. ": debugpy did not stop at the breakpoint")
    local frame = stopped.session.current_frame
    wait(function()
      frame = stopped.session.current_frame
      return frame ~= nil
    end, label .. ": no current frame")
    assert(frame.line == 4, label .. " stopped at line " .. tostring(frame.line))
    assert(vim.tbl_count(dap.sessions()) == 1, label .. " started duplicate sessions")
    -- Orbit closes DAP UI when a session ends; open it to observe that.
    require("dapui").open()
    assert(require("dapui.windows").layouts[1]:is_open(), label .. ": DAP UI did not open")
    dap.continue()
    wait(function() return terminated and next(dap.sessions()) == nil end,
      label .. ": session did not finish")
    wait(function() return not require("dapui.windows").layouts[1]:is_open() end,
      label .. ": DAP UI stayed open after the session ended")
    print("PASS real debugpy " .. label .. " reaches the breakpoint and cleans up")
  end

  debug_session({ type = "python", request = "launch", name = "orbit launch",
    program = program, console = "internalConsole" }, "launch")

  local port = 5678 + (vim.uv.os_getpid() % 1000)
  debuggee = vim.system({ venv_python, "-m", "debugpy", "--listen", "127.0.0.1:" .. port,
    "--wait-for-client", program }, { text = true })
  vim.wait(2000, function() return false end)
  debug_session({ type = "python", request = "attach", name = "orbit attach",
    connect = { host = "127.0.0.1", port = port } }, "attach")
  local done = debuggee:wait(30000)
  assert(done.code == 0 and done.stdout:find("orbit-debugpy 3", 1, true),
    "attached program did not finish: " .. vim.inspect(done))
  debuggee = nil
end, debug.traceback)

if debuggee then pcall(function() debuggee:kill(9) end) end
vim.fn.delete(workspace, "rf")
assert(ok, tostring(err))
print("Real debugpy integration tests passed.")
