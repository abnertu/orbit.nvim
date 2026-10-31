-- Behavioral tests for schema generation and validation. No third-party runner.
local script = debug.getinfo(1, "S").source:sub(2)
local root = vim.fn.fnamemodify(script, ":p:h:h")
vim.opt.rtp:prepend(root)

local schema = require("orbit.tooling.schema")
local legacy = require("orbit.tooling.legacy")
local completed = 0

local function check(name, run)
  local ok, err = xpcall(run, debug.traceback)
  if not ok then
    error("FAIL " .. name .. "\n" .. tostring(err), 0)
  end
  completed = completed + 1
  print("PASS " .. name)
end

local function expect_error(action, needle)
  local ok, message = pcall(action)
  assert(not ok, "expected failure: " .. needle)
  assert(tostring(message):find(needle, 1, true), tostring(message))
end

local function fixture(manifest, definitions, callback)
  local temp = vim.fn.tempname()
  local modules = vim.fs.joinpath(temp, "lua", "orbit", "modules")
  vim.fn.mkdir(modules, "p")
  vim.fn.writefile({ vim.json.encode(manifest) }, vim.fs.joinpath(modules, "manifest.json"))
  for name, definition in pairs(definitions or {}) do
    local dir = vim.fs.joinpath(modules, name)
    vim.fn.mkdir(dir, "p")
    vim.fn.writefile({ "return { setup = function() end }" }, vim.fs.joinpath(dir, "init.lua"))
    vim.fn.writefile({ vim.json.encode(definition) }, vim.fs.joinpath(dir, "schema.json"))
  end
  local ok, err = xpcall(function()
    callback(temp)
  end, debug.traceback)
  vim.fn.delete(temp, "rf")
  assert(ok, err)
end

check("generated schema matches committed file", function()
  local ok, err = schema.check(root)
  assert(ok, err)
  assert(vim.deep_equal(vim.json.decode(schema.generate(root)), schema.build(root)))
end)

check("manifest is the only module inventory", function()
  local manifest = vim.json.decode(table.concat(vim.fn.readfile(vim.fs.joinpath(root, "lua", "orbit", "modules", "manifest.json")), "\n"))
  local actual = schema.build(root).properties.modules.properties
  local count = 0
  for _, name in ipairs(manifest.order) do
    assert(actual[name] and actual[name].properties.enabled)
    count = count + 1
  end
  assert(vim.tbl_count(actual) == count)
end)

check("duplicate module names are rejected", function()
  fixture({ order = { "editor", "editor" } }, { editor = {
    type = "object", additionalProperties = false,
    properties = { enabled = { type = "boolean" } },
  } }, function(temp)
    expect_error(function()
      schema.build(temp)
    end, "unique module names")
  end)
end)

check("invalid module names are rejected before filesystem access", function()
  fixture({ order = { "../outside" } }, {}, function(temp)
    expect_error(function()
      schema.build(temp)
    end, "invalid module name")
  end)
end)

check("malformed module schemas are rejected", function()
  fixture({ order = { "broken" } }, { broken = {
    type = "object", additionalProperties = true,
  } }, function(temp)
    expect_error(function()
      schema.build(temp)
    end, "closed object schema")
  end)
end)

check("module override contract rejects unknown keys and invalid types", function()
  local config = require("orbit.config")
  local accepted = config.resolve({ modules = { editor = { shiftwidth = 4 } } })
  assert(accepted.modules.editor.shiftwidth == 4)
  assert(accepted.modules.keymaps.enabled == true)
  for _, invalid in ipairs({ -1, 17, "four", vim.NIL }) do
    expect_error(function()
      config.resolve({ modules = { editor = { shiftwidth = invalid } } })
    end, "orbit.modules.editor.shiftwidth")
  end
  expect_error(function()
    config.resolve({ modules = { nonexistent = {} } })
  end, "unknown setting")
end)

check("source name scanner catches legacy identifiers", function()
  assert(legacy.is_legacy("vim.g.Orbit" .. "VimSettings"))
  assert(legacy.is_legacy("orbit_" .. "vim_session"))
  assert(legacy.is_legacy("NV" .. "CHAD_UI"))
  assert(legacy.is_legacy("base" .. "46_cache"))
  assert(not legacy.is_legacy("orbit.modules.editor"))
end)

print(string.format("%d Lua schema and tooling tests passed.", completed))
