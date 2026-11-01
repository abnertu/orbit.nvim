local M = {}
local accepted

---@class Orbit.CompletionOptions # Blink, LuaSnip, autopairs and Lua developer completion.
---@field enabled? boolean @default(true) @restart(true) # Enable completion plugins.
---@field preset? 'enter'|'default'|'super-tab' @default("enter") @restart(true) # Blink keymap preset.
---@field documentation_auto_show? boolean @default(true) @restart(true) # Automatically display completion documentation.
---@field documentation_delay? integer @default(200) @minimum(0) @maximum(5000) @restart(true) # Documentation delay in milliseconds.
---@field ghost_text? boolean @default(false) @restart(true) # Display in-buffer completion ghost text.
---@field cmdline? boolean @default(true) @restart(true) # Complete command line input.
---@field snippet_history? boolean @default(true) @restart(true) # Keep LuaSnip jump history.

---@return Orbit.CompletionOptions?
function M.capture()
  return accepted and vim.deepcopy(accepted) or nil
end

---@param snapshot Orbit.CompletionOptions?
function M.restore(snapshot)
  accepted = snapshot and vim.deepcopy(snapshot) or nil
end

---@param opts? Orbit.CompletionOptions
function M.setup(opts)
  accepted = require("orbit.config").resolve_module("completion", opts)
end

---@return LazySpec
function M.spec()
  if not accepted or not accepted.enabled then return {} end
  local c = vim.deepcopy(accepted)
  return {
    {
      "saghen/blink.cmp",
      event = { "InsertEnter", "CmdlineEnter", "LspAttach" },
      version = "1.*",
      dependencies = {
        {
          "L3MON4D3/LuaSnip",
          dependencies = "rafamadriz/friendly-snippets",
          build = function(plugin)
            require("orbit.modules.completion.runtime").build_luasnip(plugin)
          end,
          opts = {
            history = c.snippet_history,
            updateevents = "TextChanged,TextChangedI",
          },
          config = function(_, opts)
            require("orbit.modules.completion.runtime").setup_luasnip(opts)
          end,
        },
        {
          "windwp/nvim-autopairs",
          opts = {
            fast_wrap = {},
            disable_filetype = { "TelescopePrompt", "vim" },
          },
          config = function(_, opts)
            require("nvim-autopairs").setup(opts)
          end,
        },
        {
          "folke/lazydev.nvim",
          ft = "lua",
          dependencies = { { "justinsgithub/wezterm-types", lazy = true } },
          opts = {
            library = {
              { path = "snacks.nvim", words = { "snacks", "snacks.nvim" } },
              { path = "noice.nvim", words = { "noice", "noice.nvim" } },
              { path = "blink.cmp/lua/blink/cmp", words = { "blink%.cmp" } },
              { path = "wezterm-types", mods = { "wezterm", "module.wezterm" } },
            },
          },
        },
      },
      opts = require("orbit.modules.completion.blink").build(c),
      config = function(_, opts)
        require("orbit.modules.completion.runtime").setup_blink(opts)
      end,
    },
  }
end

return M
