-- Lazy spec import backed by the same manifest as orbit.setup().
-- Feature specs are imported only when Lazy requests them.
local path = assert(
  vim.api.nvim_get_runtime_file("lua/orbit/modules/manifest.json", false)[1],
  "orbit.nvim module manifest is missing"
)
local manifest = vim.json.decode(table.concat(vim.fn.readfile(path), "\n"))
---@type LazySpec
local specs = {}

for _, name in ipairs(manifest.order) do
  local module = require("orbit.modules." .. name)
  if type(module.spec) == "function" then
    ---@type LazySpec
    local entries = module.spec()
    assert(vim.islist(entries), "invalid Lazy spec list from orbit module " .. name)
    vim.list_extend(specs, entries)
  end
end

return specs
