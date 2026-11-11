-- Verify Mason command laziness, the Hangar spec and the tool registry,
-- with no plugin installation.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
local orbit = require("orbit")
local mason = require("orbit.modules.mason")
local tests = 0

local function check(label, fn)
  local ok, err = xpcall(fn, debug.traceback)
  assert(ok, "FAIL " .. label .. "\n" .. tostring(err))
  tests = tests + 1
  print("PASS " .. label)
end

check("Mason module import does not access plugin", function()
  assert(#mason.spec() == 0)
  assert(package.loaded.mason == nil)
end)

check("initial setup preserves original commands and PATH policy", function()
  orbit.setup()
  local spec = mason.spec()
  assert(#spec == 3, "expected Mason, NUI and Hangar specs")
  local item = spec[1]
  assert(item[1] == "williamboman/mason.nvim")
  assert(vim.deep_equal(item.cmd, { "Mason", "MasonInstall", "MasonUpdate" }))
  local opts = item.opts
  assert(opts.PATH == "skip")
  assert(opts.max_concurrent_installers == 10)
  assert(opts.registries[1] == "github:mason-org/mason-registry")
  assert(opts.ui.icons.package_pending == " ")
  assert(opts.ui.icons.package_installed == " ")
  assert(opts.ui.icons.package_uninstalled == " ")
  assert(package.loaded.mason == nil)
end)

check("module contributes a compatible Lazy spec to one shared manifest", function()
  local specs = require("orbit.plugins")
  local found = 0
  for _, item in ipairs(specs) do
    if item[1] == "williamboman/mason.nvim" then
      found = found + 1
    end
  end
  assert(found == 1)
end)

check("Mason and Hangar enablement are independent and restorable", function()
  local before = mason.capture()
  mason.setup({ enabled = false })
  local specs = mason.spec()
  assert(#specs == 2 and specs[2][1] == "Orbit-Lua/hangar.nvim", "Hangar needs no Mason")
  mason.setup({ hangar = { enabled = false } })
  specs = mason.spec()
  assert(#specs == 1 and specs[1][1] == "williamboman/mason.nvim")
  mason.setup({ enabled = false, hangar = { enabled = false } })
  assert(#mason.spec() == 0)
  mason.restore(before)
  assert(#mason.spec() == 3)
end)

check("registry is typed Hangar input and import does not load Hangar", function()
  local tools = require("orbit.modules.mason.registry")
  assert(tools.lsp.lua_ls.mason == "lua-language-server")
  assert(tools.lsp.roslyn.mason == "roslyn-language-server")
  assert(tools.lsp["typescript-tools"].ft[1] == "typescript")
  assert(tools.dap.coreclr.mason == "netcoredbg")
  assert(tools.formatter.ruff_format.mason == "ruff")
  assert(tools.formatter_defaults.python[1] == "ruff_fix")
  assert(tools.parser.c_sharp.source == "treesitter")
  assert(package.loaded.hangar == nil)
end)

check("Hangar loads at startup on the 0.5 release line", function()
  local specs = mason.spec()
  assert(specs[2][1] == "MunifTanjim/nui.nvim" and specs[2].lazy)
  local hangar = specs[3]
  assert(hangar[1] == "Orbit-Lua/hangar.nvim")
  assert(hangar.version == "^0.5" and hangar.priority == 900 and hangar.lazy == false)
  assert(hangar.dependencies[1] == "MunifTanjim/nui.nvim")
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
  local ok, err = pcall(mason.spec()[3].config)
  assert(not ok and tostring(err):find("refusing to replace", 1, true))
  assert(called == 0)
  vim.api.nvim_del_user_command("Hangar")
end)

check("Hangar setup passes the registry, state path and border only", function()
  mason.spec()[3].config()
  assert(called == 1)
  assert(config.registry == require("orbit.modules.mason.registry"))
  assert(config.adapters == nil and config.defaults == nil)
  assert(config.state_path():find("hangar.json", 1, true))
  assert(config.border == "rounded")
  vim.cmd("Hangar")
  assert(opened == 1)
  assert(vim.fn.maparg("<leader>us", "n"):lower():find("hangar", 1, true))
end)

check("repeated Hangar setup never duplicates state or commands", function()
  mason.spec()[3].config()
  assert(called == 1)
  assert(vim.api.nvim_get_commands({}).Hangar ~= nil)
end)

check("invalid Hangar settings and restart requests keep accepted settings", function()
  local previous = orbit.get_config()
  local ok, err = pcall(orbit.setup, { modules = { mason = { hangar = { command = "" } } } })
  assert(not ok and tostring(err):find("command", 1, true))
  assert(vim.deep_equal(orbit.get_config(), previous))
  orbit.setup({ modules = { mason = { hangar = { enabled = false } } } })
  assert(orbit.get_config().modules.mason.hangar.enabled == true)
  assert(orbit.get_pending_restart()["orbit.modules.mason.hangar"].enabled == false)
end)

package.loaded.hangar, package.preload.hangar = nil, nil

check("invalid installer count is rejected before settings activation", function()
  local accepted = orbit.get_config()
  local ok, err =
    pcall(orbit.setup, { modules = {
      mason = { max_concurrent_installers = 0 },
    } })
  assert(not ok and tostring(err):find("max_concurrent_installers", 1, true))
  assert(vim.deep_equal(orbit.get_config(), accepted))
end)

check("valid changes require restart", function()
  orbit.setup({ modules = { mason = { path_mode = "append" } } })
  assert(orbit.get_config().modules.mason.path_mode == "prepend")
  assert(orbit.get_pending_restart()["orbit.modules.mason.path_mode"] == "append")
end)

check("startup init puts the Mason bin directory on PATH once", function()
  local original = vim.env.PATH
  local bin = vim.fs.joinpath(vim.fn.stdpath("data"), "mason", "bin")
  local separator = vim.fn.has("win32") == 1 and ";" or ":"
  mason.spec()[1].init()
  assert(vim.startswith(vim.env.PATH, bin .. separator), "Mason bin was not prepended")
  mason.spec()[1].init()
  assert(vim.env.PATH == bin .. separator .. original, "Mason bin was added twice")
  vim.env.PATH = original
  mason.add_bin_to_path("skip")
  assert(vim.env.PATH == original, "skip mode changed PATH")
  assert(package.loaded.mason == nil, "PATH setup loaded Mason")
end)

print(string.format("%d Mason feature tests passed.", tests))
