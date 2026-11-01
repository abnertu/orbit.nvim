-- Compile LuaDoc settings into JSON Schema without evaluating module code.
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

local function attributes(source, location)
  local result = {}
  local allowed = {
    default = true,
    minimum = true,
    maximum = true,
    minLength = true,
    restart = true,
  }

  while source:match("%S") do
    local name, raw, remainder = source:match("^%s*@([%a]+)(%b())(.*)$")
    assert(name, location .. ": invalid LuaDoc metadata: " .. source)
    assert(allowed[name], location .. ": unsupported metadata " .. name)
    assert(result[name] == nil, location .. ": duplicate metadata " .. name)

    local valid, value = pcall(vim.json.decode, raw:sub(2, -2))
    assert(valid and value ~= vim.NIL,
      location .. ": metadata " .. name .. " needs a JSON value")

    result[name] = value
    source = remainder
  end

  assert(result.default ~= nil, location .. ": @default(...) is required")
  if result.restart ~= nil then
    assert(result.restart == true, location .. ": @restart(true) is required")
  end
  return result
end

local compile_field

-- Expand LuaLS field types, arrays, string literal unions and local classes.
local function field_type(source, location, classes, stack)
  local base = source:match("^(.-)%[%]$")
  if base then
    assert(base ~= "", location .. ": empty array element type")
    return { type = "array", items = field_type(base, location, classes, stack) }
  end

  if source == "boolean" or source == "string" or
    source == "number" or source == "integer"
  then
    return { type = source }
  end

  local definition = classes[source]
  if definition then
    assert(not stack[source], location .. ": recursive LuaDoc class " .. source)
    stack[source] = true
    local result = {
      type = "object",
      additionalProperties = false,
      description = definition.description,
      properties = {},
    }
    for _, field in ipairs(definition.fields) do
      result.properties[field.name] = compile_field(
        field.type_name, field.metadata, field.description,
        field.location, classes, stack
      )
    end
    stack[source] = nil
    return result
  end

  -- LuaLS string-literal unions become stable enum lists.
  local values, exact, seen = {}, {}, {}
  for value in source:gmatch("'([^']*)'") do
    assert(not seen[value], location .. ": duplicate literal " .. value)
    seen[value] = true
    values[#values + 1] = value
    exact[#exact + 1] = "'" .. value .. "'"
  end
  assert(#values > 0 and table.concat(exact, "|") == source,
    location .. ": unsupported LuaDoc type " .. source)
  return { type = "string", enum = values }
end

compile_field = function(type_name, metadata, description, location, classes, stack)
  assert(description and description ~= "", location .. ": missing description")
  local node = field_type(type_name, location, classes, stack)
  local attr = attributes(metadata, location)
  node.description = description
  node.default = attr.default
  if attr.restart then
    node["x-orbit-restart"] = true
  end

  if node.type == "integer" then
    assert(type(node.default) == "number" and node.default == math.floor(node.default),
      location .. ": default must be an integer")
  elseif node.type == "object" then
    -- Empty defaults mean "derive nested field defaults", not "drop fields".
    assert(type(node.default) == "table" and next(node.default) == nil,
      location .. ": object default must be {}")
  elseif node.type == "array" then
    assert(type(node.default) == "table" and next(node.default) == nil,
      location .. ": array default must be []")
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
    assert(vim.fn.strchars(node.default) >= node.minLength,
      location .. ": default is too short")
  end
  if node.enum then
    assert(vim.tbl_contains(node.enum, node.default),
      location .. ": default is not in the literal union")
  end

  return node
end

---Parse all LuaDoc classes local to a module, then expand the root options.
---Do not require() the source; imports could have runtime side effects.
---@param path string
---@param name string
---@return table
function M.parse_module(path, name)
  local ok, lines = pcall(vim.fn.readfile, path)
  assert(ok, "cannot read " .. path .. ": " .. tostring(lines))

  local classes, active = {}, nil
  for number, line in ipairs(lines) do
    local annotated_class, trailing = line:match("^%s*%-%-%-@class%s+(%S+)%s*(.*)$")
    if annotated_class then
      active = nil
      if annotated_class:match("^Orbit%.") then
        assert(not classes[annotated_class],
          path .. ":" .. number .. ": duplicate class " .. annotated_class)
        local description = trailing:match("^#%s*(.-)%s*$")
        classes[annotated_class] = { description = description, fields = {}, names = {} }
        active = classes[annotated_class]
      end
    elseif active and line:match("^%s*%-%-%-@field") then
      local declaration, type_name, rest =
        line:match("^%s*%-%-%-@field%s+([%w_?]+)%s+(%S+)%s+(.+)$")
      local field = declaration and declaration:gsub("%?$", "")
      local location = path .. ":" .. number
      assert(field and field:match("^[a-z][a-z0-9_]*$") and
        (declaration == field or declaration == field .. "?"),
        location .. ": malformed LuaDoc field")
      assert(not active.names[field], location .. ": duplicate field " .. field)

      local metadata, description = rest:match("^(.-)%s*#%s+(.+)$")
      assert(metadata and description, location .. ": missing metadata or description")
      active.names[field] = true
      active.fields[#active.fields + 1] = {
        name = field,
        type_name = type_name,
        metadata = metadata,
        description = description,
        location = location,
      }
    end
  end

  local target = class_name(name)
  local root = classes[target]
  assert(root, path .. ": required LuaDoc class " .. target .. " is missing")
  assert(root.description and root.description ~= "",
    path .. ": class description is required")

  local result = field_type(target, path, classes, {})
  assert(result.properties.enabled and result.properties.enabled.type == "boolean",
    path .. ": module needs a boolean enabled field")
  return result
end

---Combine module LuaDoc using the ordered manifest as the sole inventory.
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

-- Sort keys and preserve list order for reproducible generated output.
local function encode_pretty(value, depth)
  if type(value) ~= "table" then
    return vim.json.encode(value)
  end

  local entries, indent = {}, string.rep("  ", depth)
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
      .. vim.json.encode(key) .. ": " .. encode_pretty(value[key], depth + 1)
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
