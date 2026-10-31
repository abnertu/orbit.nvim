-- Behavioral tests for LuaDoc-driven schema generation and validation.
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

local function sample(name, fields)
  local pascal = name:gsub("^%l", string.upper)
  local lines = {
    "local M = {}",
    "---@class Orbit." .. pascal .. "Options # A fixture module.",
  }
  vim.list_extend(lines, fields or {
    "---@field enabled boolean @default(true) # Enable this module.",
  })
  lines[#lines + 1] = "return M"
  return table.concat(lines, "\n")
end

local function fixture(manifest, definitions, callback)
  local temp = vim.fn.tempname()
  local modules = vim.fs.joinpath(temp, "lua", "orbit", "modules")
  vim.fn.mkdir(modules, "p")
  vim.fn.writefile({ vim.json.encode(manifest) }, vim.fs.joinpath(modules, "manifest.json"))
  for name, source in pairs(definitions or {}) do
    local dir = vim.fs.joinpath(modules, name)
    vim.fn.mkdir(dir, "p")
    vim.fn.writefile(vim.split(source, "\n", { plain = true }),
      vim.fs.joinpath(dir, "init.lua"))
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
  local manifest = vim.json.decode(table.concat(vim.fn.readfile(
    vim.fs.joinpath(root, "lua", "orbit", "modules", "manifest.json")), "\n"))
  local actual = schema.build(root).properties.modules.properties
  for _, name in ipairs(manifest.order) do
    assert(actual[name] and actual[name].properties.enabled)
    assert(vim.fn.filereadable(vim.fs.joinpath(root, "lua", "orbit", "modules",
      name, "schema.json")) == 0, "module schema.json must not be authored")
  end
  assert(vim.tbl_count(actual) == #manifest.order)
end)

check("duplicate module names are rejected", function()
  fixture({ order = { "editor", "editor" } }, { editor = sample("editor") },
    function(temp)
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

check("required class and field metadata are validated", function()
  fixture({ order = { "broken" } }, { broken = "return {}" }, function(temp)
    expect_error(function()
      schema.build(temp)
    end, "required LuaDoc class")
  end)

  fixture({ order = { "broken" } }, {
    broken = sample("broken", {
      "---@field enabled boolean # Missing default.",
    }),
  }, function(temp)
    expect_error(function()
      schema.build(temp)
    end, "@default(...) is required")
  end)

  fixture({ order = { "broken" } }, {
    broken = sample("broken", {
      "---@field enabled boolean @default(true) # Enabled.",
      "---@field enabled boolean @default(false) # Duplicate.",
    }),
  }, function(temp)
    expect_error(function()
      schema.build(temp)
    end, "duplicate field")
  end)
end)

check("LuaDoc primitive metadata and literal unions become schema", function()
  fixture({ order = { "sample" } }, {
    sample = sample("sample", {
      "---@field enabled boolean @default(false) # Enabled.",
      "---@field indent integer @default(4) @minimum(0) @maximum(8) # Indent size.",
      "---@field label string @default(\" \") @minLength(1) # Label text.",
      "---@field mode 'screen'|'cursor' @default(\"screen\") # Split behavior.",
    }),
  }, function(temp)
    local node = schema.build(temp).properties.modules.properties.sample
    assert(node.properties.enabled.default == false)
    assert(node.properties.indent.minimum == 0)
    assert(node.properties.indent.maximum == 8)
    assert(node.properties.label.default == " ")
    assert(node.properties.label.minLength == 1)
    assert(vim.deep_equal(node.properties.mode.enum, { "screen", "cursor" }))
    assert(node.properties.mode.description == "Split behavior.")
  end)
end)

check("invalid defaults and unsupported types fail immediately", function()
  for _, field in ipairs({
    "---@field width integer @default(2.5) # Width.",
    "---@field width integer @default(11) @maximum(10) # Width.",
    "---@field mode 'a'|'b' @default(\"c\") # Mode.",
    "---@field options table @default({}) # Unsupported nested type.",
  }) do
    fixture({ order = { "broken" } }, {
      broken = sample("broken", {
        "---@field enabled boolean @default(true) # Enabled.",
        field,
      }),
    }, function(temp)
      expect_error(function()
        schema.build(temp)
      end, ": ")
    end)
  end
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
