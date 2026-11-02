-- Own debugger adapters and configurations, without installing external debuggers.
local M = {}
local initialized = false
local ui_initialized = false

local function same(a, b)
  return a.type == b.type and a.request == b.request and a.name == b.name
end

local function remove_configs(dap, name)
  for ft, configs in pairs(dap.configurations or {}) do
    for index = #configs, 1, -1 do
      if configs[index].type == name then table.remove(configs, index) end
    end
    if #configs == 0 then dap.configurations[ft] = nil end
  end
end

local function add_configs(dap, name, definitions)
  dap.configurations = dap.configurations or {}
  for ft, entries in pairs(definitions.configurations or {}) do
    for _, entry in ipairs(entries) do
      if entry.type == name then
        dap.configurations[ft] = dap.configurations[ft] or {}
        local exists = false
        for _, existing in ipairs(dap.configurations[ft]) do
          if same(existing, entry) then exists = true; break end
        end
        if not exists then
          table.insert(dap.configurations[ft], vim.deepcopy(entry))
        end
      end
    end
  end
end

function M.apply_adapter(dap, name, enabled, definitions)
  if enabled then
    if name == "coreclr" then
      local ok, dotnet = pcall(require, "dotnet-cli")
      if not ok then return false, "dotnet-cli is unavailable" end
      return dotnet.setup_dap()
    end
    assert(definitions.adapters[name], "unknown debug adapter: " .. name)
    dap.adapters[name] = definitions.adapters[name]
    add_configs(dap, name, definitions)
  else
    dap.adapters[name] = nil
    remove_configs(dap, name)
  end
  return true
end

function M.adapter_status(dap, name)
  local registered = dap.adapters and dap.adapters[name] ~= nil
  local count = 0
  for _, configs in pairs(dap.configurations or {}) do
    for _, c in ipairs(configs) do
      if c.type == name then count = count + 1 end
    end
  end
  local label = string.format("%s %d cfg",
    registered and "registered" or "not registered", count)
  if not registered then return label, "DiagnosticError" end
  if count == 0 then return label, "DiagnosticWarn" end
  return label, "DiagnosticOk"
end

function M.setup(dap, definitions)
  if initialized then return end
  dap.adapters = dap.adapters or {}
  dap.configurations = dap.configurations or {}
  local bridge = require("orbit.hangar_bridge")
  if definitions.enabled.python and bridge.is_enabled("dap", "python") then
    M.apply_adapter(dap, "python", true, definitions)
  end
  if definitions.enabled.coreclr and bridge.is_enabled("dap", "coreclr") then
    local ok, message = M.apply_adapter(dap, "coreclr", true, definitions)
    if not ok then
      vim.notify(tostring(message), vim.log.levels.WARN, { title = "Dotnet" })
    end
  end
  initialized = true
end

function M.setup_ui(opts)
  if ui_initialized then return end
  local dap, ui = require("dap"), require("dapui")
  ui.setup(opts or {})
  dap.listeners.before.terminate["orbit_dapui"] = function()
    ui.close()
  end
  dap.listeners.before.event_exited["orbit_dapui"] = function()
    ui.close()
  end
  -- Attach sessions end with `terminated` alone; adapters send `exited` only for launched programs.
  dap.listeners.before.event_terminated["orbit_dapui"] = function()
    ui.close()
  end
  ui_initialized = true
end

return M
