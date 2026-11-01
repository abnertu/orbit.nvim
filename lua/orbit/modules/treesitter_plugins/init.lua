local M = {}
local accepted

---@class Orbit.TreesitterPluginsOptions # Tree-sitter parser and companion plugins.
---@field enabled boolean @default(true) @restart(true) # Include Tree-sitter plugin specs.
---@field core boolean @default(true) @restart(true) # Install the main parser manager.
---@field context boolean @default(true) @restart(true) # Enable Tree-sitter context view.
---@field autotag boolean @default(true) @restart(true) # Enable HTML/XML auto tags.
---@field context_lines integer @default(3) @minimum(0) @maximum(50) @restart(true) # Context line limit.
---@field autotag_close boolean @default(true) @restart(true) # Insert closing tags.
---@field autotag_rename boolean @default(true) @restart(true) # Rename matching tags.
---@field autotag_close_slash boolean @default(false) @restart(true) # Close tags after slash.
---@field install_dir string @default("") @restart(true) # Optional parser installation directory.
---@field sql_injections Orbit.TreesitterSqlInjections @default({}) @restart(true) # SQL injection controls.
---@field sql_dialect string @default("tsql") @minLength(1) @restart(true) # Default SQL dialect for fallback syntax.
---@field sql_syntax_fallback boolean @default(true) @restart(true) # Apply T-SQL syntax after Tree-sitter starts.
---@field sql_markdown_fenced_fallback boolean @default(true) @restart(true) # Highlight SQL inside Markdown code fences.

---@class Orbit.TreesitterSqlInjections # C# SQL injection selection.
---@field comment boolean @default(true) # Parse SQL after language=sql comments.
---@field auto boolean @default(true) # Parse SQL assigned to sql-prefixed variables.

---@return Orbit.TreesitterPluginsOptions?
function M.capture()
  return accepted and vim.deepcopy(accepted) or nil
end

---@param snapshot Orbit.TreesitterPluginsOptions?
function M.restore(snapshot)
  accepted = snapshot and vim.deepcopy(snapshot) or nil
end

---@param opts? Orbit.TreesitterPluginsOptions
function M.setup(opts)
  accepted = require("orbit.config").resolve_module("treesitter_plugins", opts)
end

---@return Orbit.TreesitterPluginsOptions?
function M.current_options()
  return accepted and vim.deepcopy(accepted) or nil
end

---@return LazySpec
function M.spec()
  if not accepted or not accepted.enabled then
    return {}
  end
  local c = vim.deepcopy(accepted)
  local specs = {}
  if c.core then
    specs[#specs + 1] = {
      "nvim-treesitter/nvim-treesitter",
      lazy = false,
      branch = "main",
      build = { ":TSUpdate" },
      init = function()
        require("orbit.modules.treesitter_plugins.runtime").setup()
      end,
      opts = {
        install_dir = c.install_dir ~= "" and c.install_dir or
          vim.fs.joinpath(vim.fn.stdpath("data"), "site"),
      },
    }
  end
  if c.context then
    specs[#specs + 1] = {
      "nvim-treesitter/nvim-treesitter-context",
      dependencies = { "nvim-treesitter/nvim-treesitter" },
      event = { "BufReadPost", "BufWritePost", "BufNewFile" },
      opts = {
        enable = true, multiwindow = false, max_lines = c.context_lines,
        min_window_height = 0, line_numbers = true,
        multiline_threshold = 20, trim_scope = "outer",
        mode = "cursor", zindex = 20,
      },
    }
  end
  if c.autotag then
    specs[#specs + 1] = {
      "windwp/nvim-ts-autotag",
      dependencies = { "nvim-treesitter/nvim-treesitter" },
      event = { "BufReadPre", "BufNewFile" },
      opts = {
        opts = {
          enable_close = c.autotag_close,
          enable_rename = c.autotag_rename,
          enable_close_on_slash = c.autotag_close_slash,
        },
        aliases = { pubxml = "xml", csproj = "xml", jsx = "typescriptreact" },
      },
      config = function(_, opts)
        require("nvim-ts-autotag").setup(opts)
      end,
    }
  end
  return specs
end

return M
