local M = {}
local configured

local function read_manifest()
  local files = vim.api.nvim_get_runtime_file("lua/orbit/modules/manifest.json", false)
  local path = assert(files[1], "orbit.nvim: module manifest is missing")
  return vim.json.decode(table.concat(vim.fn.readfile(path), "\n"))
end

---Configure the editor. A future release will add disk settings and reload.
---@param opts? Orbit.Config
function M.setup(opts)
  local config = require("orbit.config").resolve(opts)
  local manifest = read_manifest()

  for _, name in ipairs(manifest.order) do
    local options = assert(config.modules[name], "missing module options: " .. name)
    local module = require("orbit.modules." .. name)
    module.setup(options)
  end

  configured = vim.deepcopy(config)
end

---@return Orbit.Config?
function M.get_config()
  return configured and vim.deepcopy(configured) or nil
end

return M
