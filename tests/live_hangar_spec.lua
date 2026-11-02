-- Verify real pinned Hangar state persistence and Orbit consumer integration.
-- This uses the actual upstream Hangar API, with no Hangar module stubs.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)

local source = "https://github.com/Orbit-Lua/hangar.nvim.git"
-- v0.3.1 is an annotated tag: pin its dereferenced commit, not the tag object.
local revision = "fb79cc024aba1a20661064245541a821d0516ead"
local plugin = vim.fn.tempname() .. " upstream Hangar checkout with spaces"
local storage = vim.fn.tempname() .. " orbit Hangar state with spaces"
local state_path = vim.fs.joinpath(storage, "managed", "hangar.json")
local decoy = vim.fs.joinpath(storage, "wrong.json")
local old_global = vim.g.hangar_state_path

local function run(argv)
  local result = vim.system(argv, { text = true, timeout = 120000 }):wait()
  assert(result.code == 0,
    "Git checkout failed: " .. vim.inspect(argv) .. ": "
      .. tostring(result.stderr or result.stdout or result.code))
  return result.stdout or ""
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
  assert(vim.trim(run({ "git", "-C", plugin, "rev-parse", "HEAD" })) == revision,
    "real Hangar checkout did not match the pinned revision")
  vim.opt.rtp:prepend(plugin)

  vim.g.hangar_state_path = decoy
  local orbit = require("orbit")
  local owner = require("orbit.modules.hangar")
  orbit.setup({ modules = { hangar = { state_file = state_path } } })
  assert(package.loaded.hangar == nil,
    "root setup must not load upstream Hangar")
  local declaration = owner.spec()[2]
  assert(declaration[1] == "Orbit-Lua/hangar.nvim")
  assert(declaration.version == "^0.3")
  assert(vim.fn.filereadable(state_path) == 0,
    "Hangar state must not be created by initial root setup")

  declaration.config()
  assert(package.loaded.hangar ~= nil, "Hangar was not loaded by its owner")
  local hangar = require("hangar")
  local state = require("hangar.state")
  local bridge = require("orbit.hangar_bridge")
  assert(vim.api.nvim_get_commands({}).Hangar ~= nil)
  assert(require("hangar.config").get().state_path() == state_path,
    "explicit Orbit state path was not passed to real Hangar")
  assert(vim.fn.filereadable(state_path) == 0,
    "Hangar created a state file without a user action")
  assert(bridge.is_enabled("lsp", "lua_ls"))
  assert(bridge.is_enabled("formatter", "ruff_fix"))
  print("PASS pinned real Hangar Lazy activation and read-only startup")

  assert(state.set_enabled("lsp", "lua_ls", false))
  assert(state.set_enabled("linter", "sqlfluff", false))
  assert(state.set_enabled("formatter", "ruff_fix", false))
  assert(state.set_order("formatter", "python", {
    "ruff_format", "ruff_organize_imports", "ruff_fix",
  }))
  assert(not bridge.is_enabled("lsp", "lua_ls"))
  assert(bridge.is_enabled("lsp", "pyright"))
  assert(not bridge.is_enabled("linter", "sqlfluff"))
  assert(saved().lsp.lua_ls == false)
  assert(saved().formatter.ruff_fix == false)
  assert(vim.deep_equal(saved().formatter_order.python, {
    "ruff_format", "ruff_organize_imports", "ruff_fix",
  }))
  assert(vim.fn.filereadable(decoy) == 0,
    "Hangar wrote the global override instead of the explicit path")
  print("PASS real Hangar persists LSP/linter/formatter flags and order")

  local initial = {
    python = { "ruff_fix", "ruff_organize_imports", "ruff_format" },
    lua = { "stylua" },
    ["*"] = { "trim_whitespace" },
  }
  local fmt = bridge.filter("formatter", initial)
  assert(vim.deep_equal(fmt.python, {
    "ruff_format", "ruff_organize_imports",
  }), "real Hangar did not reorder and disable configured Python formatters: "
    .. vim.inspect(fmt.python))
  assert(vim.deep_equal(fmt.lua, { "stylua" }))
  assert(vim.deep_equal(fmt["*"], { "trim_whitespace" }))
  assert(initial.python[1] == "ruff_fix",
    "Hangar mutated Orbit's original formatter table")
  local linters = bridge.filter("linter", {
    sql = { "sqlfluff" }, lua = { "luacheck" },
  })
  assert(vim.deep_equal(linters.sql, {}),
    "real Hangar failed to suppress a saved disabled SQLFluff linter")
  assert(vim.deep_equal(linters.lua, { "luacheck" }))
  print("PASS real Hangar filters Orbit formatter/linter activation and order")

  state.reset()
  assert(not state.is_enabled("lsp", "lua_ls"))
  assert(not state.is_enabled("formatter", "ruff_fix"))
  assert(not state.is_enabled("linter", "sqlfluff"))
  assert(vim.deep_equal(state.get_order("formatter", "python"), {
    "ruff_format", "ruff_organize_imports", "ruff_fix",
  }))
  assert(not bridge.is_enabled("lsp", "lua_ls"),
    "a fresh Hangar state read lost persisted user intent")
  print("PASS real Hangar reloads saved state from disk")

  -- The current process owns this lock, so Hangar must reject a second
  -- writer without changing its cached state or the persisted JSON.
  local content = table.concat(vim.fn.readfile(state_path), "\n")
  local lock = state_path .. ".lock"
  vim.fn.writefile({ vim.json.encode({
    pid = vim.uv.os_getpid(), token = "live-owner-fixture",
  }) }, lock)
  local wrote, reason = state.set_enabled("lsp", "lua_ls", true)
  assert(wrote == false and type(reason) == "string",
    "real Hangar must refuse a concurrent active state writer")
  assert(table.concat(vim.fn.readfile(state_path), "\n") == content,
    "blocked Hangar update modified persisted state")
  assert(not state.is_enabled("lsp", "lua_ls"),
    "blocked Hangar update modified the accepted state")
  assert(vim.json.decode(table.concat(vim.fn.readfile(lock), "\n")).token
    == "live-owner-fixture", "Hangar stole a live writer's lock")
  assert(vim.fn.delete(lock) == 0)
  print("PASS real Hangar rejects concurrent writers without losing state")

  declaration.config()
  assert(require("hangar.config").get().state_path() == state_path)
  assert(vim.api.nvim_get_commands({}).Hangar ~= nil)
  assert(type(hangar.filter) == "function")
end, debug.traceback)

vim.g.hangar_state_path = old_global
vim.fn.delete(plugin, "rf")
vim.fn.delete(storage, "rf")
assert(ok, tostring(err))
print("Pinned real Hangar state persistence integration passed.")
