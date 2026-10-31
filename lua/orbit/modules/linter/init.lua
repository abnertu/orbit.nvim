local M = {}
local accepted

---@class Orbit.LinterOptions # nvim-lint configuration and event scheduling.
---@field enabled boolean @default(true) @restart(true) # Enable lint integration.
---@field debounce_ms integer @default(200) @minimum(0) @maximum(5000) @restart(true) # Delay before lint execution.
---@field lint_on_change boolean @default(true) @restart(true) # Trigger lint on TextChanged.
---@field skip_sql_on_change boolean @default(true) @restart(true) # Avoid SQLFluff while typing.

function M.capture()
  return accepted and vim.deepcopy(accepted) or nil
end

function M.restore(snapshot)
  accepted = snapshot and vim.deepcopy(snapshot) or nil
end

---@param opts? Orbit.LinterOptions
function M.setup(opts)
  accepted = require("orbit.config").resolve_module("linter", opts)
end

local function language_defaults()
  return {
    dockerfile = { "hadolint" },
    markdown = { "markdownlint-cli2" },
    lua = { "luacheck" },
    typescript = { "eslint_d" },
    javascript = { "eslint_d" },
    typescriptreact = { "eslint_d" },
    javascriptreact = { "eslint_d" },
    jsx = { "eslint_d" },
    sql = { "sqlfluff" },
    mysql = { "sqlfluff" },
    plsql = { "sqlfluff" },
  }
end

---@return table[]
function M.spec()
  if not accepted or not accepted.enabled then
    return {}
  end
  local c = vim.deepcopy(accepted)
  local events = { "BufWritePost", "BufReadPost", "InsertLeave" }
  if c.lint_on_change then
    events[#events + 1] = "TextChanged"
  end
  return {
    {
      "mfussenegger/nvim-lint",
      event = { "BufReadPost", "BufWritePost", "BufNewFile" },
      opts = {
        events = events,
        debounce_ms = c.debounce_ms,
        skip_while_editing = c.skip_sql_on_change and { "sqlfluff" } or {},
        linters_by_ft = language_defaults(),
        linters = {
          sqlfluff = function()
            local filename = vim.api.nvim_buf_get_name(0)
            local adapter = require("orbit.sqlfluff")
            local definition = vim.deepcopy(require("lint.linters.sqlfluff"))
            definition.args = adapter.lint_args(filename)
            definition.cwd = adapter.cwd(filename)
            definition.env = { PYTHONUTF8 = "1" }
            return definition
          end,
        },
      },
      config = function(_, opts)
        require("orbit.modules.linter.runtime").setup(opts)
      end,
    },
  }
end

return M
