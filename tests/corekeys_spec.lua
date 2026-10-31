-- Protect original user mappings through reconfiguration and rollback.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)

local orbit = require("orbit")
local commands = require("orbit.modules.commands")
local passed = 0

local function rhs(lhs)
  return vim.fn.maparg(lhs, "n")
end

local function check(label, fn)
  local ok, err = xpcall(fn, debug.traceback)
  assert(ok, "FAIL " .. label .. "\n" .. tostring(err))
  passed = passed + 1
  print("PASS " .. label)
end

vim.keymap.set("n", "<C-s>", "<cmd>echo 'user'<cr>", { silent = true })
local original_save = rhs("<C-s>")

check("core mappings replace their five owned slots", function()
  orbit.setup()
  assert(rhs("<C-s>"):lower():find("write", 1, true))
  assert(rhs("<C-h>") == "<C-w>h")
  assert(rhs("<C-j>") == "<C-w>j")
  assert(rhs("<C-k>") == "<C-w>k")
  assert(rhs("<C-l>") == "<C-w>l")
end)

check("changing the save key restores the original user binding", function()
  orbit.setup({ modules = { corekeys = { save = "<F12>" } } })
  assert(rhs("<C-s>") == original_save)
  assert(rhs("<F12>"):lower():find("write", 1, true))
  assert(rhs("<C-h>") == "<C-w>h")
end)

check("duplicate bindings are rejected before activation", function()
  local accepted = orbit.get_config()
  local ok, err = pcall(orbit.setup, { modules = {
    corekeys = { save = "<C-h>" },
  } })
  assert(not ok and tostring(err):find("duplicate core mapping", 1, true))
  assert(rhs("<F12>"):lower():find("write", 1, true))
  assert(vim.deep_equal(orbit.get_config(), accepted))
end)

check("later module failure restores previous bindings", function()
  local accepted = orbit.get_config()
  local prior = commands.setup
  commands.setup = function(opts)
    prior(opts)
    error("injected command failure")
  end
  local ok, err = pcall(orbit.setup, { modules = {
    corekeys = { save = "<F11>" },
    commands = { name = "OrbitFailed" },
  } })
  commands.setup = prior
  assert(not ok and tostring(err):find("injected command failure", 1, true))
  assert(rhs("<F12>"):lower():find("write", 1, true))
  assert(rhs("<F11>") == "")
  assert(rhs("<C-s>") == original_save)
  assert(vim.deep_equal(orbit.get_config(), accepted))
end)

check("disabling restores the prior owner mapping", function()
  orbit.setup({ modules = { corekeys = { enabled = false } } })
  assert(rhs("<C-s>") == original_save)
  assert(rhs("<F12>") == "")
end)

check("reenabling does not stack mappings", function()
  orbit.setup()
  assert(rhs("<C-s>"):lower():find("write", 1, true))
  assert(rhs("<C-h>") == "<C-w>h")
end)

print(string.format("%d core keymap tests passed.", passed))
