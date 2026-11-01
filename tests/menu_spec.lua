-- Hermetic owner contracts; real mouse and upstream UI run separately.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
local orbit = require("orbit")
local owner = require("orbit.modules.menu")
local passed = 0
local function check(label, run)
  local ok, err = xpcall(run, debug.traceback)
  assert(ok, "FAIL " .. label .. "\n" .. tostring(err))
  passed = passed + 1
  print("PASS " .. label)
end

check("setup and spec collection keep external imports deferred", function()
  orbit.setup({ modules = { menu = { enabled = false } } })
  assert(#owner.spec() == 0)
  owner.setup()
  local spec = owner.spec()[1]
  assert(spec[1] == "Orbit-Lua/menu" and spec.dependencies[1] == "Orbit-Lua/volt")
  assert(#spec.keys == 4)
  for _, key in ipairs(spec.keys) do
    assert(vim.deep_equal(key.mode, { "n", "v" }))
  end
  for _, name in ipairs({ "menu", "volt", "nvim-tree.api", "orbit.modules.menu.runtime" }) do
    assert(not package.loaded[name], name .. " imported before demand")
  end
end)

check("validation and failed activation preserve accepted state and user keys", function()
  local snapshot = owner.capture()
  assert(not pcall(owner.setup, { enabled = "yes" }))
  assert(vim.deep_equal(snapshot, owner.capture()))
  vim.keymap.set("n", "<RightMouse>", "<Nop>", { desc = "user right mouse" })
  local commands = require("orbit.modules.commands")
  local setup = commands.setup
  commands.setup = function() error("menu rollback") end
  assert(not pcall(orbit.setup, { modules = { commands = { enabled = false } } }))
  commands.setup = setup
  assert(vim.fn.maparg("<RightMouse>", "n", false, true).desc == "user right mouse")
  assert(vim.deep_equal(snapshot, owner.capture()))
end)

check("saved settings retain defaults and defer enabled changes until restart", function()
  local path = vim.fn.tempname()
  vim.fn.writefile({ '{"modules":{"menu":{"enabled":false}}}' }, path)
  assert(orbit.setup_from_file(path))
  assert(not orbit.get_config().modules.menu.enabled)
  vim.fn.writefile({ '{}' }, path)
  assert(orbit.reload_from_file(path))
  assert(not orbit.get_config().modules.menu.enabled)
  assert(orbit.get_pending_restart()["orbit.modules.menu.enabled"] == true)
  assert(vim.deep_equal(vim.fn.readfile(path), { '{}' }))
  vim.fn.writefile({ '{"modules":{"menu":{"enabled":0}}}' }, path)
  assert(not orbit.reload_from_file(path))
  assert(not orbit.get_config().modules.menu.enabled)
  vim.fn.delete(path)
end)

-- Test the same activation/open/action entry points with local upstream doubles.
local mouse = { winid = 0 }
-- No physical mouse exists in this fixture. Native popup behavior is live-tested.
vim.o.mousemodel = "extend"
local original_mouse = vim.fn.getmousepos
vim.fn.getmousepos = function() return mouse end
local state = { bufids = {} }
local entries
local mappings = { auto_close = function() error("unadapted auto_close") end }
package.loaded["menu.state"] = state
package.loaded["menu.mappings"] = mappings
package.loaded.menu = {
  open = function(items)
    entries = items
    local buffer = vim.api.nvim_create_buf(false, true)
    state.bufids = { buffer }
    vim.keymap.set("n", "q", function()
      for _, id in ipairs(state.bufids) do vim.api.nvim_buf_delete(id, { force = true }) end
      state.bufids = {}
    end, { buffer = buffer })
    mappings.auto_close()
  end,
}
owner.setup()
owner.spec()[1].config()
local runtime = require("orbit.modules.menu.runtime")
local source = vim.api.nvim_get_current_win()
local buffer = vim.api.nvim_get_current_buf()
mouse.winid = source
local function open()
  owner.spec()[1].keys[1][2]()
  assert(#state.bufids == 1)
end
local function find(items, text)
  for _, item in ipairs(items) do
    if item.name:find(text, 1, true) then return item end
  end
  error("missing item " .. text)
end

check("temporary Normal and Visual input maps restore original local and global bindings", function()
  local calls = 0
  for _, mode in ipairs({ "n", "x" }) do
    vim.keymap.set(mode, "<LeftMouse>", function() calls = calls + 1 end, { desc = "global mouse" })
    vim.keymap.set(mode, "<LeftMouse>", function() calls = calls + 1 end, { buffer = buffer, desc = "local mouse" })
    vim.keymap.set(mode, "<Esc>", function() calls = calls + 1 end, { buffer = buffer, desc = "local escape" })
  end
  open()
  runtime.install()
  open() -- replacement must release and reacquire exactly once.
  runtime.close()
  for _, mode in ipairs({ "n", "x" }) do
    for _, lhs in ipairs({ "<LeftMouse>", "<Esc>" }) do
      local binding = vim.fn.maparg(lhs, mode, false, true)
      assert(binding.desc == (lhs == "<Esc>" and "local escape" or "local mouse"))
      binding.callback()
    end
    vim.keymap.del(mode, "<LeftMouse>", { buffer = buffer })
    local global = vim.fn.maparg("<LeftMouse>", mode, false, true)
    assert(global.desc == "global mouse")
    global.callback()
  end
  assert(calls == 6)
end)

check("cleanup preserves a user mapping replaced while open", function()
  open()
  vim.keymap.set("x", "<Esc>", "<Nop>", { buffer = buffer, desc = "replacement" })
  vim.keymap.set("n", "<LeftMouse>", "<Nop>", { desc = "replacement" })
  runtime.close()
  assert(vim.fn.maparg("<Esc>", "x", false, true).desc == "replacement")
  assert(vim.fn.maparg("<LeftMouse>", "n", false, true).desc == "replacement")
end)

check("configured shortcuts and current leaders dispatch after disposal", function()
  orbit.setup({ modules = { corekeys = { save = "<F6>" } } })
  local sent = {}
  local feedkeys = vim.api.nvim_feedkeys
  vim.api.nvim_feedkeys = function(keys, mode)
    assert(#state.bufids == 0)
    assert(mode == "m" and vim.api.nvim_get_current_win() == source)
    sent[#sent + 1] = keys
  end
  open()
  local save = find(entries, "Save File")
  assert(save.rtxt == "<F6>")
  save.cmd()
  assert(vim.wait(1000, function() return #sent == 1 end, 10))
  assert(sent[1] == vim.keycode("<F6>"))
  open()
  local format = find(entries, "Format File")
  assert(format.rtxt == orbit.get_config().modules.formatter.key)
  vim.g.mapleader = ","
  format.cmd()
  assert(vim.wait(1000, function() return #sent == 2 end, 10))
  vim.api.nvim_feedkeys = feedkeys
  assert(sent[2] == ",fm")
end)

check("tree actions capture the node and reject nil rather than falling back", function()
  local current = { name = "original", absolute_path = "/original", type = "file" }
  local received
  local function action(node) received = node or current end
  local tree = { get_node_under_cursor = function() return current end }
  setmetatable(tree, { __index = function() return action end })
  local fs = setmetatable({ copy = setmetatable({}, { __index = function() return action end }) },
    { __index = function() return action end })
  package.loaded["nvim-tree.api"] = { tree = tree, node = { open = setmetatable({}, { __index = function() return action end }) },
    fs = fs, filter = { dotfiles = { toggle = action } } }
  vim.bo[buffer].filetype = "NvimTree"
  open()
  local captured = current
  current = { name = "later", absolute_path = "/later", type = "file" }
  entries[1].cmd()
  assert(vim.wait(1000, function() return received ~= nil end, 10))
  assert(received == captured)
  current, received = nil, nil
  open()
  current = captured
  local notify = vim.notify
  local errors = {}
  vim.notify = function(message) errors[#errors + 1] = message end
  entries[1].cmd()
  assert(vim.wait(1000, function() return #errors > 0 end, 10))
  vim.notify = notify
  assert(received == nil and errors[1]:find("No tree node", 1, true))
  vim.bo[buffer].filetype = ""
end)

check("invalid mouse sources and deferred disposed sources execute no action", function()
  mouse.winid = 0
  runtime.open()
  assert(#state.bufids == 0)
  mouse.winid = source
  open()
  local save = find(entries, "Save File")
  local ran = false
  vim.keymap.set("n", "<F6>", function() ran = true end)
  save.cmd()
  local replacement = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_win_set_buf(source, replacement)
  vim.wait(50, function() return false end, 10)
  assert(not ran)
  vim.api.nvim_win_set_buf(source, buffer)
  vim.api.nvim_buf_delete(replacement, { force = true })
end)

vim.fn.getmousepos = original_mouse
print(string.format("%d menu owner tests passed.", passed))
