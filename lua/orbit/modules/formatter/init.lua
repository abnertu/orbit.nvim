local M = {}
local accepted

---@class Orbit.FormatterOptions # Conform formatting integration.
---@field enabled boolean @default(true) @restart(true) # Enable Conform formatting.
---@field key string @default("<leader>fm") @minLength(1) @restart(true) # Manual format mapping.
---@field format_on_save boolean @default(false) @restart(true) # Format automatically when writing.
---@field timeout_ms integer @default(5000) @minimum(100) @maximum(60000) @restart(true) # Formatter timeout in milliseconds.
---@field lsp_format 'fallback'|'never'|'first'|'last' @default("fallback") @restart(true) # LSP formatting fallback strategy.

function M.capture()
  return accepted and vim.deepcopy(accepted) or nil
end

function M.restore(snapshot)
  accepted = snapshot and vim.deepcopy(snapshot) or nil
end

---@param opts? Orbit.FormatterOptions
function M.setup(opts)
  accepted = require("orbit.config").resolve_module("formatter", opts)
end

local function default_filetypes()
  return {
    lua = { "stylua" },
    python = { "ruff_fix", "ruff_organize_imports", "ruff_format" },
    sh = { "shfmt" },
    css = { "deno_fmt" },
    html = { "deno_fmt" },
    typescript = { "deno_fmt", "eslint_d" },
    javascript = { "deno_fmt", "eslint_d" },
    typescriptreact = { "deno_fmt", "eslint_d" },
    javascriptreact = { "deno_fmt", "eslint_d" },
    jsx = { "deno_fmt", "eslint_d" },
    json = { "deno_fmt" },
    jsonc = { "deno_fmt" },
    toml = { "tombi" },
    prisma = { "prisma_fmt" },
    cs = { "csharpier" },
    markdown = { "markdownlint-cli2", "markdown-toc" },
    ["markdown.mdx"] = { "markdownlint-cli2", "markdown-toc" },
    yaml = { "yamlfmt" },
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
  return {
    {
      "stevearc/conform.nvim",
      event = { "BufWritePost", "BufReadPost", "InsertLeave" },
      keys = {
        { c.key, function()
          require("orbit.modules.formatter.runtime").format()
        end, desc = "format file", mode = { "n", "x" } },
      },
      opts = {
        default_format_opts = {
          timeout_ms = c.timeout_ms, quiet = false,
          lsp_format = c.lsp_format,
        },
        formatters_by_ft = default_filetypes(),
        format_on_save = c.format_on_save and {
          timeout_ms = c.timeout_ms, lsp_format = c.lsp_format,
        } or false,
      },
    },
  }
end

return M
