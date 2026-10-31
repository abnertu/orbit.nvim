-- Exercise real Neovim demand events with a fixture Lazy module.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)

local orbit = require("orbit")
local plugin = require("orbit.modules.plugins")
local original_loadplugins = vim.go.loadplugins
local loaders_before = #package.loaders
local loaded, before, after, passed = 0, 0, 0, 0

local function check(label, fn)
  local ok, err = xpcall(fn, debug.traceback)
  assert(ok, "FAIL " .. label .. "\n" .. tostring(err))
  passed = passed + 1
  print("PASS " .. label)
end

package.preload.lazy = function()
  return {
    setup = function(specs, config)
      assert(specs[1].import == "plugins")
      local entries = require("plugins")
      assert(#entries == 2 and entries[1][1] == "nvim-mini/mini.icons")
      assert(entries[2][1] == "lewis6991/gitsigns.nvim")
      assert(config.defaults.lazy == true)
      assert(config.rocks.enabled == false)
      loaded = loaded + 1
      vim.api.nvim_create_autocmd("BufReadPre", {
        group = vim.api.nvim_create_augroup("OrbitTestLazySubscriber", { clear = true }),
        callback = function()
          after = after + 1
        end,
      })
    end,
  }
end

check("staging failure restores loader and option state", function()
  local original = plugin.setup
  plugin.setup = function(opts)
    original(opts)
    error("injected staging failure")
  end
  local ok, err = pcall(orbit.setup, { modules = { plugins = { enabled = true } } })
  plugin.setup = original
  assert(not ok and tostring(err):find("injected staging failure", 1, true))
  assert(plugin.status() == "disabled")
  assert(#package.loaders == loaders_before)
  assert(vim.go.loadplugins == original_loadplugins)
  assert(orbit.get_config() == nil)
end)

check("opt-in setup registers one loader but never initializes Lazy", function()
  orbit.setup({ modules = { plugins = { enabled = true } } })
  assert(plugin.status() == "pending")
  assert(loaded == 0 and not package.loaded.lazy)
  assert(vim.go.loadplugins == false)
  assert(#package.loaders == loaders_before + 1)
end)

check("first read initializes Lazy and replays only new groups", function()
  vim.api.nvim_create_autocmd("BufReadPre", {
    group = vim.api.nvim_create_augroup("OrbitTestEarlierRead", { clear = true }),
    callback = function()
      before = before + 1
    end,
  })
  local buffer = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_exec_autocmds("BufReadPre", { buffer = buffer, modeline = false })
  assert(plugin.status() == "loaded")
  assert(loaded == 1, "Lazy setup repeated")
  assert(before == 1, "earlier event observer replayed")
  assert(after == 1, "new observer missed or doubled")
  assert(#package.loaders == loaders_before)
  local exists, entries = pcall(vim.api.nvim_get_autocmds,
    { group = "OrbitPluginDemand" })
  assert(not exists or #entries == 0)
end)

check("repeated demand and unchanged setup are idempotent", function()
  vim.api.nvim_exec_autocmds("UIEnter", { modeline = false })
  orbit.setup({ modules = { plugins = { enabled = true } } })
  assert(plugin.status() == "loaded" and loaded == 1)
end)

check("changing initialized plugin options is restart-only", function()
  orbit.setup({ modules = { plugins = { enabled = false } } })
  assert(orbit.get_config().modules.plugins.enabled)
  assert(orbit.get_pending_restart()["orbit.modules.plugins.enabled"] == false)
  assert(loaded == 1)
end)

package.preload.lazy = nil
package.loaded.lazy = nil
vim.go.loadplugins = original_loadplugins
print(string.format("%d plugin-demand tests passed.", passed))
