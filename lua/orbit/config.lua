local M = {}

---@class Orbit.ModuleOverrides
---@field editor? Orbit.EditorOptions
---@field filetypes? Orbit.FiletypesOptions
---@field keymaps? Orbit.KeymapsOptions
---@field keyguide? Orbit.KeyguideOptions
---@field events? Orbit.EventsOptions
---@field system? Orbit.SystemOptions
---@field python_tools? Orbit.PythonToolsOptions
---@field corekeys? Orbit.CorekeysOptions
---@field commands? Orbit.CommandsOptions
---@field icons? Orbit.IconsOptions
---@field git? Orbit.GitOptions
---@field editor_plugins? Orbit.EditorPluginsOptions
---@field diagnostics_plugins? Orbit.DiagnosticsPluginsOptions
---@field messages? Orbit.MessagesOptions
---@field snacks? Orbit.SnacksOptions
---@field mason? Orbit.MasonOptions
---@field treesitter_plugins? Orbit.TreesitterPluginsOptions
---@field formatter? Orbit.FormatterOptions
---@field linter? Orbit.LinterOptions
---@field markdown? Orbit.MarkdownOptions
---@field navigation? Orbit.NavigationOptions
---@field lsp? Orbit.LspOptions
---@field dap? Orbit.DapOptions
---@field hangar? Orbit.HangarOptions
---@field completion? Orbit.CompletionOptions
---@field lsp_providers? Orbit.LspProvidersOptions
---@field plugins? Orbit.PluginsOptions

---@class Orbit.Config
---@field modules? Orbit.ModuleOverrides

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
  -- Nested object defaults come from their fields, not an empty table literal.
  if node.type == "object" then
    local result = {}
    for name, child in pairs(node.properties or {}) do
      result[name] = default_for(child)
    end
    return result
  end
  if node.default ~= nil then
    return vim.deepcopy(node.default)
  end
  if node.type == "array" then
    return {}
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
  elseif kind == "array" then
    matches = type(value) == "table"
      and vim.islist(value)
      and value ~= vim.NIL
  elseif kind == "integer" then
    matches = type(value) == "number" and value == math.floor(value)
  end

  if not matches then
    error(path .. ": expected " .. kind, 0)
  end

  if kind == "integer" or kind == "number" then
    if (node.minimum and value < node.minimum) or
      (node.maximum and value > node.maximum)
    then
      error(path .. ": out of range", 0)
    end
  elseif kind == "string" then
    if node.minLength and vim.fn.strchars(value) < node.minLength then
      error(path .. ": must be at least " .. node.minLength .. " characters", 0)
    end
  end

  if node.enum and not vim.tbl_contains(node.enum, value) then
    error(path .. ": unsupported value", 0)
  end

  if kind == "object" then
    local overrides = {}
    for name, child_value in pairs(value) do
      local child = (node.properties or {})[name]
      if child == nil then
        error(path .. "." .. name .. ": unknown setting", 0)
      end
      overrides[name] = resolve(child_value, child, path .. "." .. name)
    end
    -- Validate first, then overlay only supplied fields. Deep merging would
    -- merge arrays by index and change the settings replacement contract.
    return vim.tbl_extend("force", default_for(node), overrides)
  elseif kind == "array" then
    local result = {}
    for index, item in ipairs(value) do
      result[index] = resolve(item, assert(node.items, "array schema needs items"),
        path .. "[" .. index .. "]")
    end
    return result
  end

  return value
end

-- Restart-only fields retain their active values until the next Neovim process.
-- Arrays with restart-only members defer as a unit to avoid unstable indices.
local function has_restart(node)
  if node["x-orbit-restart"] then
    return true
  end
  if node.type == "array" then
    return has_restart(assert(node.items, "array schema needs items"))
  end
  if node.type == "object" then
    for _, child in pairs(node.properties or {}) do
      if has_restart(child) then
        return true
      end
    end
  end
  return false
end

local function defer_node(current, requested, node, path, pending)
  if node["x-orbit-restart"] or
    (node.type == "array" and has_restart(node.items))
  then
    if not vim.deep_equal(current, requested) then
      pending[path] = vim.deepcopy(requested)
      return vim.deepcopy(current)
    end
    return requested
  end

  if node.type == "object" then
    local effective = vim.deepcopy(requested)
    for name, child in pairs(node.properties or {}) do
      effective[name] = defer_node(current[name], requested[name], child,
        path .. "." .. name, pending)
    end
    return effective
  end
  return requested
end

---Keep restart-only values active while applying other validated fields.
---On first setup, there is no active configuration to preserve.
---@param current? Orbit.Config
---@param requested Orbit.Config
---@param supplied_schema? table
---@return Orbit.Config, table
function M.defer_restart(current, requested, supplied_schema)
  if not current then
    return vim.deepcopy(requested), {}
  end
  local pending = {}
  local effective = defer_node(current, requested, supplied_schema or get_schema(),
    "orbit", pending)
  return effective, pending
end

---Resolve a supplied schema without activating any modules.
---Used to validate generated schema fixtures before publishing them.
---@param opts table?
---@param supplied_schema table
---@return table
function M.resolve_against(opts, supplied_schema)
  return resolve(vim.deepcopy(opts or {}), supplied_schema, "orbit")
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
  return M.resolve_against(opts, get_schema())
end

return M
