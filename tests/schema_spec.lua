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

check("restart-only metadata defers nested fields and array changes", function()
  local module = sample("sample", {
    "---@field enabled boolean @default(true) # Enable.",
    "---@field live integer @default(1) # Live value.",
    "---@field delayed string @default(\"one\") @restart(true) # Deferred value.",
    "---@field panel Orbit.PanelOptions @default({}) # Nested settings.",
    "---@field panels Orbit.PanelOptions[] @default([]) # Panel list.",
  }) .. "\n" .. table.concat({
    "---@class Orbit.PanelOptions # Panel settings.",
    "---@field size integer @default(2) @restart(true) # Restart-only size.",
    "---@field title string @default(\"base\") # Live title.",
  }, "\n")

  fixture({ order = { "sample" } }, { sample = module }, function(temp)
    local built = schema.build(temp)
    local fields = built.properties.modules.properties.sample.properties
    assert(fields.delayed["x-orbit-restart"] == true)
    assert(fields.panel.properties.size["x-orbit-restart"] == true)
    assert(fields.live["x-orbit-restart"] == nil)

    local config = require("orbit.config")
    local previous = config.resolve_against({ modules = { sample = {
      panels = { { size = 2, title = "first" } },
    } } }, built)
    local requested = config.resolve_against({ modules = { sample = {
      live = 3,
      delayed = "two",
      panel = { size = 9, title = "updated" },
      panels = { { size = 4, title = "second" } },
    } } }, built)
    local effective, pending = config.defer_restart(previous, requested, built)
    assert(effective.modules.sample.live == 3)
    assert(effective.modules.sample.delayed == "one")
    assert(effective.modules.sample.panel.size == 2)
    assert(effective.modules.sample.panel.title == "updated")
    assert(vim.deep_equal(effective.modules.sample.panels,
      previous.modules.sample.panels))
    assert(pending["orbit.modules.sample.delayed"] == "two")
    assert(pending["orbit.modules.sample.panel.size"] == 9)
    assert(vim.deep_equal(pending["orbit.modules.sample.panels"],
      requested.modules.sample.panels))
    assert(vim.tbl_count(pending) == 3)

    local first, no_pending = config.defer_restart(nil, requested, built)
    assert(vim.deep_equal(first, requested))
    assert(vim.tbl_isempty(no_pending))
  end)
end)

check("restart-only annotation must be explicitly true", function()
  for _, value in ipairs({ "false", "1", "\"yes\"", "{}" }) do
    fixture({ order = { "broken" } }, {
      broken = sample("broken", {
        "---@field enabled boolean @default(true) # Enabled.",
        "---@field delayed boolean @default(true) @restart(" .. value ..
          ") # Deferred.",
      }),
    }, function(temp)
      expect_error(function()
        schema.build(temp)
      end, "@restart(true) is required")
    end)
  end
end)

check("nested LuaDoc classes and arrays compile without JSON sources", function()
  local module = sample("sample", {
    "---@field enabled boolean @default(true) # Enable.",
    "---@field panel Orbit.PanelOptions @default({}) # Panel settings.",
    "---@field entries Orbit.PanelOptions[] @default([]) # Open panels.",
    "---@field labels string[] @default([]) # Labels.",
  }) .. "\n" .. table.concat({
    "---@class Orbit.PanelOptions # A panel's settings.",
    "---@field width integer @default(2) @minimum(1) @maximum(9) # Width.",
    "---@field title string @default(\"panel\") @minLength(1) # Title.",
  }, "\n")

  fixture({ order = { "sample" } }, { sample = module }, function(temp)
    local schema_node = schema.build(temp)
    local fields = schema_node.properties.modules.properties.sample.properties
    assert(fields.panel.type == "object")
    assert(fields.panel.properties.width.default == 2)
    assert(fields.entries.type == "array" and fields.entries.items.type == "object")
    assert(fields.labels.items.type == "string")

    local config = require("orbit.config")
    local defaults = config.resolve_against({}, schema_node)
    assert(defaults.modules.sample.panel.width == 2)
    assert(defaults.modules.sample.panel.title == "panel")
    assert(vim.islist(defaults.modules.sample.entries))
    assert(vim.islist(defaults.modules.sample.labels))

    local configured = config.resolve_against({
      modules = { sample = {
        panel = { width = 4 },
        entries = { { width = 5, title = "first" } },
        labels = { "one", "two" },
      } },
    }, schema_node)
    assert(configured.modules.sample.panel.width == 4)
    assert(configured.modules.sample.entries[1].title == "first")
    assert(configured.modules.sample.labels[2] == "two")

    expect_error(function()
      config.resolve_against({ modules = {
        sample = { entries = { { width = 20 } } },
      } }, schema_node)
    end, "orbit.modules.sample.entries[1].width")

    expect_error(function()
      config.resolve_against({ modules = {
        sample = { panel = { unknown = "x" } },
      } }, schema_node)
    end, "unknown setting")

    expect_error(function()
      config.resolve_against({ modules = {
        sample = { labels = { "good", false } },
      } }, schema_node)
    end, "orbit.modules.sample.labels[2]")
  end)
end)

check("recursive LuaDoc classes cannot produce infinitely nested schema", function()
  local module = sample("sample", {
    "---@field enabled boolean @default(true) # Enabled.",
    "---@field child Orbit.PanelOptions @default({}) # Child.",
  }) .. "\n" .. table.concat({
    "---@class Orbit.PanelOptions # Panel.",
    "---@field next Orbit.PanelOptions @default({}) # Next.",
  }, "\n")

  fixture({ order = { "sample" } }, { sample = module }, function(temp)
    expect_error(function()
      schema.build(temp)
    end, "recursive LuaDoc class")
  end)
end)

check("invalid defaults and unsupported types fail immediately", function()
  for _, field in ipairs({
    "---@field width integer @default(2.5) # Width.",
    "---@field width integer @default(11) @maximum(10) # Width.",
    "---@field mode 'a'|'b' @default(\"c\") # Mode.",
    "---@field options unknown @default({}) # Unsupported nested type.",
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
