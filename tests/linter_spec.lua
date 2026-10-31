-- Validate lint scheduling, filetype selection and cancellation on both OSes.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
local orbit = require("orbit")
local module = require("orbit.modules.linter")
local passed = 0
local function check(label, fn)
  local ok, err = xpcall(fn, debug.traceback)
  assert(ok, "FAIL " .. label .. "\n" .. tostring(err))
  passed = passed + 1
  print("PASS " .. label)
end

check("feature import is inert", function()
  assert(#module.spec() == 0)
  assert(package.loaded.lint == nil)
end)

check("initial Lazy spec keeps legacy events and language linters", function()
  orbit.setup()
  local item = module.spec()[1]
  assert(item[1] == "mfussenegger/nvim-lint")
  assert(item.event[1] == "BufReadPost")
  assert(item.opts.debounce_ms == 200)
  assert(vim.tbl_contains(item.opts.events, "TextChanged"))
  assert(item.opts.linters_by_ft.sql[1] == "sqlfluff")
  assert(item.opts.linters_by_ft.lua[1] == "luacheck")
  assert(item.opts.skip_while_editing[1] == "sqlfluff")
  assert(package.loaded.lint == nil)
end)

local runs = {}
package.preload.lint = function()
  return {
    linters_by_ft = {},
    try_lint = function(names)
      runs[#runs + 1] = vim.deepcopy(names)
    end,
  }
end

check("TextChanged excludes SQLFluff but BufWritePost can run it", function()
  local spec = module.spec()[1]
  spec.config(nil, spec.opts)
  local buf = vim.api.nvim_create_buf(true, false)
  vim.bo[buf].filetype = "sql"
  vim.api.nvim_exec_autocmds("TextChanged", { buffer = buf, modeline = false })
  vim.wait(450, function() return #runs > 0 end, 10)
  assert(#runs == 0, "SQLFluff must be skipped while editing")
  vim.api.nvim_exec_autocmds("BufWritePost", { buffer = buf, modeline = false })
  assert(vim.wait(1000, function() return #runs == 1 end, 10))
  assert(vim.deep_equal(runs[1], { "sqlfluff" }))
end)

check("the latest debounce event determines SQLFluff suppression", function()
  local buf = vim.api.nvim_create_buf(true, false)
  vim.bo[buf].filetype = "sql"
  local before = #runs

  -- Reading followed by an edit must not lint SQLFluff during typing.
  vim.api.nvim_exec_autocmds("BufReadPost", { buffer = buf, modeline = false })
  vim.api.nvim_exec_autocmds("TextChanged", { buffer = buf, modeline = false })
  vim.wait(450, function() return false end, 10)
  assert(#runs == before, "the latest TextChanged must skip SQLFluff")

  -- A save supersedes the edit and must run SQLFluff exactly once.
  vim.api.nvim_exec_autocmds("TextChanged", { buffer = buf, modeline = false })
  vim.api.nvim_exec_autocmds("BufWritePost", { buffer = buf, modeline = false })
  assert(vim.wait(1000, function() return #runs > before end, 10))
  assert(#runs == before + 1)
  assert(vim.deep_equal(runs[#runs], { "sqlfluff" }))

  -- Editing after a save must suppress the replaced save timer.
  vim.api.nvim_exec_autocmds("BufWritePost", { buffer = buf, modeline = false })
  vim.api.nvim_exec_autocmds("TextChanged", { buffer = buf, modeline = false })
  vim.wait(450, function() return false end, 10)
  assert(#runs == before + 1, "a later edit must cancel save-time lint")
end)

check("pending lint is cancelled when buffer is wiped", function()
  local before = #runs
  local buf = vim.api.nvim_create_buf(true, false)
  vim.bo[buf].filetype = "lua"
  vim.api.nvim_exec_autocmds("BufReadPost", { buffer = buf, modeline = false })
  vim.api.nvim_buf_delete(buf, { force = true })
  vim.wait(400, function() return false end, 10)
  assert(#runs == before)
end)

check("repeated setup replaces its subscription without duplicates", function()
  local spec = module.spec()[1]
  spec.config(nil, spec.opts)
  assert(#vim.api.nvim_get_autocmds({
    group = "OrbitLint", event = "BufReadPost",
  }) == 1)
  local buf = vim.api.nvim_create_buf(true, false)
  vim.bo[buf].filetype = "lua"
  local before = #runs
  vim.api.nvim_exec_autocmds("BufReadPost", { buffer = buf, modeline = false })
  assert(vim.wait(1000, function() return #runs > before end, 10))
  assert(#runs == before + 1)
  assert(vim.deep_equal(runs[#runs], { "luacheck" }))
end)

check("invalid debounce is rejected and options are restart-only", function()
  local previous = orbit.get_config()
  local ok, err = pcall(orbit.setup, {
    modules = { linter = { debounce_ms = -1 } },
  })
  assert(not ok and tostring(err):find("debounce_ms", 1, true))
  assert(vim.deep_equal(previous, orbit.get_config()))
  orbit.setup({ modules = { linter = { lint_on_change = false } } })
  assert(orbit.get_pending_restart()["orbit.modules.linter.lint_on_change"] == false)
end)

package.loaded.lint, package.preload.lint = nil, nil
print(string.format("%d linter tests passed.", passed))
