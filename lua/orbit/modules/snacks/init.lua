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

-- Notifications from known noisy sources stay out of the notifier.
local ignored_notifications = {
  "man.lua",
  "roslyn: %-32000",
  "roslyn: %-30099",
  "lua_ls: %-32603",
}

---@param notif {msg: string}
---@return boolean
local function notification_filter(notif)
  for _, pattern in ipairs(ignored_notifications) do
    if tostring(notif.msg):find(pattern) then return false end
  end
  return true
end

local layouts = {
  default = {
    layout = {
      backdrop = false, box = "horizontal", width = 0.87, height = 0.80, border = "none",
      {
        box = "vertical",
        { win = "list", border = "rounded", flex = 1 },
        { win = "input", height = 1, border = "rounded", title = "Find {title} {live} {flags}" },
      },
      { win = "preview", title = "Preview {preview}", border = "rounded", flex = 1, min_width = 30 },
    },
  },
  select = {
    layout = {
      backdrop = false, box = "vertical", border = "none", width = 0.6, height = 0.4,
      { win = "input", height = 0.1, border = "rounded", title = "{title}" },
      { win = "list", border = "rounded", flex = 1 },
    },
  },
  vscode = {
    hidden = { "preview" },
    layout = {
      backdrop = false, row = 1, width = 0.4, min_width = 80, height = 0.4,
      border = "none", box = "vertical",
      { win = "input", height = 1, border = "rounded", title = "{title} {live} {flags}", title_pos = "center" },
      { win = "list", border = "hpad" },
      { win = "preview", title = "{preview}", border = true },
    },
  },
  vertical = {
    layout = {
      backdrop = false, width = 0.5, min_width = 80, height = 0.8, min_height = 30,
      box = "vertical", border = "rounded", title = "{title} {live} {flags}", title_pos = "center",
      { win = "input", height = 1, border = "bottom" },
      { win = "list", border = "none" },
      { win = "preview", title = "{preview}", height = 0.4, border = "top" },
    },
  },
}

local function options(c)
  return {
    dim = {},
    gh = {},
    gitbrowse = {},
    zen = {},
    lazygit = {
      theme = { activeBorderColor = { fg = "SnacksLazygitActiveBorder", bold = true } },
    },
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
    dashboard = {
      enabled = c.dashboard,
      preset = { header = require("orbit.modules.snacks.header") },
      sections = {
        { section = "header", align = "center" },
        { pane = 2, section = "keys", gap = 1, padding = 1 },
        { pane = 2, title = "Recent Files", section = "recent_files", indent = 2, padding = { 1, 1 } },
        { pane = 2, title = "Projects", section = "projects", indent = 2, padding = 1 },
        { pane = 2, section = "startup" },
      },
    },
    notifier = {
      enabled = c.notifier,
      top_down = false,
      margin = { bottom = 2 },
      timeout = c.notify_timeout,
      filter = notification_filter,
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
      layouts = vim.deepcopy(layouts),
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
