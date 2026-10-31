local M = {}
local accepted

---@class Orbit.LspServerFlags # Standard servers owned by native Neovim LSP.
---@field bashls boolean @default(true) # Enable Bash language server.
---@field clangd boolean @default(true) # Enable C and C++ language server.
---@field cssls boolean @default(true) # Enable CSS language server.
---@field docker_compose_language_service boolean @default(true) # Enable Compose YAML language server.
---@field dockerls boolean @default(true) # Enable Dockerfile language server.
---@field gopls boolean @default(true) # Enable Go language server.
---@field html boolean @default(true) # Enable HTML language server.
---@field jsonls boolean @default(true) # Enable JSON language server.
---@field lemminx boolean @default(true) # Enable XML language server.
---@field lua_ls boolean @default(true) # Enable Lua language server.
---@field marksman boolean @default(true) # Enable Markdown language server.
---@field powershell_es boolean @default(true) # Enable PowerShell language server.
---@field prismals boolean @default(true) # Enable Prisma language server.
---@field pyright boolean @default(true) # Enable Pyright Python language server.
---@field ruff boolean @default(true) # Enable Ruff Python language server.
---@field tombi boolean @default(true) # Enable TOML language server.
---@field yamlls boolean @default(true) # Enable YAML language server.

---@class Orbit.LspDiagnostics # Shared diagnostics presentation.
---@field underline boolean @default(true) # Underline diagnostics.
---@field virtual_text boolean @default(true) # Show severity-filtered inline diagnostics.
---@field severity_sort boolean @default(true) # Sort diagnostics by severity.
---@field update_in_insert boolean @default(false) # Refresh diagnostics while editing.
---@field float_border 'rounded'|'single'|'double'|'solid'|'shadow'|'none' @default("rounded") # Floating diagnostic border.

---@class Orbit.LspOptions # Native LSP server activation and diagnostics.
---@field enabled boolean @default(true) @restart(true) # Enable the LSP owner.
---@field servers Orbit.LspServerFlags @default({}) @restart(true) # Standard server activation flags.
---@field diagnostics Orbit.LspDiagnostics @default({}) @restart(true) # Shared diagnostics presentation.
---@field semantic_tokens boolean @default(false) @restart(true) # Keep server semantic tokens instead of Tree-sitter.

function M.capture()
  return accepted and vim.deepcopy(accepted) or nil
end

function M.restore(snapshot)
  accepted = snapshot and vim.deepcopy(snapshot) or nil
end

---@param opts? Orbit.LspOptions
function M.setup(opts)
  accepted = require("orbit.config").resolve_module("lsp", opts)
end

---@return table[]
function M.spec()
  if not accepted or not accepted.enabled then
    return {}
  end
  return {
    {
      "neovim/nvim-lspconfig",
      event = "VeryLazy",
      opts = vim.deepcopy(accepted),
      config = function(_, opts)
        return require("orbit.modules.lsp.runtime").setup(opts)
      end,
    },
  }
end

return M
