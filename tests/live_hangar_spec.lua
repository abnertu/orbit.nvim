-- Verify real pinned Hangar state persistence, and that Hangar itself gates
-- Orbit's real LSP, conform, nvim-lint and nvim-dap owners from saved state.
-- This uses the actual upstream plugins, with no Hangar module stubs.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)

local source = "https://github.com/Orbit-Lua/hangar.nvim.git"
-- v0.4.0 is an annotated tag: pin its dereferenced commit, not the tag object.
local revision = "778b2e55df6f0a524e77489800178894612e4291"
-- The backends use the commits that Orbit locks and Hangar 0.4 tests.
local backends = {
  { "https://github.com/stevearc/conform.nvim.git", "016802de402556da54c36bd7359b441266b01cdd" },
  { "https://github.com/mfussenegger/nvim-lint.git", "f6230a5c06ba59e6059c14637f1dbe29a7978b9b" },
  { "https://github.com/Orbit-Lua/nvim-dap.git", "8aba1e3805438ee6f74207e0b7385ef951bb9945" },
}
local plugin = vim.fn.tempname() .. " upstream Hangar checkout with spaces"
local backend_root = vim.fn.tempname() .. " Hangar backends with spaces"
local storage = vim.fn.tempname() .. " orbit Hangar state with spaces"
local state_path = vim.fs.joinpath(storage, "managed", "hangar.json")
local decoy = vim.fs.joinpath(storage, "wrong.json")
local old_global = vim.g.hangar_state_path

local function run(argv)
  local result = vim.system(argv, { text = true, timeout = 120000 }):wait()
  assert(
    result.code == 0,
    "Git checkout failed: "
      .. vim.inspect(argv)
      .. ": "
      .. tostring(result.stderr or result.stdout or result.code)
  )
  return result.stdout or ""
end

---@param directory string
---@param url string
---@param commit string
local function checkout(directory, url, commit)
  assert(vim.fn.mkdir(directory, "p") == 1)
  run({ "git", "init", directory })
  run({ "git", "-C", directory, "fetch", "--depth", "1", url, commit })
  run({ "git", "-C", directory, "checkout", "--detach", "FETCH_HEAD" })
  assert(
    vim.trim(run({ "git", "-C", directory, "rev-parse", "HEAD" })) == commit,
    url .. " checkout did not match the pinned revision"
  )
end

local function saved()
  return vim.json.decode(table.concat(vim.fn.readfile(state_path), "\n"))
end

