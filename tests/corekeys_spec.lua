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
-- User-owned mappings on fixed slots must also survive disable and rollback.
vim.keymap.set("n", ";", "<cmd>echo 'user-command'<cr>", { silent = true })
vim.keymap.set("x", ">", "<cmd>echo 'user-visual'<cr>", { silent = true })
vim.keymap.set("i", "jk", "<cmd>echo 'user-insert'<cr>", { silent = true })
vim.keymap.set("t", "<C-x>", "<cmd>echo 'user-terminal'<cr>", { silent = true })
local previous = {
  { "n", ";", vim.fn.maparg(";", "n") },
  { "x", ">", vim.fn.maparg(">", "x") },
  { "i", "jk", vim.fn.maparg("jk", "i") },
  { "t", "<C-x>", vim.fn.maparg("<C-x>", "t") },
}

local function mapping_rhs(mode, lhs)
  return vim.fn.maparg(lhs, mode):lower()
end

check("core mappings replace their five owned slots", function()
  orbit.setup()
  assert(rhs("<C-s>"):lower():find("write", 1, true))
  assert(rhs("<C-h>"):lower() == "<c-w>h")
  assert(rhs("<C-j>"):lower() == "<c-w>j")
  assert(rhs("<C-k>"):lower() == "<c-w>k")
  assert(rhs("<C-l>"):lower() == "<c-w>l")
end)

check("common editing shortcuts use the legacy modes and actions", function()
  local expected = {
    { "n", "<C-c>", "%y+" },
    { "n", ";", ":" },
    { "n", "<", "<<" },
    { "n", ">", ">>" },
    { "x", "<", "<gv" },
    { "x", ">", ">gv" },
    { "x", "p", "p" },
    { "i", "jk", "<esc>" },
    { "n", "Q", "q" },
    { "n", "q", "<nop>" },
    { "n", "K", "<nop>" },
    { "t", "<C-x>", "<c-\\><c-n>" },
  }
  for _, item in ipairs(expected) do
    local actual = mapping_rhs(item[1], item[2])
    assert(actual:find(item[3], 1, true),
      string.format("missing %s %s: %s", item[1], item[2], actual))
  end
end)

check("changing the save key restores the original user binding", function()
  orbit.setup({ modules = { corekeys = { save = "<F12>" } } })
  assert(rhs("<C-s>") == original_save)
  assert(rhs("<F12>"):lower():find("write", 1, true))
  assert(rhs("<C-h>"):lower() == "<c-w>h")
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

check("fixed editing key collisions are rejected before activation", function()
  local accepted = orbit.get_config()
  local ok, err = pcall(orbit.setup, { modules = {
    corekeys = { save = ";" },
  } })
  assert(not ok and tostring(err):find("duplicate core mapping", 1, true))
  assert(rhs("<F12>"):lower():find("write", 1, true))
  assert(mapping_rhs("n", ";") == ":")
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
  assert(mapping_rhs("n", ";") == ":")
  assert(mapping_rhs("x", ">") == ">gv")
  assert(mapping_rhs("i", "jk") == "<esc>")
  assert(vim.deep_equal(orbit.get_config(), accepted))
end)

check("disabling restores the prior owner mapping", function()
  orbit.setup({ modules = { corekeys = { enabled = false } } })
  assert(rhs("<C-s>") == original_save)
  assert(rhs("<F12>") == "")
end)

check("disabling restores user maps from every edited mode", function()
  for _, item in ipairs(previous) do
    assert(vim.fn.maparg(item[2], item[1]) == item[3],
      string.format("lost user %s %s mapping", item[1], item[2]))
  end
end)

check("reenabling does not stack mappings", function()
  orbit.setup()
  assert(rhs("<C-s>"):lower():find("write", 1, true))
  assert(rhs("<C-h>"):lower() == "<c-w>h")
end)

print(string.format("%d core keymap tests passed.", passed))
