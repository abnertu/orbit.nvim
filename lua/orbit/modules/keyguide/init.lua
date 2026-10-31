-- Which-key owns discoverability, without importing the plugin at root setup.
local M = {}
local accepted

---@class Orbit.KeyguideOptions # Discoverable leader-key groups through which-key.
---@field enabled boolean @default(true) @restart(true) # Contribute the which-key Lazy specification.
---@field preset 'classic'|'modern'|'helix' @default("helix") @restart(true) # Which-key popup layout.
---@field border 'none'|'single'|'double'|'rounded'|'solid'|'shadow' @default("rounded") @restart(true) # Popup window border.

local groups = {
  { "<leader>b", group = "buffer" },
  { "<leader>c", group = "code" },
  { "<leader>d", group = "debug" },
  { "<leader>f", group = "file/find" },
  { "<leader>g", group = "git" },
  { "<leader>m", group = "markdown" },
  { "<leader>s", group = "search" },
  { "<leader>t", group = "trouble/diagnostic" },
  { "<leader>u", group = "ui" },
  { "<leader>w", group = "whichkey" },
}

function M.capture()
  return accepted and vim.deepcopy(accepted) or nil
end

function M.restore(snapshot)
  accepted = snapshot and vim.deepcopy(snapshot) or nil
end

---@param opts? Orbit.KeyguideOptions
function M.setup(opts)
  accepted = require("orbit.config").resolve_module("keyguide", opts)
end

-- Use an argv-safe Ex call. User input must not be parsed as another command.
function M.query()
  local query = vim.fn.input("WhichKey: ")
  if type(query) ~= "string" or query == "" then return end
  vim.api.nvim_cmd({ cmd = "WhichKey", args = { query } }, {})
end

---@return table[]
function M.spec()
  if not accepted or not accepted.enabled then return {} end
  local opts = vim.deepcopy(accepted)
  return {
    {
      "folke/which-key.nvim",
      event = "VeryLazy",
      cmd = "WhichKey",
      keys = {
        { "<leader>wK", "<cmd>WhichKey<cr>", desc = "Show all keymaps" },
        { "<leader>wk", M.query, desc = "Query keymaps" },
      },
      opts = {
        preset = opts.preset,
        win = { border = opts.border },
        spec = vim.deepcopy(groups),
      },
      config = function(_, options)
        require("which-key").setup(options)
      end,
    },
  }
end

return M
