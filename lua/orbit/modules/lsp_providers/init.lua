local M = {}
local accepted

---@class Orbit.LspProvidersOptions # Specialist Roslyn and TypeScript LSP providers.
---@field enabled boolean @default(true) @restart(true) # Contribute specialist LSP providers.
---@field roslyn boolean @default(true) @restart(true) # Enable the .NET Roslyn provider.
---@field typescript_tools boolean @default(true) @restart(true) # Enable TypeScript tools provider.
---@field roslyn_filewatching string @default("roslyn") @minLength(1) @restart(true) # Roslyn file-watching policy.
---@field tsserver_path string @default("") @restart(true) # Optional explicit tsserver.js path.
---@field ts_inlay_hints boolean @default(true) @restart(true) # Enable safe TypeScript inlay hints.

function M.capture()
  return accepted and vim.deepcopy(accepted) or nil
end

function M.restore(snapshot)
  accepted = snapshot and vim.deepcopy(snapshot) or nil
end

---@param opts? Orbit.LspProvidersOptions
function M.setup(opts)
  accepted = require("orbit.config").resolve_module("lsp_providers", opts)
end

---@return table[]
function M.spec()
  if not accepted or not accepted.enabled then return {} end
  local c = vim.deepcopy(accepted)
  local result = {}
  if c.roslyn then
    result[#result + 1] = {
      "seblyng/roslyn.nvim",
      event = { "BufReadPre *.cs", "BufNewFile *.cs" },
      ft = { "cs" },
      cond = function()
        if not require("orbit.hangar_bridge").is_enabled("lsp", "roslyn") then
          return false
        end
        local exe = vim.fn.has("win32") == 1
          and "roslyn-language-server.cmd" or "roslyn-language-server"
        return vim.fn.executable("dotnet") == 1
          and vim.fn.executable(exe) == 1
      end,
      opts = {
        filewatching = c.roslyn_filewatching,
        silent = true,
        choose_target = require("orbit.modules.lsp_providers.runtime").choose_target,
      },
    }
  end

  if c.typescript_tools then
    result[#result + 1] = {
      "pmizio/typescript-tools.nvim",
      ft = {
        "typescript", "typescriptreact", "javascript", "javascriptreact",
        "jsx",
      },
      dependencies = { "nvim-lua/plenary.nvim", "neovim/nvim-lspconfig" },
      opts = function()
        return require("orbit.modules.lsp_providers.runtime")
          .typescript_options(c)
      end,
    }
  end
  return result
end

return M
