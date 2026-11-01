local M = {}
local accepted

---@class Orbit.DotnetOptions # dotnet-cli and Comet .NET project commands.
---@field enabled? boolean @default(true) @restart(true) # Include the dotnet-cli plugin spec.
---@field manager_key? string @default("<leader>ud") @minLength(1) @restart(true) # Open the .NET manager.

---@return Orbit.DotnetOptions?
function M.capture()
  return accepted and vim.deepcopy(accepted) or nil
end

---@param snapshot Orbit.DotnetOptions?
function M.restore(snapshot)
  accepted = snapshot and vim.deepcopy(snapshot) or nil
end

---@param opts? Orbit.DotnetOptions
function M.setup(opts)
  accepted = require("orbit.config").resolve_module("dotnet", opts)
end

---Declare the command-, key- and C#-lazy dotnet-cli owner. It also owns
---CoreCLR registration, which the DAP module delegates to it.
---@return LazySpec
function M.spec()
  if not accepted or not accepted.enabled then
    return {}
  end
  local c = vim.deepcopy(accepted)
  return {
    {
      "Orbit-Lua/dotnet-cli.nvim",
      dependencies = { "Orbit-Lua/comet.nvim" },
      cmd = {
        "DotnetManager",
        "DotnetBuild",
        "DotnetPublish",
        "DotnetGlobalJson",
        "DotnetDebug",
        "DotnetAttach",
      },
      keys = {
        { c.manager_key, "<cmd>DotnetManager<CR>", desc = "open dotnet manager" },
      },
      ft = "cs",
      opts = {},
    },
  }
end

return M
