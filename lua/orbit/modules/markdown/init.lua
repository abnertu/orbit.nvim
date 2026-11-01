local M = {}
local accepted

---@class Orbit.MarkdownOptions # Markdown preview integration.
---@field enabled? boolean @default(true) @restart(true) # Enable Markdown integration.
---@field preview? boolean @default(true) @restart(true) # Include Markdown preview plugin.
---@field preview_key? string @default("<leader>mp") @minLength(1) @restart(true) # Preview toggle mapping.
---@field build_timeout? integer @default(120000) @minimum(1000) @maximum(300000) @restart(true) # Preview installer timeout in milliseconds.
---@field notes? boolean @default(true) @restart(true) # Enable Obsidian vault integration.
---@field vault? string @default("") @restart(true) # Optional Obsidian vault directory.

---@return Orbit.MarkdownOptions?
function M.capture()
  return accepted and vim.deepcopy(accepted) or nil
end

---@param snapshot Orbit.MarkdownOptions?
function M.restore(snapshot)
  accepted = snapshot and vim.deepcopy(snapshot) or nil
end

---@param opts? Orbit.MarkdownOptions
function M.setup(opts)
  accepted = require("orbit.config").resolve_module("markdown", opts)
end

---@return LazySpec
function M.spec()
  if not accepted or not accepted.enabled then return {} end
  local c = vim.deepcopy(accepted)
  local specs = {}
  if c.preview then
    specs[#specs + 1] = {
      "iamcco/markdown-preview.nvim",
      cmd = { "MarkdownPreviewToggle", "MarkdownPreview", "MarkdownPreviewStop" },
      ft = { "markdown" },
      keys = {
        { c.preview_key, "<cmd>MarkdownPreviewToggle<cr>", desc = "markdown preview toggle" },
      },
      build = function(plugin)
        require("orbit.modules.markdown.runtime").build_preview(plugin, c.build_timeout)
      end,
    }
  end
  if c.notes and c.vault ~= "" then
    specs[#specs + 1] = {
      "obsidian-nvim/obsidian.nvim",
      version = "*",
      ft = "markdown",
      cond = function()
        return vim.fn.isdirectory(vim.fn.expand(c.vault)) == 1
      end,
      opts = function()
        return require("orbit.modules.markdown.notes").options(c.vault)
      end,
      config = function(_, opts)
        require("orbit.modules.markdown.notes").setup(opts)
      end,
    }
  end
  return specs
end

return M
