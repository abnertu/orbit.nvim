-- Real expression mappings must preserve menu/snippet cleanup and ownership.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
local orbit = require("orbit")
local commands = require("orbit.modules.commands")
local count = 0
local function check(label, fn)
  local ok, err = xpcall(fn, debug.traceback)
  assert(ok, "FAIL " .. label .. "\n" .. tostring(err))
  count = count + 1
  print("PASS " .. label)
end

local function map(mode)
  return vim.fn.maparg("<Esc>", mode, false, true)
end

local originals = {}
for _, mode in ipairs({ "n", "i", "s" }) do
  vim.keymap.set(mode, "<Esc>", "<Nop>", { desc = "User Escape " .. mode })
  originals[mode] = map(mode)
end

check("smart Escape is lazy and expression-mapped in every mapped mode", function()
  orbit.setup()
  assert(package.loaded["orbit.modules.corekeys.escape"] == nil)
  for _, mode in ipairs({ "n", "i", "s" }) do
    assert(type(map(mode).callback) == "function")
    assert(map(mode).expr == 1)
  end
end)

check("Escape returns the proper result and clears search highlights", function()
  local original_snippet = vim.snippet
  local stops = 0
  vim.snippet = { stop = function() stops = stops + 1 end }
  local ok, err = xpcall(function()
    for _, mode in ipairs({ "n", "i", "s" }) do
      assert(map(mode).callback() == "<Esc>")
    end
    assert(stops == 3)
  end, debug.traceback)
  vim.snippet = original_snippet
  assert(ok, err)
end)

check("loaded LuaSnip session is unlinked instead of native snippet", function()
  local original_snippet = vim.snippet
  local original_luasnip = package.loaded["luasnip"]
  local native_stops, unlink = 0, 0
  vim.snippet = { stop = function() native_stops = native_stops + 1 end }
  package.loaded["luasnip"] = {
    session = { current_nodes = {
      [vim.api.nvim_get_current_buf()] = true,
    } },
    unlink_current = function() unlink = unlink + 1 end,
  }
  local ok, err = pcall(function() assert(map("i").callback() == "<Esc>") end)
  package.loaded["luasnip"] = original_luasnip
  vim.snippet = original_snippet
  assert(ok, tostring(err))
  assert(unlink == 1 and native_stops == 0)
end)

check("menu Escape suppresses keystrokes and schedules menu cleanup", function()
  local original_state = package.loaded["menu.state"]
  local original_utils = package.loaded["menu.utils"]
  local original_schedule = vim.schedule
  local scheduled, closed = {}, 0
  package.loaded["menu.state"] = { bufids = { 5 } }
  package.loaded["menu.utils"] = {
    delete_old_menus = function() closed = closed + 1 end,
  }
  vim.schedule = function(cb) scheduled[#scheduled + 1] = cb end
  local ok, err = xpcall(function()
    assert(map("n").callback() == "")
    assert(#scheduled == 1 and closed == 0)
    scheduled[1]()
    assert(closed == 1)
    assert(map("s").callback() == "")
    scheduled[2]()
    assert(closed == 2)
  end, debug.traceback)
  vim.schedule = original_schedule
  package.loaded["menu.state"] = original_state
  package.loaded["menu.utils"] = original_utils
  assert(ok, err)
end)

check("missing menu utilities fail gracefully when menu state exists", function()
  local original_state = package.loaded["menu.state"]
  local original_utils = package.loaded["menu.utils"]
  local original_schedule = vim.schedule
  local queued
  package.loaded["menu.state"] = { bufids = { 1 } }
  package.loaded["menu.utils"] = nil
  vim.schedule = function(cb) queued = cb end
  local ok, err = xpcall(function()
    assert(map("n").callback() == "")
    assert(type(queued) == "function")
    queued()
  end, debug.traceback)
  vim.schedule = original_schedule
  package.loaded["menu.state"] = original_state
  package.loaded["menu.utils"] = original_utils
  assert(ok, err)
end)

check("a later module failure retains every owned mode binding", function()
  local before = orbit.get_config()
  local original = commands.setup
  commands.setup = function() error("injected Escape rollback failure") end
  local ok, err = pcall(orbit.setup, { modules = {
    corekeys = { enabled = false },
    commands = { enabled = false },
  } })
  commands.setup = original
  assert(not ok and tostring(err):find("injected Escape rollback failure", 1, true))
  assert(vim.deep_equal(orbit.get_config(), before))
  for _, mode in ipairs({ "n", "i", "s" }) do
    assert(type(map(mode).callback) == "function")
    assert(map(mode).expr == 1)
  end
end)

check("disabling corekeys restores all original user Escape mappings", function()
  orbit.setup({ modules = { corekeys = { enabled = false } } })
  for _, mode in ipairs({ "n", "i", "s" }) do
    local restored = map(mode)
    assert(restored.rhs == originals[mode].rhs)
    assert(restored.expr == originals[mode].expr)
  end
end)

print(string.format("%d smart Escape tests passed.", count))
