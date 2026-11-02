-- Run a real Roslyn language server through Orbit's specialist provider.
-- Requires Git, network and the .NET 10 SDK; missing tools fail the test.
-- The server is the NuGet tool roslyn-language-server, installed per test.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
local windows = vim.fn.has("win32") == 1
local pins = {
  { "https://github.com/seblyng/roslyn.nvim.git", "bf1bd4e70bc7068d1b4aebf4ce03cc19a86615be" },
  -- Hangar v0.3.1 is an annotated tag: pin its dereferenced commit.
  { "https://github.com/Orbit-Lua/hangar.nvim.git", "fb79cc024aba1a20661064245541a821d0516ead" },
}
local server_version = "5.12.0-1.26475.2"
local workspace = vim.fn.tempname() .. " live roslyn with spaces"

local function run(argv, cwd)
  local result = vim.system(argv, { text = true, timeout = 600000, cwd = cwd }):wait()
  assert(result.code == 0, vim.inspect(argv) ..
    " failed: " .. tostring(result.stderr or "") .. tostring(result.stdout or ""))
  return result.stdout or ""
end

local function wait(predicate, message)
  assert(vim.wait(300000, predicate, 100), message)
end

local ok, err = xpcall(function()
  for _, tool in ipairs({ "git", "dotnet" }) do
    assert(vim.fn.executable(tool) == 1, tool .. " is required on PATH")
  end
  for index, pin in ipairs(pins) do
    local directory = vim.fs.joinpath(workspace, "plugin" .. index)
    assert(vim.fn.mkdir(directory, "p") == 1)
    run({ "git", "init", directory })
    run({ "git", "-C", directory, "fetch", "--depth", "1", pin[1], pin[2] })
    run({ "git", "-C", directory, "checkout", "--detach", "FETCH_HEAD" })
    assert(vim.trim(run({ "git", "-C", directory, "rev-parse", "HEAD" })) == pin[2])
    vim.opt.rtp:prepend(directory)
  end

  -- Resolve 8.3 short names before Roslyn compares solution paths.
  local base = vim.fs.normalize(vim.uv.fs_realpath(workspace))
  local tools = vim.fs.joinpath(base, "tools")
  run({ "dotnet", "tool", "install", "roslyn-language-server", "--version", server_version,
    "--tool-path", tools })
  vim.env.PATH = tools .. (windows and ";" or ":") .. vim.env.PATH
  local server = windows and "roslyn-language-server.exe" or "roslyn-language-server"
  assert(vim.fn.executable(server) == 1, "Roslyn tool did not install " .. server)
  -- Mason installs a .cmd shim on Windows; Orbit and roslyn.nvim expect it.
  if windows then
    assert(vim.fn.writefile({ '@"%~dp0roslyn-language-server.exe" %*' },
      vim.fs.joinpath(tools, "roslyn-language-server.cmd")) == 0)
  end

  -- Two solutions reference the project; Orbit selects the root solution.
  local repo = vim.fs.joinpath(base, "repo")
  local project_dir = vim.fs.joinpath(repo, "App")
  run({ "git", "init", repo })
  local framework = "net" .. run({ "dotnet", "--version" }):match("^(%d+%.%d+)")
  run({ "dotnet", "new", "console", "--name", "App", "--output", project_dir,
    "--framework", framework })
  run({ "dotnet", "new", "sln", "--name", "App", "--format", "sln", "--output", repo })
  run({ "dotnet", "sln", "App.sln", "add", "App/App.csproj" }, repo)
  local nested = vim.fs.joinpath(repo, "nested")
  run({ "dotnet", "new", "sln", "--name", "Other", "--format", "sln", "--output", nested })
  run({ "dotnet", "sln", "Other.sln", "add", "../App/App.csproj" }, nested)
  local source = vim.fs.joinpath(project_dir, "Program.cs")
  assert(vim.fn.writefile({
    "int total = 1 + 2;",
    "string wrong = total;",
    "System.Console.WriteLine(wrong);",
  }, source) == 0)

  local state_file = vim.fs.joinpath(base, "state", "hangar.json")
  require("orbit").setup({ modules = { hangar = { state_file = state_file } } })
  require("orbit.modules.hangar").spec()[2].config()
  local state = require("hangar.state")
  local provider = require("orbit.modules.lsp_providers").spec()[1]
  assert(provider[1] == "seblyng/roslyn.nvim", "Orbit did not declare roslyn.nvim")
  assert(state.set_enabled("lsp", "roslyn", false))
  assert(provider.cond() == false, "Roslyn activated while Hangar disabled it")
  assert(state.set_enabled("lsp", "roslyn", true))
  assert(provider.cond() == true, "Roslyn did not activate with a real server on PATH")
  print("PASS Hangar enablement gates the Roslyn provider")

  vim.cmd("filetype on")
  vim.cmd.runtime("plugin/roslyn.lua")
  provider.config(provider, provider.opts)
  vim.cmd.edit(vim.fn.fnameescape(source))
  local buffer = vim.api.nvim_get_current_buf()
  local client
  wait(function()
    client = vim.lsp.get_clients({ bufnr = buffer, name = "roslyn" })[1]
    return client ~= nil and client.initialized
  end, "Roslyn did not attach")
  local solution = require("roslyn.store").get(client.id)
  assert(solution and vim.fs.normalize(solution) == vim.fs.joinpath(repo, "App.sln"),
    "Roslyn opened the wrong solution: " .. tostring(solution))
  print("PASS Orbit chooses the root solution for real Roslyn")

  local diagnostic
  wait(function()
    for _, item in ipairs(vim.diagnostic.get(buffer)) do
      if item.lnum == 1 and tostring(item.code) == "CS0029" then diagnostic = item end
    end
    return diagnostic ~= nil
  end, "Roslyn did not report CS0029: " .. vim.inspect(vim.diagnostic.get(buffer)))
  print("PASS real Roslyn reports a diagnostic: " .. diagnostic.message)

  client:stop()
  wait(function() return client:is_stopped() end, "Roslyn did not stop")
end, debug.traceback)

for _, client in ipairs(vim.lsp.get_clients()) do pcall(function() client:stop(true) end) end
vim.wait(5000, function() return #vim.lsp.get_clients() == 0 end, 50)
vim.fn.delete(workspace, "rf")
assert(ok, tostring(err))
print("Real Roslyn integration tests passed.")
