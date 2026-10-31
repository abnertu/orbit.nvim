-- Verify explicit reload preserves untouched local settings and mappings.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)

local orbit = require("orbit")
local keymaps = require("orbit.modules.keymaps")
local path = vim.fn.tempname() .. ".json"
local passed = 0

local function write(options)
  assert(vim.fn.writefile({ vim.json.encode(options) }, path) == 0)
end

local function check(label, callback)
  local ok, err = xpcall(callback, debug.traceback)
  if not ok then
    vim.fn.delete(path)
    error("FAIL " .. label .. "\n" .. tostring(err), 0)
  end
  passed = passed + 1
  print("PASS " .. label)
end

check("first load applies editor values", function()
  write({ modules = { editor = { shiftwidth = 4, number = true } } })
  local ok, err = orbit.setup_from_file(path)
  assert(ok, tostring(err))
  assert(vim.o.shiftwidth == 4)
  assert(vim.wo.number == true)
end)

check("unchanged settings keep user local overrides", function()
  vim.bo.shiftwidth = 7
  vim.wo.number = false
  local ok, err = orbit.reload_from_file(path)
  assert(ok, tostring(err))
  assert(vim.bo.shiftwidth == 7)
  assert(vim.wo.number == false)
  assert(orbit.get_config().modules.editor.shiftwidth == 4)
end)

check("changed editor field does not reset an unchanged field", function()
  write({ modules = { editor = { shiftwidth = 5, number = true } } })
  local ok, err = orbit.reload_from_file(path)
  assert(ok, tostring(err))
  assert(vim.bo.shiftwidth == 5)
  assert(vim.wo.number == false)
  assert(vim.api.nvim_get_option_value("shiftwidth", { scope = "global" }) == 5)
end)

check("unmodified keymaps module is not activated again", function()
  local old_setup = keymaps.setup
  keymaps.setup = function()
    error("keymaps should not be restarted on an editor-only change")
  end
  write({ modules = { editor = { shiftwidth = 6, number = true } } })
  local ok, err = orbit.reload_from_file(path)
  keymaps.setup = old_setup
  assert(ok, tostring(err))
  assert(vim.bo.shiftwidth == 6)
  assert(vim.wo.number == false)
end)

check("invalid reload does not change accepted state", function()
  local previous = orbit.get_config()
  assert(vim.fn.writefile({ '{"modules":{"editor":{"shiftwidth":99}}}' }, path) == 0)
  local ok, err = orbit.reload_from_file(path)
  assert(not ok and type(err) == "string")
  assert(vim.deep_equal(orbit.get_config(), previous))
  assert(vim.bo.shiftwidth == 6)
  assert(vim.wo.number == false)
end)

vim.fn.delete(path)
print(string.format("%d explicit reload tests passed.", passed))
