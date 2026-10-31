-- Test command ownership and explicit settings writes through real Neovim APIs.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
local orbit = require("orbit")
local commands = require("orbit.modules.commands")
local path = vim.fn.tempname() .. ".json"
local count = 0

local function check(label, callback)
  local ok, err = xpcall(callback, debug.traceback)
  assert(ok, "FAIL " .. label .. "\n" .. tostring(err))
  count = count + 1
  print("PASS " .. label)
end

local function exists(name)
  return vim.api.nvim_get_commands({})[name] ~= nil
end

check("setup does not write settings and owns one command", function()
  orbit.setup({ modules = { commands = { path = path } } })
  assert(exists("OrbitSettings"))
  assert(vim.fn.filereadable(path) == 0)
end)

check("open creates schema-linked settings without overwriting existing data", function()
  vim.cmd("OrbitSettings open")
  assert(vim.fn.filereadable(path) == 1, "settings file was not created")
  local actual = vim.fs.normalize(vim.api.nvim_buf_get_name(0))
  local expected = vim.fs.normalize(path)
  if vim.fn.has("win32") == 1 then
    actual, expected = actual:lower(), expected:lower()
  end
  assert(actual == expected,
    "wrong settings buffer: " .. actual .. " instead of " .. expected)
  local saved = vim.json.decode(table.concat(vim.fn.readfile(path), "\n"))
  local schema = assert(vim.api.nvim_get_runtime_file("settings.schema.json", false)[1])
  assert(saved["$schema"] == vim.uri_from_fname(schema))
  local custom = '{"modules":{"editor":{"shiftwidth":4}}}'
  assert(vim.fn.writefile({ custom }, path) == 0)
  vim.cmd("OrbitSettings open")
  assert(table.concat(vim.fn.readfile(path), "\n") == custom)
end)

check("reload activates validated JSON", function()
  vim.cmd("OrbitSettings reload")
  assert(orbit.get_config().modules.editor.shiftwidth == 4)
  assert(orbit.get_config().modules.commands.path == vim.fs.normalize(path))
  assert(vim.api.nvim_get_option_value("shiftwidth", { scope = "global" }) == 4)
end)

check("invalid reload warns but preserves prior configuration", function()
  local before = orbit.get_config()
  vim.fn.writefile({ '{"modules":' }, path)
  local notified, original = {}, vim.notify
  vim.notify = function(message, level)
    notified[#notified + 1] = { message, level }
  end
  local ok, err = pcall(vim.cmd, "OrbitSettings reload")
  vim.notify = original
  assert(ok, tostring(err))
  assert(#notified == 1 and notified[1][2] == vim.log.levels.WARN,
    "expected warning, got " .. vim.inspect(notified) ..
      "; file=" .. table.concat(vim.fn.readfile(path), "\\n") ..
      "; path=" .. path)
  assert(vim.deep_equal(orbit.get_config(), before))
end)

check("info shows accepted values in an isolated buffer", function()
  vim.cmd("OrbitSettings info")
  local b = vim.api.nvim_get_current_buf()
  assert(vim.bo[b].buftype == "nofile")
  local text = table.concat(vim.api.nvim_buf_get_lines(b, 0, -1, false), "\n")
  assert(text:find("Settings: ", 1, true))
  assert(text:find("modules.editor.shiftwidth = 4", 1, true))
  vim.cmd.close()
end)

check("renaming command cleans up its previous registration", function()
  orbit.setup({ modules = { commands = { name = "OrbitConfig", path = path } } })
  assert(exists("OrbitConfig") and not exists("OrbitSettings"))
end)

check("failure after creation restores previous command", function()
  local accepted = orbit.get_config()
  local original = commands.setup
  commands.setup = function(opts)
    original(opts)
    error("injected command failure")
  end
  local ok, err = pcall(orbit.setup, { modules = {
    commands = { name = "OrbitBroken", path = path },
  } })
  commands.setup = original
  assert(not ok and tostring(err):find("injected command failure", 1, true))
  assert(exists("OrbitConfig") and not exists("OrbitBroken"))
  assert(vim.deep_equal(orbit.get_config(), accepted))
end)

check("existing third-party commands cannot be overwritten", function()
  vim.api.nvim_create_user_command("OrbitReserved", function() end, {})
  local accepted = orbit.get_config()
  local ok, err = pcall(orbit.setup, { modules = {
    commands = { name = "OrbitReserved", path = path },
  } })
  assert(not ok and tostring(err):find("refusing to overwrite", 1, true))
  assert(exists("OrbitReserved") and exists("OrbitConfig"))
  assert(vim.deep_equal(orbit.get_config(), accepted))
  vim.api.nvim_del_user_command("OrbitReserved")
end)

check("disable and re-enable remove only the module's command", function()
  orbit.setup({ modules = { commands = { enabled = false } } })
  assert(not exists("OrbitConfig"))
  orbit.setup({ modules = { commands = { path = path } } })
  assert(exists("OrbitSettings"))
end)

vim.fn.delete(path)
print(string.format("%d command tests passed.", count))
