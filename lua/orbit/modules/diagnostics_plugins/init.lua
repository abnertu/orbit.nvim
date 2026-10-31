local M = {}
local accepted

---@class Orbit.DiagnosticsPluginsOptions # Trouble and todo-comments integrations.
---@field enabled boolean @default(true) @restart(true) # Contribute diagnostic plugin specifications.
---@field trouble boolean @default(true) @restart(true) # Enable Trouble diagnostics views.
---@field todo boolean @default(true) @restart(true) # Enable todo-comments integration.
---@field preview_border 'rounded'|'single'|'double'|'solid'|'shadow'|'none' @default("rounded") @restart(true) # Diagnostic preview border.
---@field preview_width number @default(0.3) @restart(true) # Diagnostic preview width fraction.
---@field preview_height number @default(0.3) @restart(true) # Diagnostic preview height fraction.
---@field todo_icon string @default(" ") @minLength(1) @restart(true) # WORKAROUND marker icon.

function M.capture()
  return accepted and vim.deepcopy(accepted) or nil
end

function M.restore(snapshot)
  accepted = snapshot and vim.deepcopy(snapshot) or nil
end

---@param opts? Orbit.DiagnosticsPluginsOptions
function M.setup(opts)
  opts = require("orbit.config").resolve_module("diagnostics_plugins", opts)
  for _, name in ipairs({ "preview_width", "preview_height" }) do
    assert(opts[name] > 0 and opts[name] <= 1,
      "orbit.modules.diagnostics_plugins." .. name .. ": expected a fraction in (0, 1]")
  end
  accepted = vim.deepcopy(opts)
end

---Reopen the LSP view to avoid stale syntax highlighting.
function M.open_lsp_references()
  local trouble = require("trouble")
  trouble.close({ mode = "lsp" })
  trouble.open({
    mode = "lsp", auto_refresh = false,
    win = { position = "right" }, focus = false,
  })
end

local function todo_picker(keywords)
  -- Snacks owns this picker and is migrated as a separate feature.
  local picker = require("snacks").picker
  if keywords then
    picker.todo_comments({ keywords = keywords })
  else
    picker.todo_comments()
  end
end

---@return table[]
function M.spec()
  if not accepted or not accepted.enabled then
    return {}
  end
  local c = vim.deepcopy(accepted)
  local specs = {}
  if c.trouble then
    specs[#specs + 1] = {
      "folke/trouble.nvim",
      cmd = "Trouble",
      opts = {
        modes = {
          diagnostic_preview_float = {
            mode = "diagnostics",
            preview = {
              type = "float", relative = "editor",
              border = c.preview_border, title = " Preview ",
              title_pos = "center", position = { 0, -2 },
              size = { width = c.preview_width, height = c.preview_height },
              zindex = 200,
            },
          },
        },
      },
      keys = {
        { "<leader>td", "<cmd>Trouble diagnostic_preview_float toggle win.position=bottom<cr>", desc = "diagnostics (trouble)" },
        { "<leader>tD", "<cmd>Trouble diagnostic_preview_float toggle filter.buf=0 win.position=bottom<cr>", desc = "buffer diagnostics (trouble)" },
        { "<leader>cs", "<cmd>Trouble symbols toggle focus=false win.position=right<cr>", desc = "symbols (trouble)" },
        { "<leader>cL", M.open_lsp_references, desc = "lsp references (trouble)" },
        { "<leader>tL", "<cmd>Trouble loclist toggle win.position=bottom<cr>", desc = "location list (trouble)" },
        { "<leader>tQ", "<cmd>Trouble qflist toggle win.position=bottom<cr>", desc = "quickfix list (trouble)" },
      },
    }
  end
  if c.todo then
    specs[#specs + 1] = {
      "folke/todo-comments.nvim",
      event = "User FilePost",
      dependencies = { "nvim-lua/plenary.nvim" },
      keys = {
        { "<leader>st", function() todo_picker() end, desc = "Todo" },
        { "<leader>sT", function()
          todo_picker({ "TODO", "FIX", "FIXME", "WORKAROUND" })
        end, desc = "Todo/Fix/Fixme/Workaround" },
      },
      opts = {
        keywords = {
          WORKAROUND = { icon = c.todo_icon, color = "warning" },
        },
      },
      config = function(_, opts)
        require("todo-comments").setup(opts)
      end,
    }
  end
  return specs
end

return M
