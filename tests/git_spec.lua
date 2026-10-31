-- Verify gitsigns Lazy declaration and marker compatibility without plugins.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)

local orbit = require("orbit")
local git = require("orbit.modules.git")
local count = 0

local function check(label, fn)
  local ok, err = xpcall(fn, debug.traceback)
  assert(ok, "FAIL " .. label .. "\n" .. tostring(err))
  count = count + 1
  print("PASS " .. label)
end

check("importing module does not initialize plugin code", function()
  assert(#git.spec() == 0)
  assert(not package.loaded.gitsigns)
end)

check("module defaults preserve legacy marker values", function()
  local defaults = require("orbit.config").resolve_module("git", {})
  assert(defaults.marks.add == "▎")
  assert(defaults.marks.delete == "")
  assert(defaults.staged.add == " ")
  assert(defaults.staged.change == " ")
  assert(defaults.staged.delete == " ")
end)

check("feature accepts nested LuaDoc options on initial setup", function()
  orbit.setup({ modules = {
    git = { marks = { change = "X" }, staged = { add = "+" } },
  } })
  local spec = git.spec()
  assert(#spec == 1 and spec[1][1] == "lewis6991/gitsigns.nvim")
  assert(spec[1].event == "User FilePost")
  assert(spec[1].opts.signs.change.text == "X")
  assert(spec[1].opts.signs.add.text == "▎")
  assert(spec[1].opts.signs.delete.text == "")
  assert(spec[1].opts.signs_staged.add.text == "+")
  assert(spec[1].opts.signs_staged.change.text == " ")
  assert(package.loaded.gitsigns == nil)
end)

check("manifest-backed import includes icons and gitsigns without a second inventory", function()
  local specs = require("orbit.plugins")
  local named = {}
  for _, spec in ipairs(specs) do
    named[spec[1]] = (named[spec[1]] or 0) + 1
  end
  assert(named["nvim-mini/mini.icons"] == 1)
  assert(named["lewis6991/gitsigns.nvim"] == 1)
  assert(named["folke/which-key.nvim"] == 1)
end)

check("disabling direct module setup removes its feature spec", function()
  local original = git.capture()
  git.setup({ enabled = false })
  assert(#git.spec() == 0)
  git.restore(original)
  assert(#git.spec() == 1)
end)

check("changes after root setup are held for restart", function()
  orbit.setup({ modules = { git = { enabled = false } } })
  assert(orbit.get_config().modules.git.enabled == true)
  assert(orbit.get_pending_restart()["orbit.modules.git.enabled"] == false)
end)

print(string.format("%d gitsigns spec tests passed.", count))
