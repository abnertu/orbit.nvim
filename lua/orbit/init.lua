local M = {}
local configured

local function read_manifest()
  local files = vim.api.nvim_get_runtime_file("lua/orbit/modules/manifest.json", false)
  local path = assert(files[1], "orbit.nvim: module manifest is missing")
  return vim.json.decode(table.concat(vim.fn.readfile(path), "\n"))
end

---Configure modules as one transaction. Failed activation restores affected module state.
---@param opts? Orbit.Config
function M.setup(opts)
  local config = require("orbit.config").resolve(opts)
  local manifest = read_manifest()
  local prepared = {}
  local seen = {}

  -- Load and capture all modules before the first runtime modification.
  for _, name in ipairs(manifest.order) do
    assert(not seen[name], "duplicate orbit module: " .. name)
    seen[name] = true

    local options = assert(config.modules[name], "missing module options: " .. name)
    local module = require("orbit.modules." .. name)
    assert(type(module.capture) == "function", "missing capture contract: " .. name)
    assert(type(module.restore) == "function", "missing restore contract: " .. name)

    -- Unchanged options must not reset buffer/window-local user overrides.
    local before = configured and configured.modules[name]
    if not before or not vim.deep_equal(before, options) then
      prepared[#prepared + 1] = {
        name = name,
        module = module,
        options = options,
        previous_config = before,
        previous = module.capture(options),
      }
    end
  end

  for index, item in ipairs(prepared) do
    local applied, apply_error = xpcall(function()
      item.module.setup(item.options, item.previous_config)
    end, debug.traceback)

    if not applied then
      local rollback_errors = {}
      for undo = index, 1, -1 do
        local previous = prepared[undo]
        local restored, restore_error = xpcall(function()
          previous.module.restore(previous.previous)
        end, debug.traceback)
        if not restored then
          rollback_errors[#rollback_errors + 1] =
            previous.name .. ": " .. tostring(restore_error)
        end
      end

      local message = "orbit.setup: " .. item.name .. ": " .. tostring(apply_error)
      if #rollback_errors > 0 then
        message = message .. "; rollback failed (" ..
          table.concat(rollback_errors, "; ") .. "); restart required"
      end
      error(message, 0)
    end
  end

  configured = vim.deepcopy(config)
end

---Load, validate and apply saved JSON settings on explicit request.
---A failed read or activation does not replace the accepted configuration.
---@param path? string
---@return boolean, string?
function M.setup_from_file(path)
  local options, err = require("orbit.settings").read(path)
  if not options then
    return false, err
  end

  local ok, failure = xpcall(function()
    M.setup(options)
  end, debug.traceback)
  if not ok then
    return false, tostring(failure)
  end

  return true
end

---Explicitly reload saved settings using transactional setup.
---Unchanged module settings do not reset current local editor overrides.
---@param path? string
---@return boolean, string?
function M.reload_from_file(path)
  return M.setup_from_file(path)
end

---Start observing only the selected settings file on buffer writes.
---@param path? string
---@return string
function M.watch_settings(path)
  return require("orbit.settings").watch(path)
end

---Remove the settings observer without modifying saved settings.
function M.unwatch_settings()
  require("orbit.settings").unwatch()
end

---@return Orbit.Config?
function M.get_config()
  return configured and vim.deepcopy(configured) or nil
end

return M
