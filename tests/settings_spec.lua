-- Saved JSON must validate before any module applies side effects.
local script = debug.getinfo(1, "S").source:sub(2)
local root = vim.fn.fnamemodify(script, ":p:h:h")
vim.opt.rtp:prepend(root)

local orbit = require("orbit")
local settings = require("orbit.settings")
local passed = 0

local function check(label, fn)
  local ok, err = xpcall(fn, debug.traceback)
  if not ok then
    error("FAIL " .. label .. "\n" .. tostring(err), 0)
  end
  passed = passed + 1
  print("PASS " .. label)
end

local function with_settings(contents, fn)
  local path = vim.fn.tempname() .. ".json"
  if contents ~= nil then
    assert(vim.fn.writefile({ contents }, path) == 0)
  end
  local ok, err = xpcall(function()
    fn(path)
  end, debug.traceback)
  vim.fn.delete(path)
  assert(ok, err)
end

check("missing file uses declared defaults", function()
  with_settings(nil, function(path)
    local config, err, source = settings.read(path)
    assert(config ~= nil, tostring(err))
    assert(config.modules.editor.shiftwidth == 2)
    assert(config.modules.keymaps.enabled == true)
    assert(vim.deep_equal(source, {}))
    assert(vim.fn.filereadable(path) == 0)
  end)
end)

check("valid overrides preserve defaults and boolean false", function()
  with_settings('{"modules":{"editor":{"shiftwidth":4},"keymaps":{"enabled":false}}}', function(path)
    local config, err, source = settings.read(path)
    assert(config ~= nil, tostring(err))
    assert(config.modules.editor.shiftwidth == 4)
    assert(config.modules.editor.number == true)
    assert(config.modules.keymaps.enabled == false)
    assert(source.modules.editor.shiftwidth == 4)
  end)
end)

check("malformed JSON is rejected without rewriting source", function()
  with_settings('{"modules":', function(path)
    local config, err = settings.read(path)
    assert(config == nil and err:find("invalid JSON", 1, true), tostring(err))
    assert(table.concat(vim.fn.readfile(path), "\n") == '{"modules":')
  end)
end)

check("unknown options and JSON null are rejected", function()
  for _, contents in ipairs({ '{"modules":{"unknown":{}}}', '{"modules":{"editor":null}}' }) do
    with_settings(contents, function(path)
      local config, err = settings.read(path)
      assert(config == nil and type(err) == "string", "invalid input was accepted")
    end)
  end
end)

check("directory input is rejected", function()
  local path = vim.fn.tempname()
  vim.fn.mkdir(path, "p")
  local config, err = settings.read(path)
  vim.fn.delete(path, "rf")
  assert(config == nil and err:find("must refer to a file", 1, true), tostring(err))
end)

check("invalid settings preserve the last accepted configuration", function()
  orbit.setup({ modules = { editor = { shiftwidth = 4 } } })
  local before = orbit.get_config()
  with_settings('{"modules":{"editor":{"shiftwidth":99}}}', function(path)
    local ok, err = orbit.setup_from_file(path)
    assert(not ok and type(err) == "string")
    assert(vim.deep_equal(orbit.get_config(), before))
    assert(vim.o.shiftwidth == 4)
  end)
end)

check("explicit valid file activates modules", function()
  with_settings('{"modules":{"editor":{"shiftwidth":3}}}', function(path)
    local ok, err = orbit.setup_from_file(path)
    assert(ok, tostring(err))
    assert(orbit.get_config().modules.editor.shiftwidth == 3)
    assert(vim.o.shiftwidth == 3)
  end)
end)

check("empty path is rejected", function()
  local config, err = settings.read("")
  assert(config == nil and err:find("nonempty string", 1, true), tostring(err))
end)

print(string.format("%d saved settings tests passed.", passed))
