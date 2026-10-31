-- Verify native comment mapping and settings-command dispatch across modes.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
local orbit = require("orbit")
local commands = require("orbit.modules.commands")
local count = 0

local function check(name, fn)
  local ok, err = xpcall(fn, debug.traceback)
  assert(ok, "FAIL " .. name .. "\n" .. tostring(err))
  count = count + 1
  print("PASS " .. name)
end

local function mapping(mode, lhs)
  return vim.fn.maparg(lhs, mode, false, true)
end

for _, mode in ipairs({ "n", "v" }) do
  vim.keymap.set(mode, " /", "<cmd>echo 'original comment'<cr>", { silent = true })
  vim.keymap.set(mode, ",/", "<cmd>echo 'comma comment'<cr>", { silent = true })
end
local old = {
  n_space = mapping("n", " /").rhs,
  v_space = mapping("v", " /").rhs,
  n_comma = mapping("n", ",/").rhs,
  v_comma = mapping("v", ",/").rhs,
}

check("normal and visual comments keep native gc remapping", function()
  orbit.setup()
  local normal = mapping("n", " /")
  local visual = mapping("v", " /")
  assert(normal.rhs == "gcc" and normal.noremap == 0)
  assert(visual.rhs == "gc" and visual.noremap == 0)
  assert(type(mapping("n", " uc").callback) == "function")
end)

check("comment shortcuts use native Neovim comment operators", function()
  local previous = vim.api.nvim_get_current_buf()
  local buffer = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_set_current_buf(buffer)
  vim.bo[buffer].commentstring = "-- %s"
  vim.api.nvim_buf_set_lines(buffer, 0, -1, false, {
    "first line", "second line", "third line",
  })
  local ok, err = xpcall(function()
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    vim.api.nvim_feedkeys(vim.keycode(" /"), "xt", false)
    local lines = vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
    assert(lines[1]:match("^%-%- "), "normal comment mapping did not execute")
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    vim.api.nvim_feedkeys(vim.keycode("Vj /"), "xt", false)
    lines = vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
    assert(lines[2]:match("^%-%- ") and lines[3]:match("^%-%- "),
      "visual comment mapping did not execute")
  end, debug.traceback)
  vim.api.nvim_set_current_buf(previous)
  vim.api.nvim_buf_delete(buffer, { force = true })
  assert(ok, err)
end)

local path = vim.fn.tempname() .. ".json"
check("settings key follows the renamed command at invocation", function()
  orbit.setup({ modules = { commands = {
    name = "OrbitActionSettings", path = path,
  } } })
  mapping("n", " uc").callback()
  assert(vim.fn.filereadable(path) == 1)
  assert(vim.fs.normalize(vim.api.nvim_buf_get_name(0)) == vim.fs.normalize(path))
  vim.cmd.bdelete({ bang = true })
  vim.fn.delete(path)
end)

check("disabled settings command warns without invoking an orphan", function()
  orbit.setup({ modules = { commands = { enabled = false } } })
  local original = vim.notify
  local observed
  vim.notify = function(message, level)
    observed = { message, level }
  end
  local ok, err = pcall(function() mapping("n", " uc").callback() end)
  vim.notify = original
  assert(ok, tostring(err))
  assert(observed and observed[1]:find("disabled", 1, true))
  assert(observed[2] == vim.log.levels.WARN)
end)

check("normal comment collides with the configurable save shortcut", function()
  local accepted = orbit.get_config()
  local ok, err = pcall(orbit.setup, { modules = {
    keymaps = { save = "<leader>/" },
  } })
  assert(not ok and tostring(err):find("duplicate leader mapping", 1, true))
  assert(vim.deep_equal(orbit.get_config(), accepted))
  assert(mapping("n", " /").rhs == "gcc")
  assert(mapping("v", " /").rhs == "gc")
end)

check("downstream failure preserves both mode maps and the leader", function()
  local accepted = orbit.get_config()
  local original = commands.setup
  commands.setup = function() error("injected settings owner failure") end
  local ok, err = pcall(orbit.setup, { modules = {
    keymaps = { leader = ",", save = "<leader>w" },
    commands = { enabled = true, name = "OrbitActionBroken", path = path },
  } })
  commands.setup = original
  assert(not ok and tostring(err):find("injected settings owner failure", 1, true))
  assert(vim.deep_equal(orbit.get_config(), accepted))
  assert(vim.g.mapleader == " ")
  assert(mapping("n", " /").rhs == "gcc")
  assert(mapping("v", " /").rhs == "gc")
  assert(mapping("n", ",/").rhs == old.n_comma)
  assert(mapping("v", ",/").rhs == old.v_comma)
end)

check("changing leader restores original normal and visual maps", function()
  orbit.setup({ modules = { keymaps = {
    leader = ",", save = "<leader>w",
  } } })
  assert(mapping("n", " /").rhs == old.n_space)
  assert(mapping("v", " /").rhs == old.v_space)
  assert(mapping("n", ",/").rhs == "gcc")
  assert(mapping("v", ",/").rhs == "gc")
end)

check("disabling keymaps restores both current and former leader maps", function()
  orbit.setup({ modules = { keymaps = { enabled = false } } })
  assert(mapping("n", " /").rhs == old.n_space)
  assert(mapping("v", " /").rhs == old.v_space)
  assert(mapping("n", ",/").rhs == old.n_comma)
  assert(mapping("v", ",/").rhs == old.v_comma)
  assert(vim.fn.maparg(",uc", "n") == "")
end)

print(string.format("%d comment and settings keymap tests passed.", count))
