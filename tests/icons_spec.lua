-- Exercise the manifest-backed Lazy spec without a plugin download.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)

local orbit = require("orbit")
local module = require("orbit.modules.icons")
local count = 0

local function check(name, fn)
  local ok, err = xpcall(fn, debug.traceback)
  assert(ok, "FAIL " .. name .. "\n" .. tostring(err))
  count = count + 1
  print("PASS " .. name)
end

check("icons have no side effects during module import", function()
  assert(module.spec()[1] == nil)
  assert(package.loaded["mini.icons"] == nil)
end)

check("initial setup may disable devicons mock without loading plugins", function()
  orbit.setup({ modules = { icons = { mock_devicons = false } } })
  assert(package.loaded["mini.icons"] == nil)
  local entries = module.spec()
  assert(#entries == 1)
  assert(entries[1][1] == "nvim-mini/mini.icons")
  assert(entries[1].lazy == false)
  assert(type(entries[1].config) == "function")
end)

check("registry derives plugin specs from module manifest", function()
  local expected = require("orbit.plugins")
  local compatible = require("plugins")
  assert(#expected >= 2 and expected[1] == compatible[1])
  assert(expected[2][1] == "lewis6991/gitsigns.nvim")
  assert(expected[1][1] == "nvim-mini/mini.icons")
end)

check("calling plugin config uses the module's initial accepted settings", function()
  local setup_count, mocked = 0, 0
  package.preload["mini.icons"] = function()
    return {
      setup = function(opts)
        assert(vim.deep_equal(opts, {}))
        setup_count = setup_count + 1
      end,
      mock_nvim_web_devicons = function()
        mocked = mocked + 1
      end,
    }
  end
  local item = module.spec()[1]
  item.config()
  assert(setup_count == 1 and mocked == 0)
  package.preload["mini.icons"] = nil
  package.loaded["mini.icons"] = nil
end)

check("reconfiguring an activated plugin feature is restart-only", function()
  orbit.setup({ modules = { icons = { enabled = false } } })
  assert(orbit.get_config().modules.icons.enabled == true)
  assert(orbit.get_pending_restart()["orbit.modules.icons.enabled"] == false)
  assert(#module.spec() == 1)
end)

print(string.format("%d icon spec tests passed.", count))
