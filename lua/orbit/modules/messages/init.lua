local M = {}
local accepted

---@class Orbit.MessagesOptions # Optional Noice commandline and LSP message integration.
---@field enabled? boolean @default(true) @restart(true) # Include Noice and its message routes.
---@field cmdline? boolean @default(true) @restart(true) # Show the commandline popup.
---@field messages? boolean @default(true) @restart(true) # Display Neovim messages through Noice.
---@field popupmenu? boolean @default(true) @restart(true) # Use the NUI commandline completion popup.
---@field hover? boolean @default(true) @restart(true) # Present LSP hover documentation.
---@field signature? boolean @default(true) @restart(true) # Present LSP signature help.
---@field progress? boolean @default(true) @restart(true) # Display LSP progress updates.
---@field lsp_message? boolean @default(false) @restart(true) # Let Noice display LSP showMessage notifications.
---@field doc_max_width? integer @default(80) @minimum(10) @maximum(200) @restart(true) # Maximum documentation popup columns.
---@field doc_max_height? integer @default(20) @minimum(3) @maximum(100) @restart(true) # Maximum documentation popup rows.

---@return Orbit.MessagesOptions?
function M.capture()
  return accepted and vim.deepcopy(accepted) or nil
end

---@param snapshot Orbit.MessagesOptions?
function M.restore(snapshot)
  accepted = snapshot and vim.deepcopy(snapshot) or nil
end

---@param opts? Orbit.MessagesOptions
function M.setup(opts)
  accepted = require("orbit.config").resolve_module("messages", opts)
end

---@return LazySpec
function M.spec()
  if not accepted or not accepted.enabled then return {} end
  local options = vim.deepcopy(accepted)
  return {
    {
      "folke/noice.nvim",
      event = "VeryLazy",
      dependencies = { "MunifTanjim/nui.nvim" },
      opts = function()
        return require("orbit.modules.messages.runtime").options(options)
      end,
      config = function(_, opts)
        require("noice").setup(opts)
      end,
    },
  }
end

return M
