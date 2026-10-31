-- Exercise saved settings observation through real buffer writes.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)

local orbit = require("orbit")
local path = vim.fn.tempname() .. ".json"
local unrelated = vim.fn.tempname() .. ".json"
local passed = 0

local function check(name, callback)
  local ok, err = xpcall(callback, debug.traceback)
  assert(ok, "FAIL " .. name .. ": " .. tostring(err))
  passed = passed + 1
  print("PASS " .. name)
end

local function write_current(text)
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { text })
  vim.cmd.write()
end

check("opt-in observation applies settings saved from a buffer", function()
  assert(vim.fn.writefile({ '{"modules":{"editor":{"shiftwidth":4}}}' }, path) == 0)
  local ok, err = orbit.setup_from_file(path)
  assert(ok, tostring(err))
  orbit.watch_settings(path)

  vim.cmd.edit(vim.fn.fnameescape(path))
  write_current('{"modules":{"editor":{"shiftwidth":5}}}')
  assert(orbit.get_config().modules.editor.shiftwidth == 5)
  assert(vim.bo.shiftwidth == 5)
end)

check("repeated watch setup replaces rather than duplicates callbacks", function()
  orbit.watch_settings(path)
  orbit.watch_settings(path)
  local callbacks = vim.api.nvim_get_autocmds({
    group = "OrbitSettingsWatch",
    event = "BufWritePost",
  })
  assert(#callbacks == 1, "settings observer has duplicate callbacks")
end)

check("other file saves do not activate the settings observer", function()
  assert(vim.fn.writefile({ "{}" }, unrelated) == 0)
  vim.cmd.edit(vim.fn.fnameescape(unrelated))
  write_current('{"modules":{"editor":{"shiftwidth":6}}}')
  assert(orbit.get_config().modules.editor.shiftwidth == 5)
end)

check("invalid saved JSON never replaces accepted settings", function()
  local previous = orbit.get_config()
  local notified = {}
  local original_notify = vim.notify
  vim.notify = function(message, level)
    notified[#notified + 1] = { message, level }
  end
  local ok, err = xpcall(function()
    vim.cmd.edit(vim.fn.fnameescape(path))
    write_current('{"modules":')
  end, debug.traceback)
  vim.notify = original_notify

  assert(ok, tostring(err))
  assert(#notified == 1)
  assert(notified[1][2] == vim.log.levels.WARN)
  assert(vim.deep_equal(orbit.get_config(), previous))
  assert(table.concat(vim.fn.readfile(path), "\n") == '{"modules":')
end)

check("unwatch removes subscriptions", function()
  orbit.unwatch_settings()
  -- Validate removal through a real buffer save.
  vim.cmd.edit(vim.fn.fnameescape(path))
  write_current('{"modules":{"editor":{"shiftwidth":7}}}')
  assert(orbit.get_config().modules.editor.shiftwidth == 5)
end)

vim.fn.delete(path)
vim.fn.delete(unrelated)
print(string.format("%d settings observation tests passed.", passed))
