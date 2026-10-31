-- Verify Tree-sitter specs and one-shot filetype subscriber with fixtures.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
local orbit = require("orbit")
local feature = require("orbit.modules.treesitter_plugins")
local passed = 0
local function check(label, fn)
  local ok, err = xpcall(fn, debug.traceback)
  assert(ok, "FAIL " .. label .. "\n" .. tostring(err))
  passed = passed + 1
  print("PASS " .. label)
end

check("feature import is inert and defaults preserve legacy declarations", function()
  assert(#feature.spec() == 0)
  orbit.setup()
  local s = feature.spec()
  assert(#s == 3)
  assert(s[1][1] == "nvim-treesitter/nvim-treesitter")
  assert(s[1].branch == "main" and s[1].lazy == false)
  assert(s[1].build[1] == ":TSUpdate")
  assert(s[2][1] == "nvim-treesitter/nvim-treesitter-context")
  assert(s[2].event[1] == "BufReadPost")
  assert(s[2].opts.max_lines == 3)
  assert(s[3][1] == "windwp/nvim-ts-autotag")
  assert(s[3].opts.aliases.csproj == "xml")
  assert(s[3].opts.aliases.jsx == "typescriptreact")
  assert(s[3].opts.opts.enable_close_on_slash == false)
  assert(package.loaded["nvim-ts-autotag"] == nil)
end)

check("parser owner subscribes only once and skips bigfiles", function()
  local runtime = require("orbit.modules.treesitter_plugins.runtime")
  runtime.setup()
  runtime.setup()
  assert(#vim.api.nvim_get_autocmds({
    group = "OrbitTreesitterStart", event = "FileType",
  }) == 1)
  local start = vim.treesitter.start
  local seen = {}
  vim.treesitter.start = function(buf)
    seen[#seen + 1] = buf
  end
  local normal = vim.api.nvim_create_buf(true, false)
  vim.bo[normal].filetype = "lua"
  assert(#seen == 1 and seen[1] == normal)
  local huge = vim.api.nvim_create_buf(true, false)
  vim.bo[huge].filetype = "bigfile"
  assert(#seen == 1)
  vim.treesitter.start = start
end)

check("missing parser retries on BufEnter and stops after success", function()
  local runtime = require("orbit.modules.treesitter_plugins.runtime")
  runtime.setup()
  runtime.setup()
  assert(#vim.api.nvim_get_autocmds({
    group = "OrbitTreesitterStart", event = "BufEnter",
  }) == 1)
  assert(#vim.api.nvim_get_autocmds({
    group = "OrbitTreesitterStart", event = "BufWipeout",
  }) == 1)

  local original = vim.treesitter.start
  local buffer = vim.api.nvim_create_buf(true, false)
  local attempts = 0
  local installed = false
  vim.treesitter.start = function(target)
    assert(target == buffer)
    attempts = attempts + 1
    if not installed then error("parser unavailable") end
  end
  vim.bo[buffer].filetype = "c_sharp"
  assert(attempts == 1)
  vim.api.nvim_exec_autocmds("BufEnter", { buffer = buffer })
  assert(attempts == 2)
  installed = true
  vim.api.nvim_exec_autocmds("BufEnter", { buffer = buffer })
  assert(attempts == 3)
  vim.api.nvim_exec_autocmds("BufEnter", { buffer = buffer })
  assert(attempts == 3)
  vim.treesitter.start = original
end)

check("autotag setup callback invokes plugin with accepted options", function()
  local called = 0
  package.preload["nvim-ts-autotag"] = function()
    return {
      setup = function(opts)
        assert(opts.opts.enable_close)
        assert(opts.opts.enable_rename)
        assert(opts.aliases.pubxml == "xml")
        called = called + 1
      end,
    }
  end
  local item = feature.spec()[3]
  item.config(nil, item.opts)
  assert(called == 1)
  package.loaded["nvim-ts-autotag"] = nil
  package.preload["nvim-ts-autotag"] = nil
end)

check("invalid context limit is rejected and safe config remains accepted", function()
  local accepted = orbit.get_config()
  local ok, err = pcall(orbit.setup, { modules = {
    treesitter_plugins = { context_lines = -1 },
  } })
  assert(not ok and tostring(err):find("context_lines", 1, true))
  assert(vim.deep_equal(orbit.get_config(), accepted))
end)

check("later plugin changes are deferred until restart", function()
  orbit.setup({ modules = { treesitter_plugins = { context = false } } })
  assert(orbit.get_config().modules.treesitter_plugins.context)
  assert(orbit.get_pending_restart()["orbit.modules.treesitter_plugins.context"] == false)
end)

print(string.format("%d Tree-sitter tests passed.", passed))
