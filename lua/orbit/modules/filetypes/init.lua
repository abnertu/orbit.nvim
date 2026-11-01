local M = {}
local original
local registered = false

---@class Orbit.FiletypesOptions # Filename and extension detection rules.
---@field compose? string @default("yaml.docker-compose") @minLength(1) # Filetype for Compose YAML filenames.
---@field enabled? boolean @default(true) # Register custom filetype detections.
---@field jsx? string @default("jsx") @minLength(1) # Filetype for JSX extensions.

local compose_files = {
  "compose.yaml",
  "compose.yml",
  "docker-compose.yaml",
  "docker-compose.yml",
}

local function snapshot()
  local registry = vim.filetype.inspect()
  local previous = { filename = {}, extension = {} }
  for _, name in ipairs(compose_files) do
    previous.filename[name] = registry.filename[name] or false
  end
  previous.extension.jsx = registry.extension.jsx or false
  return previous
end

local function restore_registry(previous)
  local filenames = {}
  for _, name in ipairs(compose_files) do
    local value = previous.filename[name]
    filenames[name] = value == false and function()
      return nil
    end or value
  end

  local jsx = previous.extension.jsx
  if jsx == false then
    jsx = function()
      return nil
    end
  end

  vim.filetype.add({
    filename = filenames,
    extension = { jsx = jsx },
  })
end

---Capture registry entries so failed activation can restore previous owners.
---@return table
function M.capture()
  return {
    registered = registered,
    original = original,
    current = snapshot(),
  }
end

---@param previous table
function M.restore(previous)
  restore_registry(previous.current)
  original = previous.original
  registered = previous.registered
end

---@param opts? Orbit.FiletypesOptions
function M.setup(opts)
  opts = require("orbit.config").resolve_module("filetypes", opts)
  if not registered then
    original = snapshot()
    registered = true
  end

  if not opts.enabled then
    restore_registry(original)
    return
  end

  local filenames = {}
  for _, name in ipairs(compose_files) do
    filenames[name] = opts.compose
  end

  vim.filetype.add({
    filename = filenames,
    extension = { jsx = opts.jsx },
  })
end

return M
