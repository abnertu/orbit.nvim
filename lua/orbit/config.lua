local M = {}

---@class Orbit.Config
---@field modules? table<string, table>

local schema

local function get_schema()
  if schema then
    return schema
  end

  local paths = vim.api.nvim_get_runtime_file("settings.schema.json", false)
  local path = assert(paths[1], "orbit.nvim: generated settings.schema.json is missing")
  local content = table.concat(vim.fn.readfile(path), "\n")
  schema = vim.json.decode(content)
  return schema
end

local function default_for(node)
  if node.default ~= nil then
    return vim.deepcopy(node.default)
  end

  if node.type == "object" then
    local result = {}
    for name, child in pairs(node.properties or {}) do
      result[name] = default_for(child)
    end
    return result
  end
end

local function resolve(value, node, path)
  if value == nil then
    return default_for(node)
  end

  local kind = node.type
  local matches = type(value) == kind
  if kind == "object" then
    matches = type(value) == "table"
      and (not vim.islist(value) or next(value) == nil)
      and value ~= vim.NIL
  elseif kind == "integer" then
    matches = type(value) == "number" and value == math.floor(value)
  end

  if not matches then
    error(path .. ": expected " .. kind, 0)
  end

  if kind == "integer" then
    if value < node.minimum or value > node.maximum then
      error(path .. ": out of range", 0)
    end
  elseif kind == "string" then
    if node.minLength and #value < node.minLength then
      error(path .. ": must not be empty", 0)
    end
  end

  if node.enum and not vim.tbl_contains(node.enum, value) then
    error(path .. ": unsupported value", 0)
  end

  if kind == "object" then
    local result = default_for(node)
    for name, child_value in pairs(value) do
      local child = (node.properties or {})[name]
      if child == nil then
        error(path .. "." .. name .. ": unknown setting", 0)
      end
      result[name] = resolve(child_value, child, path .. "." .. name)
    end
    return result
  end

  return value
end

---Validate a module when users call its setup function directly.
---@param name string
---@param opts? table
---@return table
function M.resolve_module(name, opts)
  local modules = get_schema().properties.modules.properties
  local node = assert(modules[name], "unknown orbit.nvim module: " .. name)
  return resolve(opts or {}, node, "orbit.modules." .. name)
end

---Validate all options before any module applies side effects.
---@param opts? Orbit.Config
---@return Orbit.Config
function M.resolve(opts)
  return resolve(vim.deepcopy(opts or {}), get_schema(), "orbit")
end

return M
