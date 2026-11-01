local M = {}
local accepted

---@class Orbit.SnacksOptions # Snacks UI and picker integration.
---@field enabled? boolean @default(true) @restart(true) # Include Snacks in Lazy specs.
---@field picker? boolean @default(true) @restart(true) # Enable picker.
---@field dashboard? boolean @default(true) @restart(true) # Enable dashboard.
---@field notifier? boolean @default(true) @restart(true) # Enable notifier.
---@field statuscolumn? boolean @default(true) @restart(true) # Enable status column.
---@field quickfile? boolean @default(true) @restart(true) # Enable quickfile.
---@field scope? boolean @default(true) @restart(true) # Enable scope detection.
---@field scroll? boolean @default(true) @restart(true) # Enable smooth scroll.
---@field bigfile? boolean @default(true) @restart(true) # Enable large-file handling.
---@field input? boolean @default(true) @restart(true) # Enable input prompts.
---@field words? boolean @default(true) @restart(true) # Enable word references.
---@field notify_timeout? integer @default(3000) @minimum(0) @restart(true) # Notification timeout in milliseconds.

---@return Orbit.SnacksOptions?
function M.capture()
  return accepted and vim.deepcopy(accepted) or nil
end

---@param snapshot Orbit.SnacksOptions?
function M.restore(snapshot)
  accepted = snapshot and vim.deepcopy(snapshot) or nil
end

---@param opts? Orbit.SnacksOptions
function M.setup(opts)
  accepted = require("orbit.config").resolve_module("snacks", opts)
end

local function options(c)
  return {
    animate = {},
    bigfile = { enabled = c.bigfile },
    explorer = { enabled = false },
    image = { enabled = false },
    indent = { enabled = false },
    input = { enabled = c.input, icon = " " },
    quickfile = { enabled = c.quickfile },
    scope = { enabled = c.scope },
    scroll = { enabled = c.scroll },
    statuscolumn = {
      enabled = c.statuscolumn,
      left = { "mark", "sign" },
      right = { "fold", "git" },
      folds = { open = true, git_hl = false },
      git = { patterns = { "GitSign", "MiniDiffSign" } },
      refresh = 50,
    },
    words = { enabled = c.words },
    dashboard = { enabled = c.dashboard },
    notifier = {
      enabled = c.notifier,
      top_down = false,
      margin = { bottom = 2 },
      timeout = c.notify_timeout,
    },
    picker = {
      enabled = c.picker,
      sources = { files = { hidden = true }, grep = { hidden = true } },
      win = {
        list = { wo = { wrap = false } },
        input = { keys = {
          ["<C-u>"] = { "preview_scroll_up", mode = { "i", "n" } },
          ["<C-d>"] = { "preview_scroll_down", mode = { "i", "n" } },
          ["<C-l>"] = { "focus_preview", mode = { "i", "n" } },
          ["<C-h>"] = { "focus_input", mode = { "i", "n" } },
        } },
        preview = { keys = {
          ["<C-l>"] = { "focus_preview", mode = { "i", "n" } },
          ["<C-h>"] = { "focus_input", mode = { "i", "n" } },
        } },
      },
    },
    styles = {
      notification = { border = "rounded" },
      input = { border = "rounded" },
    },
  }
end

---@return LazySpec
function M.spec()
  if not accepted or not accepted.enabled then
    return {}
  end
  return {
    {
      "folke/snacks.nvim",
      lazy = false,
      priority = 1000,
      opts = options(vim.deepcopy(accepted)),
      keys = require("orbit.modules.snacks.keys"),
      config = function(_, opts)
        require("orbit.modules.snacks.runtime").setup(opts)
      end,
    },
  }
end

return M
