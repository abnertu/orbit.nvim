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
vim.keymap.set("x", "J", "<cmd>echo 'user-move-down'<cr>", { silent = true })
vim.keymap.set("x", "K", "<cmd>echo 'user-move-up'<cr>", { silent = true })
vim.keymap.set("i", "jk", "<cmd>echo 'user-insert'<cr>", { silent = true })
vim.keymap.set("t", "<C-x>", "<cmd>echo 'user-terminal'<cr>", { silent = true })
vim.keymap.set("n", "<Tab>", "<cmd>echo 'user-next'<cr>", { silent = true })
vim.keymap.set("n", "<S-Tab>", "<cmd>echo 'user-prev'<cr>", { silent = true })
local previous_next = rhs("<Tab>")
local previous_prev = rhs("<S-Tab>")
local previous = {
  { "n", ";", vim.fn.maparg(";", "n") },
  { "x", ">", vim.fn.maparg(">", "x") },
  { "x", "J", vim.fn.maparg("J", "x") },
  { "x", "K", vim.fn.maparg("K", "x") },
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

check("common editing shortcuts use their modes and actions", function()
  local expected = {
    { "n", "<C-c>", "%y+" },
    { "n", ";", ":" },
    { "n", "<", "<<" },
    { "n", ">", ">>" },
    { "x", "<", "<gv" },
    { "x", ">", ">gv" },
    { "x", "p", "P" },
    { "i", "jk", "<esc>" },
    { "n", "Q", "q" },
    { "n", "q", "<nop>" },
    { "n", "K", "<nop>" },
    { "t", "<C-x>", "<c-\\><c-n>" },
  }
  for _, item in ipairs(expected) do
    local actual = vim.fn.maparg(item[2], item[1])
    -- Visual P must be case-sensitive: lowercase p changes registers.
    local matches = item[1] == "x" and item[2] == "p"
      and actual == item[3]
      or (item[1] ~= "x" or item[2] ~= "p")
        and actual:lower():find(item[3], 1, true) ~= nil
    assert(matches,
      string.format("missing %s %s: %s", item[1], item[2], actual))
  end
end)

check("visual J/K callbacks preserve selection and move in opposite directions", function()
  local down = vim.fn.maparg("J", "x", false, true)
  local up = vim.fn.maparg("K", "x", false, true)
  assert(type(down.callback) == "function")
  assert(type(up.callback) == "function")

  local original_feedkeys, original_cmd = vim.api.nvim_feedkeys, vim.cmd
  local actions = {}
  vim.api.nvim_feedkeys = function(keys, mode, escape)
    assert(type(keys) == "string" and #keys > 0)
    assert(mode == "x" and escape == false)
    actions[#actions + 1] = "escape"
  end
  vim.cmd = function(command)
    actions[#actions + 1] = command
  end
  local ok, err = xpcall(function()
    down.callback()
    up.callback()
  end, debug.traceback)
  vim.api.nvim_feedkeys, vim.cmd = original_feedkeys, original_cmd
  assert(ok, err)
  assert(vim.deep_equal(actions, {
    "escape", "'<,'>move '>+1", "normal! gv-gv",
    "escape", "'<,'>move '<-2", "normal! gv-gv",
  }))
end)

local function tab_key(lhs)
  return vim.fn.maparg(lhs, "n", false, true).callback
end

local function delete_buffers(buffers)
  for _, buffer in ipairs(buffers) do
    if vim.api.nvim_buf_is_valid(buffer) then
      vim.api.nvim_buf_delete(buffer, { force = true })
    end
  end
end

check("buffer cycling follows the tracked order and is lazy-loaded", function()
  assert(package.loaded["orbit.modules.corekeys.buffers"] == nil)
  assert(type(tab_key("<Tab>")) == "function")
  assert(type(tab_key("<S-Tab>")) == "function")
  local current = vim.api.nvim_get_current_buf()
  local first = vim.api.nvim_create_buf(true, false)
  local second = vim.api.nvim_create_buf(true, false)
  local third = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_set_current_buf(first)

  tab_key("<Tab>")()
  assert(vim.api.nvim_get_current_buf() == second)
  tab_key("<Tab>")()
  assert(vim.api.nvim_get_current_buf() == third)
  tab_key("<S-Tab>")()
  tab_key("<S-Tab>")()
  assert(vim.api.nvim_get_current_buf() == first)

  vim.api.nvim_set_current_buf(current)
  delete_buffers({ first, second, third })
end)

check("buffer cycling ignores tab variables from other owners", function()
  local current = vim.api.nvim_get_current_buf()
  local first = vim.api.nvim_create_buf(true, false)
  local second = vim.api.nvim_create_buf(true, false)
  local third = vim.api.nvim_create_buf(true, false)
  vim.t.bufs = { first, third, second }
  vim.api.nvim_set_current_buf(first)

  tab_key("<Tab>")()
  assert(vim.api.nvim_get_current_buf() == second, "vim.t.bufs must not reorder cycling")

  vim.t.bufs = nil
  vim.api.nvim_set_current_buf(current)
  delete_buffers({ first, second, third })
end)

check("buffer cycling stays within the current tab", function()
  local outer = vim.api.nvim_create_buf(true, false)
  vim.cmd("tabnew")
  local tab_first = vim.api.nvim_get_current_buf()
  local tab_second = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_set_current_buf(tab_second)

  tab_key("<Tab>")()
  assert(vim.api.nvim_get_current_buf() == tab_first,
    "next must wrap within the tab: " .. vim.inspect(require("orbit.buffers").list()))
  tab_key("<S-Tab>")()
  assert(vim.api.nvim_get_current_buf() == tab_second)
  assert(not vim.list_contains(require("orbit.buffers").list(), outer))

  vim.cmd("tabclose!")
  delete_buffers({ tab_first, tab_second, outer })
end)

check("buffer cycling skips unloaded and unlisted buffers", function()
  local current = vim.api.nvim_get_current_buf()
  local first = vim.api.nvim_create_buf(true, false)
  local unloaded = vim.api.nvim_create_buf(true, false)
  local unlisted = vim.api.nvim_create_buf(true, false)
  local second = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_delete(unloaded, { unload = true })
  assert(vim.api.nvim_buf_is_valid(unloaded) and not vim.api.nvim_buf_is_loaded(unloaded))
  vim.bo[unlisted].buflisted = false
  vim.api.nvim_set_current_buf(first)

  tab_key("<Tab>")()
  assert(vim.api.nvim_get_current_buf() == second, "next must skip ineligible buffers")
  tab_key("<S-Tab>")()
  assert(vim.api.nvim_get_current_buf() == first)

  vim.api.nvim_set_current_buf(current)
  delete_buffers({ first, unloaded, unlisted, second })
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
  assert(mapping_rhs("i", "jk") == "<esc>", vim.inspect(vim.fn.maparg("jk", "i", false, true)))
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

check("disabling restores original buffer cycling keys", function()
  assert(rhs("<Tab>") == previous_next)
  assert(rhs("<S-Tab>") == previous_prev)
  local buffers = require("orbit.buffers")
  assert(not buffers.attached("corekeys"))
  -- The group stays only while another owner, such as the tab line, uses it.
  assert(pcall(vim.api.nvim_get_autocmds, { group = "OrbitBufferOrder" })
    == buffers.attached("tabline"), "the last owner must remove the buffer-order group")
end)

check("reenabling does not stack mappings", function()
  orbit.setup()
  assert(require("orbit.buffers").attached("corekeys"))
  local groups = vim.api.nvim_get_autocmds({ group = "OrbitBufferOrder" })
  orbit.setup({ modules = { corekeys = { save = "<F10>" } } })
  orbit.setup()
  assert(#vim.api.nvim_get_autocmds({ group = "OrbitBufferOrder" }) == #groups,
    "repeated setup must not duplicate buffer-order handlers")
  assert(rhs("<C-s>"):lower():find("write", 1, true))
  assert(rhs("<C-h>"):lower() == "<c-w>h")
end)

check("repeated rollback keeps jk and smart Escape mappings intact", function()
  local prior = commands.setup
  for index = 1, 30 do
    local accepted = orbit.get_config()
    local escape = vim.fn.maparg("jk", "i")
    assert(escape:lower() == "<esc>", "initial jk mapping missing")
    commands.setup = function() error("injected repeated rollback") end
    local ok, err = pcall(orbit.setup, { modules = {
      corekeys = { save = "<F11>" },
      commands = { enabled = false },
    } })
    commands.setup = prior
    assert(not ok and tostring(err):find("injected repeated rollback", 1, true))
    assert(not tostring(err):find("rollback failed", 1, true), tostring(err))
    assert(vim.deep_equal(orbit.get_config(), accepted))
    assert(vim.fn.maparg("jk", "i") == escape,
      "jk mapping disappeared at iteration " .. index ..
      ": " .. vim.inspect(vim.fn.maparg("jk", "i", false, true)))
    for _, mode in ipairs({ "n", "i", "s" }) do
      local current = vim.fn.maparg("<Esc>", mode, false, true)
      assert(type(current.callback) == "function" and current.expr == 1,
        "Escape mapping lost in mode " .. mode .. " at iteration " .. index)
    end
  end
end)

print(string.format("%d core keymap tests passed.", passed))
