-- Entry point for using this repository as the Neovim configuration directory.
-- Plugins load through Lazy, which is cloned on first use when missing.
require("orbit").setup({
  modules = {
    plugins = {
      enabled = true,
      bootstrap = true,
      path = vim.fn.stdpath("data") .. "/lazy/lazy.nvim",
    },
  },
})
