-- Verify Mason command laziness and old tool-manager defaults.
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
  assert(#spec == 1)
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

check("direct module disable removes owned spec but allows restore", function()
  local before = mason.capture()
  mason.setup({ enabled = false })
  assert(#mason.spec() == 0)
  mason.restore(before)
  assert(#mason.spec() == 1)
end)

check("invalid installer count is rejected before settings activation", function()
  local accepted = orbit.get_config()
  local ok, err = pcall(orbit.setup, { modules = {
    mason = { max_concurrent_installers = 0 },
  } })
  assert(not ok and tostring(err):find("max_concurrent_installers", 1, true))
  assert(vim.deep_equal(orbit.get_config(), accepted))
end)

check("valid changes require restart", function()
  orbit.setup({ modules = { mason = { path_mode = "prepend" } } })
  assert(orbit.get_config().modules.mason.path_mode == "skip")
  assert(orbit.get_pending_restart()["orbit.modules.mason.path_mode"] == "prepend")
end)

print(string.format("%d Mason feature tests passed.", tests))
