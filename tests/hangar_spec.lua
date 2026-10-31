-- Check Hangar tool inventory and public entry points with no plugin installation.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
local orbit = require("orbit")
local owner = require("orbit.modules.hangar")
local passed = 0
local function check(name, fn)
  local ok, err = xpcall(fn, debug.traceback)
  assert(ok, "FAIL " .. name .. "\n" .. tostring(err))
  passed = passed + 1
  print("PASS " .. name)
end

check("registry is canonical and import does not load Hangar", function()
  local tools = require("orbit.modules.hangar.registry")
  assert(tools.lsp.lua_ls.mason == "lua-language-server")
  assert(tools.lsp.roslyn.mason == "roslyn-language-server")
  assert(tools.lsp.tailwindcss.mason == "tailwindcss-language-server")
  assert(tools.dap.coreclr.mason == "netcoredbg")
  assert(tools.linter.sqlfluff.mason == "sqlfluff")
  assert(tools.formatter.ruff_format.mason == "ruff")
  assert(tools.formatter_defaults.python[1] == "ruff_fix")
  assert(tools.parser.c_sharp.ft[1] == "cs")
  assert(package.loaded.hangar == nil)
  assert(#owner.spec() == 0)
end)

check("Hangar is a high-priority plugin with a NUI dependency", function()
  orbit.setup()
  local specs = owner.spec()
  assert(#specs == 2)
  assert(specs[1][1] == "MunifTanjim/nui.nvim" and specs[1].lazy)
  assert(specs[2][1] == "Orbit-Lua/hangar.nvim")
  assert(specs[2].version == "^0.3" and specs[2].priority == 900)
  assert(specs[2].lazy == false)
  assert(specs[2].dependencies[1] == "MunifTanjim/nui.nvim")
end)

local called, opened, config = 0, 0, nil
package.preload.hangar = function()
  return {
    setup = function(opts)
      called = called + 1
      config = opts
    end,
    open = function()
      opened = opened + 1
    end,
  }
end

check("unowned command collision blocks Hangar setup", function()
  vim.api.nvim_create_user_command("Hangar", function() end, {})
  local ok, err = pcall(owner.spec()[2].config)
  assert(not ok and tostring(err):find("refusing to replace", 1, true))
  assert(called == 0)
  vim.api.nvim_del_user_command("Hangar")
end)

check("Hangar setup provides tool categories, state path and adapters", function()
  owner.spec()[2].config()
  assert(called == 1)
  assert(type(config.registry) == "table")
  assert(config.registry.package["typescript-language-server"].role == "dependency")
  local defaults = config.defaults()
  assert(defaults.formatter.python[2] == "ruff_organize_imports")
  assert(defaults.linter ~= nil)
  local path = config.state_path()
  assert(path:find("hangar.json", 1, true))
  assert(config.border == "rounded")
  local formatter = config.adapters.activation.formatter()
  local linter = config.adapters.activation.linter()
  assert(formatter.lua[1] == "stylua")
  assert(linter.sql[1] == "sqlfluff")
  assert(vim.api.nvim_get_commands({}).Hangar ~= nil)
  vim.cmd("Hangar")
  assert(opened == 1)
  local mapping = vim.fn.maparg("<leader>us", "n")
  assert(mapping:lower():find("hangar", 1, true))
end)

check("repeated plugin setup never duplicates state or commands", function()
  owner.spec()[2].config()
  assert(called == 1)
  assert(vim.api.nvim_get_commands({}).Hangar ~= nil)
end)

check("invalid config and restart requests do not alter accepted settings", function()
  local previous = orbit.get_config()
  local ok, err = pcall(orbit.setup, { modules = { hangar = { command = "" } } })
  assert(not ok and tostring(err):find("command", 1, true))
  assert(vim.deep_equal(orbit.get_config(), previous))
  orbit.setup({ modules = { hangar = { enabled = false } } })
  assert(orbit.get_config().modules.hangar.enabled == true)
  assert(orbit.get_pending_restart()["orbit.modules.hangar.enabled"] == false)
end)

package.loaded.hangar, package.preload.hangar = nil, nil
print(string.format("%d Hangar registry tests passed.", passed))
