local M = {}
local accepted

---@class Orbit.EditorPluginsOptions # Optional editor visual integrations.
---@field enabled? boolean @default(true) @restart(true) # Contribute editor plugin specifications.
---@field matchup? boolean @default(true) @restart(true) # Enable vim-matchup.
---@field indent_guides? boolean @default(true) @restart(true) # Enable indent-blankline.
---@field matchup_stopline? integer @default(500) @minimum(0) @restart(true) # Matchup syntax scan limit.
---@field indent_char? string @default("│") @minLength(1) @restart(true) # Indentation marker.
---@field scope_char? string @default("│") @minLength(1) @restart(true) # Scope marker.

---@return Orbit.EditorPluginsOptions?
function M.capture()
  return accepted and vim.deepcopy(accepted) or nil
end

---@param snapshot Orbit.EditorPluginsOptions?
function M.restore(snapshot)
  accepted = snapshot and vim.deepcopy(snapshot) or nil
end

---@param opts? Orbit.EditorPluginsOptions
function M.setup(opts)
  accepted = require("orbit.config").resolve_module("editor_plugins", opts)
end

---Contribute plugin declarations without loading external code.
---@return LazySpec
function M.spec()
  if not accepted or not accepted.enabled then
    return {}
  end

  local config = vim.deepcopy(accepted)
  local result = {}
  if config.matchup then
    result[#result + 1] = {
      "andymass/vim-matchup",
      lazy = false,
      init = function()
        vim.g.matchup_treesitter_stopline = config.matchup_stopline
        vim.g.matchup_matchparen_offscreen = {
          method = "popup", fullwidth = 1, border = 0,
        }
      end,
    }
  end

  if config.indent_guides then
    result[#result + 1] = {
      "lukas-reineke/indent-blankline.nvim",
      main = "ibl",
      event = "User FilePost",
      opts = {
        indent = { char = config.indent_char, highlight = "IblChar" },
        scope = { char = config.scope_char, highlight = "IblScopeChar" },
      },
      config = function(_, opts)
        local hooks = require("ibl.hooks")
        hooks.register(
          hooks.type.WHITESPACE,
          hooks.builtin.hide_first_space_indent_level
        )
        require("ibl").setup(opts)
      end,
    }
  end

  return result
end

return M
