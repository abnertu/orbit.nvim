-- Schema construction is intentionally separate from CLI arguments and I/O.
-- Neovim provides the JSON parser, so no additional Lua rocks are required.
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

---Build the combined schema using only the ordered manifest and module schemas.
---@param root string
---@return table
function M.build(root)
  local modules = module_root(root)
  local manifest = read_json(vim.fs.joinpath(modules, "manifest.json"))
  assert(type(manifest) == "table" and vim.islist(manifest.order), "module order must be a list")
  assert(#manifest.order > 0, "module order must not be empty")

  local seen = {}
  local properties = {}

  for _, name in ipairs(manifest.order) do
    assert(is_module_name(name), "invalid module name: " .. tostring(name))
    assert(not seen[name], "module order must contain unique module names: " .. name)
    seen[name] = true

    local entry = vim.fs.joinpath(modules, name, "init.lua")
    assert(vim.fn.filereadable(entry) == 1, "missing module entry: " .. entry)

    local node = read_json(vim.fs.joinpath(modules, name, "schema.json"))
    assert(
      type(node) == "table" and node.type == "object" and node.additionalProperties == false,
      "module " .. name .. " must declare a closed object schema"
    )
    assert(
      type(node.properties) == "table"
        and type(node.properties.enabled) == "table"
        and node.properties.enabled.type == "boolean",
      "module " .. name .. " must expose a boolean enabled option"
    )
    properties[name] = node
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

-- Sort object keys and retain list order, independent of Lua hash iteration.
-- JSON remains readable and byte-identical on Linux and Windows.
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
  local result = vim.fn.writefile(vim.split(M.generate(root):gsub("\n$", ""), "\n", { plain = true }), path)
  assert(result == 0, "failed to write generated schema: " .. path)
end

return M