local ok, err = xpcall(function()
  assert(vim.fn.executable("git") == 1, "Git is required")
  assert(vim.fn.mkdir(plugin, "p") == 1)
  assert(vim.fn.mkdir(storage, "p") == 1)
  run({ "git", "init", plugin })
  run({ "git", "-C", plugin, "fetch", "--depth", "1", source, revision })
  run({ "git", "-C", plugin, "checkout", "--detach", "FETCH_HEAD" })
  assert(
    vim.trim(run({ "git", "-C", plugin, "rev-parse", "HEAD" })) == revision,
    "real Hangar checkout did not match the pinned revision"
  )
  vim.opt.rtp:prepend(plugin)
  for index, backend in ipairs(backends) do
    local directory = vim.fs.joinpath(backend_root, tostring(index))
    checkout(directory, backend[1], backend[2])
    vim.opt.rtp:prepend(directory)
  end

  vim.g.hangar_state_path = decoy
  local orbit = require("orbit")
  local owner = require("orbit.modules.mason")
  orbit.setup({ modules = { mason = { hangar = { state_file = state_path } } } })
  assert(package.loaded.hangar == nil, "root setup must not load upstream Hangar")
  local declaration = owner.spec()[3]
  assert(declaration[1] == "Orbit-Lua/hangar.nvim")
  assert(declaration.version == "^0.4")
  assert(
    vim.fn.filereadable(state_path) == 0,
    "Hangar state must not be created by initial root setup"
  )

  declaration.config()
  assert(package.loaded.hangar ~= nil, "Hangar was not loaded by its owner")
  local hangar = require("hangar")
  local state = require("hangar.state")
  assert(vim.api.nvim_get_commands({}).Hangar ~= nil)
  assert(
    require("hangar.config").get().state_path() == state_path,
    "explicit Orbit state path was not passed to real Hangar"
  )
  assert(vim.fn.filereadable(state_path) == 0, "Hangar created a state file without a user action")
  assert(state.is_enabled("lsp", "lua_ls"))
  assert(state.is_enabled("formatter", "ruff_fix"))
  print("PASS pinned real Hangar Lazy activation and read-only startup")

  assert(state.set_enabled("lsp", "lua_ls", false))
  assert(state.set_enabled("linter", "sqlfluff", false))
  assert(state.set_enabled("formatter", "ruff_fix", false))
  assert(state.set_enabled("dap", "python", false))
  assert(state.set_order("formatter", "python", {
    "ruff_format",
    "ruff_organize_imports",
    "ruff_fix",
  }))
  assert(not state.is_enabled("lsp", "lua_ls"))
  assert(state.is_enabled("lsp", "pyright"))
  assert(not state.is_enabled("linter", "sqlfluff"))
  assert(saved().lsp.lua_ls == false)
  assert(saved().formatter.ruff_fix == false)
  assert(vim.deep_equal(saved().formatter_order.python, {
    "ruff_format",
    "ruff_organize_imports",
    "ruff_fix",
  }))
  assert(
    vim.fn.filereadable(decoy) == 0,
    "Hangar wrote the global override instead of the explicit path"
  )
  print("PASS real Hangar persists LSP/linter/formatter flags and order")

  local lsp = require("orbit.modules.lsp").spec()[1]
  lsp.config(nil, lsp.opts)
  assert(not vim.lsp.is_enabled("lua_ls"), "Hangar did not skip the disabled lua_ls server")
  assert(vim.lsp.is_enabled("pyright"), "Hangar skipped an enabled server")
  print("PASS real Hangar skips a disabled server that Orbit's LSP owner enables")

  local formatter = require("orbit.modules.formatter").spec()[1]
  formatter.config(formatter, formatter.opts)
  local by_ft = require("conform").formatters_by_ft
  assert(
    vim.deep_equal(by_ft.python, { "ruff_format", "ruff_organize_imports" }),
    "real Hangar did not reorder and disable Orbit's Python formatters: "
      .. vim.inspect(by_ft.python)
  )
  assert(vim.deep_equal(by_ft.lua, { "stylua" }))
  assert(formatter.opts.formatters_by_ft.python[1] == "ruff_fix", "Hangar mutated Orbit's opts")
  print("PASS real Hangar filters conform after Orbit's formatter owner sets it up")

  local linter = require("orbit.modules.linter").spec()[1]
  linter.config(nil, linter.opts)
  local lint = require("lint")
  -- An empty name list runs no linter but triggers Hangar's pre-run filter.
  lint.try_lint({})
  assert(
    vim.deep_equal(lint.linters_by_ft.sql, {}),
    "real Hangar did not drop the disabled SQLFluff linter: " .. vim.inspect(lint.linters_by_ft.sql)
  )
  assert(linter.opts.linters_by_ft.sql[1] == "sqlfluff", "Hangar mutated Orbit's opts")
  print("PASS real Hangar filters nvim-lint before each run")

  local notices = {}
  local old_notify = vim.notify
  vim.notify = function(message)
    notices[#notices + 1] = tostring(message)
  end
  local dap_ok, dap_err = pcall(function()
    local owner_spec = require("orbit.modules.dap").spec()[1]
    assert(owner_spec[1] == "Orbit-Lua/nvim-dap")
    owner_spec.config()
    local dap = require("dap")
    assert(dap.adapters.python ~= nil, "Orbit must register the adapter; Hangar gates the session")
    dap.run({ type = "python", request = "launch", name = "Hangar gate", program = "main.py" })
    assert(
      vim.wait(5000, function()
        for _, message in ipairs(notices) do
          if message:find("python is disabled in Hangar", 1, true) then
            return true
          end
        end
        return false
      end),
      "Hangar did not report the disabled adapter: " .. vim.inspect(notices)
    )
    assert(dap.session() == nil, "a disabled adapter started a debug session")
  end)
  vim.notify = old_notify
  assert(dap_ok, tostring(dap_err))
  print("PASS real Hangar stops a debug session of a disabled adapter")

  state.reset()
  assert(not state.is_enabled("lsp", "lua_ls"))
  assert(not state.is_enabled("formatter", "ruff_fix"))
  assert(not state.is_enabled("linter", "sqlfluff"))
  assert(vim.deep_equal(state.get_order("formatter", "python"), {
    "ruff_format",
    "ruff_organize_imports",
    "ruff_fix",
  }))
  assert(saved().dap.python == false, "Hangar lost the saved adapter state")
  print("PASS real Hangar reloads saved state from disk")

  -- The current process owns this lock, so Hangar must reject a second
  -- writer without changing its cached state or the persisted JSON.
  local content = table.concat(vim.fn.readfile(state_path), "\n")
  local lock = state_path .. ".lock"
  vim.fn.writefile(
    { vim.json.encode({
      pid = vim.uv.os_getpid(),
      token = "live-owner-fixture",
    }) },
    lock
  )
  local wrote, reason = state.set_enabled("lsp", "lua_ls", true)
  assert(
    wrote == false and type(reason) == "string",
    "real Hangar must refuse a concurrent active state writer"
  )
  assert(
    table.concat(vim.fn.readfile(state_path), "\n") == content,
    "blocked Hangar update modified persisted state"
  )
  assert(not state.is_enabled("lsp", "lua_ls"), "blocked Hangar update modified the accepted state")
  assert(
    vim.json.decode(table.concat(vim.fn.readfile(lock), "\n")).token == "live-owner-fixture",
    "Hangar stole a live writer's lock"
  )
  assert(vim.fn.delete(lock) == 0)
  print("PASS real Hangar rejects concurrent writers without losing state")

  declaration.config()
  assert(require("hangar.config").get().state_path() == state_path)
  assert(vim.api.nvim_get_commands({}).Hangar ~= nil)
  assert(type(hangar.filter) == "function")
end, debug.traceback)

vim.g.hangar_state_path = old_global
vim.fn.delete(plugin, "rf")
vim.fn.delete(backend_root, "rf")
vim.fn.delete(storage, "rf")
assert(ok, tostring(err))
print("Pinned real Hangar state persistence integration passed.")
