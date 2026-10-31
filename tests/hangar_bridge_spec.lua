-- Verify Hangar enabled-state and formatter/linter order across real owners.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
local orbit = require("orbit")
local bridge = require("orbit.hangar_bridge")
local passed = 0
local function check(label, fn)
  local ok, err = xpcall(fn, debug.traceback)
  assert(ok, "FAIL " .. label .. "\n" .. tostring(err))
  passed = passed + 1
  print("PASS " .. label)
end

check("Hangar is not eagerly imported when plugins are disabled", function()
  local input = { lua = { "stylua" } }
  local filtered = bridge.filter("formatter", input)
  assert(vim.deep_equal(input, filtered) and filtered ~= input)
  assert(bridge.is_enabled("lsp", "pyright"))
  assert(package.loaded.hangar == nil)
end)

local filtered = {}
package.loaded.hangar = {
  filter = function(category, by_ft)
    filtered[#filtered + 1] = category
    local selected = vim.deepcopy(by_ft)
    if category == "formatter" then
      selected.lua = {}
    elseif category == "linter" then
      selected.sql = {}
    end
    return selected
  end,
}
package.preload["hangar.state"] = function()
  return {
    is_enabled = function(category, name)
      assert(category == "lsp")
      return name ~= "pyright"
    end,
  }
end

check("Hangar bridge delegates enabled-state to the runtime tool state", function()
  assert(not bridge.is_enabled("lsp", "pyright"))
  assert(bridge.is_enabled("lsp", "lua_ls"))
end)

check("Conform receives Hangar-filtered filetype formatters at config time", function()
  orbit.setup()
  local received
  package.preload.conform = function()
    return { setup = function(opts)
      received = opts
    end }
  end
  local item = require("orbit.modules.formatter").spec()[1]
  assert(item.opts.formatters_by_ft.lua[1] == "stylua",
    "source formatter defaults must stay immutable")
  item.config(nil, vim.deepcopy(item.opts))
  assert(received ~= nil and #received.formatters_by_ft.lua == 0)
  assert(received.formatters_by_ft.python[1] == "ruff_fix")
  assert(item.opts.formatters_by_ft.lua[1] == "stylua")
  package.loaded.conform, package.preload.conform = nil, nil
end)

check("nvim-lint receives Hangar-filtered linters at runtime setup", function()
  package.preload.lint = function()
    return { linters_by_ft = {}, try_lint = function() end }
  end
  local item = require("orbit.modules.linter").spec()[1]
  item.config(nil, item.opts)
  local lint = require("lint")
  assert(#lint.linters_by_ft.sql == 0)
  assert(lint.linters_by_ft.lua[1] == "luacheck")
  assert(item.opts.linters_by_ft.sql[1] == "sqlfluff")
  package.loaded.lint, package.preload.lint = nil, nil
end)

check("native LSP skips disabled servers while leaving other servers enabled", function()
  local configured, enabled = {}, {}
  local old_config, old_enable = vim.lsp.config, vim.lsp.enable
  vim.lsp.config = function(name)
    configured[#configured + 1] = name
  end
  vim.lsp.enable = function(name)
    enabled[#enabled + 1] = name
  end
  local ok, err = xpcall(function()
    local item = require("orbit.modules.lsp").spec()[1]
    local status = item.config(nil, item.opts)
    assert(#status.activated > 5)
  end, debug.traceback)
  vim.lsp.config, vim.lsp.enable = old_config, old_enable
  assert(ok, tostring(err))
  assert(not vim.tbl_contains(configured, "pyright"))
  assert(not vim.tbl_contains(enabled, "pyright"))
  assert(vim.tbl_contains(enabled, "lua_ls"))
end)

check("all three tool consumers use one Hangar bridge", function()
  assert(vim.deep_equal(filtered, { "formatter", "linter" }))
  package.loaded.hangar = nil
  package.loaded["hangar.state"], package.preload["hangar.state"] = nil, nil
  assert(bridge.is_enabled("lsp", "pyright"))
end)

print(string.format("%d Hangar activation bridge tests passed.", passed))
