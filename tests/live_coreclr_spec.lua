-- Debug a disposable C# project with real netcoredbg through Orbit's DAP
-- owner and dotnet-cli. Requires Git, network, the .NET SDK and netcoredbg.
-- ORBIT_NVIM_DAP selects the nvim-dap source: fork (default) or upstream.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
local windows = vim.fn.has("win32") == 1
local dap_sources = {
  fork = { "https://github.com/Orbit-Lua/nvim-dap.git", "8aba1e3805438ee6f74207e0b7385ef951bb9945" },
  upstream = { "https://github.com/mfussenegger/nvim-dap.git", "cfa2d58f4537aca6ca83e2de1a0d9f1491121264" },
}
local variant = vim.env.ORBIT_NVIM_DAP or "fork"
local pins = {
  assert(dap_sources[variant], "unknown ORBIT_NVIM_DAP: " .. variant),
  { "https://github.com/Orbit-Lua/dotnet-cli.nvim.git", "a74464a59be996b5db3e7f9480b937c9ff992471" },
}
local workspace = vim.fn.tempname() .. " live coreclr with spaces"

local function run(argv, cwd)
  local result = vim.system(argv, { text = true, timeout = 600000, cwd = cwd }):wait()
  assert(result.code == 0, vim.inspect(argv) ..
    " failed: " .. tostring(result.stderr or "") .. tostring(result.stdout or ""))
  return result.stdout or ""
end

local function wait(predicate, message)
  assert(vim.wait(180000, predicate, 100), message)
end

local ok, err = xpcall(function()
  for _, tool in ipairs({ "git", "dotnet", windows and "netcoredbg.exe" or "netcoredbg" }) do
    assert(vim.fn.executable(tool) == 1, tool .. " is required on PATH")
  end
  print("nvim-dap source: " .. variant)
  for index, pin in ipairs(pins) do
    local directory = vim.fs.joinpath(workspace, "plugin" .. index)
    assert(vim.fn.mkdir(directory, "p") == 1)
    run({ "git", "init", directory })
    run({ "git", "-C", directory, "fetch", "--depth", "1", pin[1], pin[2] })
    run({ "git", "-C", directory, "checkout", "--detach", "FETCH_HEAD" })
    assert(vim.trim(run({ "git", "-C", directory, "rev-parse", "HEAD" })) == pin[2])
    vim.opt.rtp:prepend(directory)
  end

  local project_dir = vim.fs.joinpath(workspace, "Orbit Console")
  run({ "dotnet", "new", "console", "--name", "OrbitConsole", "--output", project_dir,
    "--framework", "net" .. run({ "dotnet", "--version" }):match("^(%d+%.%d+)") })
  local program = vim.fs.joinpath(project_dir, "Program.cs")
  assert(vim.fn.writefile({
    "var total = 0;",
    "for (var value = 0; value < 3; value++) total += value;",
    "System.Console.WriteLine($\"orbit-coreclr {total}\");",
  }, program) == 0)
  local project = vim.fs.joinpath(project_dir, "OrbitConsole.csproj")

  require("orbit").setup()
  local dotnet = require("orbit.modules.dotnet").spec()[1]
  require("dotnet-cli").setup(dotnet.opts)
  require("orbit.modules.dap").spec()[1].config()
  local dap = require("dap")
  assert(type(dap.adapters.coreclr) == "function", "dotnet-cli did not register CoreCLR")
  print("PASS Orbit delegates CoreCLR registration to dotnet-cli")

  -- Native paths come from :edit; forward slashes come from pickers and
  -- vim.fs.normalize. Windows debuggers must accept both buffer names.
  local spellings = { native = vim.fn.fnamemodify(program, ":p") }
  if windows then spellings.forward = spellings.native:gsub("\\", "/") end
  for label, path in pairs(spellings) do
    for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_get_name(buffer):lower():find("program.cs", 1, true) then
        vim.api.nvim_buf_delete(buffer, { force = true })
      end
    end
    local buffer = vim.fn.bufadd(path)
    vim.fn.bufload(buffer)
    vim.api.nvim_set_current_buf(buffer)
    require("dap.breakpoints").clear()
    require("dap.breakpoints").set({}, buffer, 3)

    local stopped, terminated = nil, false
    dap.listeners.after.event_stopped.orbit_live = function(session) stopped = session end
    dap.listeners.after.event_terminated.orbit_live = function() terminated = true end
    local config = assert(require("dotnet-cli.dap").config({
      project = project, root = project_dir, configuration = "Debug",
    }))
    dap.run(config)
    wait(function() return stopped ~= nil and stopped.current_frame ~= nil end,
      label .. " path: netcoredbg did not stop at the breakpoint (" .. path .. ")")
    assert(stopped.current_frame.line == 3,
      label .. " path stopped at line " .. tostring(stopped.current_frame.line))
    assert(#dap.sessions() == 1, label .. " path started duplicate sessions")
    dap.continue()
    wait(function() return terminated and dap.session() == nil end,
      label .. " path: session did not finish")
    print("PASS real netcoredbg stops at a breakpoint with a " .. label .. " path")
  end
end, debug.traceback)

pcall(function() require("dap").terminate() end)
vim.fn.delete(workspace, "rf")
assert(ok, tostring(err))
print("Real CoreCLR integration tests passed with nvim-dap " .. variant .. ".")
