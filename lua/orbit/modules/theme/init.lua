---@alias Orbit.ThemeBase16 {base00: integer, base01: integer, base02: integer, base03: integer, base04: integer, base05: integer, base06: integer, base07: integer, base08: integer, base09: integer, base0A: integer, base0B: integer, base0C: integer, base0D: integer, base0E: integer, base0F: integer}

---@alias Orbit.ThemePalette {base16: Orbit.ThemeBase16, baby_pink: integer, black: integer, black2: integer, blue: integer, cyan: integer, dark_purple: integer, darker_black: integer, folder_bg: integer, green: integer, grey: integer, grey_fg: integer, grey_fg2: integer, light_grey: integer, lightbg: integer, line: integer, nord_blue: integer, one_bg: integer, one_bg2: integer, one_bg3: integer, orange: integer, pink: integer, pmenu_bg: integer, purple: integer, red: integer, statusline_bg: integer, sun: integer, teal: integer, vibrant_green: integer, white: integer, yellow: integer}

local M = {}
local accepted

---@class Orbit.ThemeOptions # Colorscheme, highlight overrides and saved theme selection.
---@field enabled? boolean @default(true) @restart(true) # Include the colorscheme plugin and highlight owner.
---@field colorscheme? string @default("tokyonight-night") @minLength(1) # Colorscheme applied at startup and on change.
---@field highlights? boolean @default(true) # Apply Orbit highlight overrides after each colorscheme.

---@alias Orbit.ThemeSnapshot {options?: Orbit.ThemeOptions, runtime: Orbit.ThemeRuntimeState}

---@return Orbit.ThemeSnapshot
function M.capture()
  return {
    options = accepted and vim.deepcopy(accepted) or nil,
    runtime = require("orbit.modules.theme.runtime").capture(),
  }
end

---@param snapshot Orbit.ThemeSnapshot
function M.restore(snapshot)
  accepted = snapshot.options and vim.deepcopy(snapshot.options) or nil
  require("orbit.modules.theme.runtime").restore(snapshot.runtime)
end

---@param opts? Orbit.ThemeOptions
function M.setup(opts)
  accepted = require("orbit.config").resolve_module("theme", opts)
  require("orbit.modules.theme.runtime").update(accepted)
end

---@return Orbit.ThemeOptions?
function M.current_options()
  return accepted and vim.deepcopy(accepted) or nil
end

---Declare the default colorscheme plugin; it starts the theme runtime.
---@return LazySpec
function M.spec()
  if not accepted or not accepted.enabled then
    return {}
  end
  return {
    {
      "folke/tokyonight.nvim",
      lazy = false,
      priority = 1000,
      opts = {},
      config = function(_, opts)
        require("tokyonight").setup(opts)
        require("orbit.modules.theme.runtime").start()
      end,
    },
  }
end

return M
