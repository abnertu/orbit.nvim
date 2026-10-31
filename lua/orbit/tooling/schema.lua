-- Generate JSON Schema from the same LuaDoc that drives Lua type completion.
-- No module schema.json files or third-party parsers are required.
local M = {}

local function module_root(root)
  return vim.fs.joinpath(root, "lua", "orbit", "modules")
end

local function read_json(path)
  local ok, lines = pcall(vim.fn.readfile, path)
  assert(ok, "cannot read " .. path .. ": " .. tostring(lines))
  local decoded, result = pcall(vim.json.decode, table.concat(lines, "\n"))
  assert(decoded, "invalid JSON in " .. path .. ": " .. tostring(result))
  return result
end

local function is_module_name(name)
  return type(name) == "string" and name:match("^[a-z][a-z0-9_]*$") ~= nil
end

local function class_name(name)
  local pascal = name:gsub("^%l", string.upper):gsub("_(%l)", string.upper)
  return "Orbit." .. pascal .. "Options"
end

local function field_type(source, location)
  local primitives = {
    boolean = true,
    string = true,
    number = true,
    integer = true,
  }
  if primitives[source] then
    return { type = source }
  end

  -- LuaLS string literal unions double as enum declarations.
  local entries, normalized, seen = {}, {}, {}
  for value in source:gmatch("'([^']*)'") do
    assert(not seen[value], location .. ": duplicate literal: " .. value)
    seen[value] = true
    entries[#entries + 1] = value
    normalized[#normalized + 1] = "'" .. value .. "'"
  end
  assert(#entries > 0 and table.concat(normalized, "|") == source,
    location .. ": unsupported LuaDoc type " .. source)
  return { type = "string", enum = entries }
end

local function attributes(source, location)
  local result = {}
  local allowed = {
    default = true,
    minimum = true,
    maximum = true,
    minLength = true,
  }

  while source:match("%S") do
    local name, raw, remainder = source:match("^%s*@([%a]+)(%b())(.*)$")
    assert(name, location .. ": invalid LuaDoc metadata: " .. source)
    assert(allowed[name], location .. ": unsupported metadata " .. name)
    assert(result[name] == nil, location .. ": duplicate metadata " .. name)

    local valid, value = pcall(vim.json.decode, raw:sub(2, -2))
    assert(valid and value ~= vim.NIL,
      location .. ": metadata " .. name .. " needs a JSON scalar")

    result[name] = value
    source = remainder
  end

  assert(result.default ~= nil, location .. ": @default(...) is required")
  return result
end

local function compile_field(annotation, type_name, metadata, description, location)
  assert(description and description ~= "", location .. ": missing description")
  local node = field_type(type_name, location)
  local attr = attributes(metadata, location)

  node.description = description
  node.default = attr.default

  if node.type == "integer" then
    assert(type(node.default) == "number" and node.default == math.floor(node.default),
      location .. ": default must be an integer")
  else
    assert(type(node.default) == node.type, location .. ": invalid default type")
  end

  for _, name in ipairs({ "minimum", "maximum", "minLength" }) do
    local value = attr[name]
    if value ~= nil then
      assert(type(value) == "number" and value >= 0 and value == math.floor(value),
        location .. ": " .. name .. " must be a nonnegative integer")
      if name == "minLength" then
        assert(node.type == "string", location .. ": minLength requires string")
      else
        assert(node.type == "integer" or node.type == "number",
          location .. ": " .. name .. " requires a numeric type")
      end
      node[name] = value
    end
  end

  assert(not node.minimum or not node.maximum or node.minimum <= node.maximum,
    location .. ": minimum exceeds maximum")

  if node.minimum then
    assert(node.default >= node.minimum, location .. ": default is below minimum")
  end
  if node.maximum then
    assert(node.default <= node.maximum, location .. ": default exceeds maximum")
  end
  if node.minLength then
    assert(#node.default >= node.minLength, location .. ": default is too short")
  end
  if node.enum then
    assert(vim.tbl_contains(node.enum, node.default),
      location .. ": default is not in the literal union")
  end

  return node
end

---Parse a module's LuaDoc without evaluating the module or applying side effects.
---@param path string
---@param name string
---@return table
function M.parse_module(path, name)
  local ok, lines = pcall(vim.fn.readfile, path)
  assert(ok, "cannot read " .. path .. ": " .. tostring(lines))

  local target = class_name(name)
  local found, active = false, false
  local node = {
    type = "object",
    additionalProperties = false,
    properties = {},
  }

  for number, line in ipairs(lines) do
    local annotated_class, trailing = line:match("^%s*%-%-%-@class%s+(%S+)%s*(.*)$")
    if annotated_class then
      active = annotated_class == target
      if active then
        assert(not found, path .. ":" .. number .. ": duplicate class " .. target)
        found = true
        node.description = trailing:match("^#%s*(.-)%s*$")
        assert(node.description and node.description ~= "",
          path .. ":" .. number .. ": class description is required")
      end
    elseif active and line:match("^%s*%-%-%-@field") then
      local field, type_name, rest =
        line:match("^%s*%-%-%-@field%s+([%w_]+)%s+(%S+)%s+(.+)$")
      local location = path .. ":" .. number
      assert(field and field:match("^[a-z][a-z0-9_]*$"),
        location .. ": malformed LuaDoc field")
      assert(node.properties[field] == nil, location .. ": duplicate field " .. field)

      local metadata, description = rest:match("^(.-)%s*#%s+(.+)$")
      assert(metadata and description, location .. ": missing metadata or description")
      node.properties[field] = compile_field(field, type_name, metadata, description, location)
    end
  end

  assert(found, path .. ": required LuaDoc class " .. target .. " is missing")
  assert(node.properties.enabled and node.properties.enabled.type == "boolean",
    path .. ": module needs a boolean enabled field")

  return node
end

---Build the combined schema using only the manifest and module LuaDoc.
---@param root string
---@return table
function M.build(root)
  local modules = module_root(root)
  local manifest = read_json(vim.fs.joinpath(modules, "manifest.json"))
  assert(type(manifest) == "table" and vim.islist(manifest.order),
    "module order must be a list")
  assert(#manifest.order > 0, "module order must not be empty")

  local seen, properties = {}, {}
  for _, name in ipairs(manifest.order) do
    assert(is_module_name(name), "invalid module name: " .. tostring(name))
    assert(not seen[name], "module order must contain unique module names: " .. name)
    seen[name] = true

    local entry = vim.fs.joinpath(modules, name, "init.lua")
    assert(vim.fn.filereadable(entry) == 1, "missing module entry: " .. entry)
    properties[name] = M.parse_module(entry, name)
  end

  return {
    ["$schema"] = "http://json-schema.org/draft-07/schema#",
    title = "orbit.nvim settings",
    description = "Configuration for orbit.nvim modules.",
    type = "object",
    additionalProperties = false,
    properties = {
      ["$schema"] = { type = "string" },
      modules = {
        type = "object",
        additionalProperties = false,
        properties = properties,
      },
    },
  }
end

-- Sort object keys and retain list order across Linux and Windows.
local function encode_pretty(value, depth)
  local kind = type(value)
  if kind ~= "table" then
    return vim.json.encode(value)
  end

  local entries = {}
  local indent = string.rep("  ", depth)
  local next_indent = string.rep("  ", depth + 1)

  if vim.islist(value) then
    for _, item in ipairs(value) do
      entries[#entries + 1] = next_indent .. encode_pretty(item, depth + 1)
    end
    if #entries == 0 then
      return "[]"
    end
    return "[\n" .. table.concat(entries, ",\n") .. "\n" .. indent .. "]"
  end

  local keys = vim.tbl_keys(value)
  table.sort(keys)
  for _, key in ipairs(keys) do
    entries[#entries + 1] = next_indent
      .. vim.json.encode(key)
      .. ": "
      .. encode_pretty(value[key], depth + 1)
  end
  if #entries == 0 then
    return "{}"
  end
  return "{\n" .. table.concat(entries, ",\n") .. "\n" .. indent .. "}"
end

---@param root string
---@return string
function M.generate(root)
  return encode_pretty(M.build(root), 0) .. "\n"
end

---@param root string
---@return boolean, string?
function M.check(root)
  local path = vim.fs.joinpath(root, "settings.schema.json")
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok then
    return false, "settings.schema.json is missing"
  end
  local current = table.concat(lines, "\n") .. "\n"
  if current ~= M.generate(root) then
    return false, "settings.schema.json is stale; run scripts/generate_schema.lua"
  end
  return true
end

---@param root string
function M.write(root)
  local path = vim.fs.joinpath(root, "settings.schema.json")
  local result = vim.fn.writefile(
    vim.split(M.generate(root):gsub("\n$", ""), "\n", { plain = true }), path
  )
  assert(result == 0, "failed to write generated schema: " .. path)
end

return M
