local M = {}
local accepted

---@class Orbit.MarkdownOptions # Markdown preview integration.
---@field enabled boolean @default(true) @restart(true) # Enable Markdown integration.
---@field preview boolean @default(true) @restart(true) # Include Markdown preview plugin.
---@field preview_key string @default("<leader>mp") @minLength(1) @restart(true) # Preview toggle mapping.
---@field build_timeout integer @default(120000) @minimum(1000) @maximum(300000) @restart(true) # Preview installer timeout in milliseconds.

function M.capture()
  return accepted and vim.deepcopy(accepted) or nil
end

function M.restore(snapshot)
  accepted = snapshot and vim.deepcopy(snapshot) or nil
end

---@param opts? Orbit.MarkdownOptions
function M.setup(opts)
  accepted = require("orbit.config").resolve_module("markdown", opts)
end

---@return table[]
function M.spec()
  if not accepted or not accepted.enabled or not accepted.preview then
    return {}
  end
  local c = vim.deepcopy(accepted)
  return {
    {
      "iamcco/markdown-preview.nvim",
      cmd = { "MarkdownPreviewToggle", "MarkdownPreview", "MarkdownPreviewStop" },
      ft = { "markdown" },
      keys = {
        { c.preview_key, "<cmd>MarkdownPreviewToggle<cr>", desc = "markdown preview toggle" },
      },
      build = function(plugin)
        require("orbit.modules.markdown.runtime").build_preview(plugin, c.build_timeout)
      end,
    },
  }
end

return M
