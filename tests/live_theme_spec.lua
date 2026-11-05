-- Exercise pinned tokyonight through the theme owner's Lazy config.
-- This test intentionally uses network and runs outside hermetic suites.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
local lock = dofile(root .. "/tests/support/live_lock.lua")
local directory = vim.fn.tempname() .. " live theme with spaces"

local function hl(name)
  return vim.api.nvim_get_hl(0, { name = name, link = false })
end

local ok, err = xpcall(function()
  lock.checkout("tokyonight.nvim", "folke/tokyonight.nvim", directory)
  vim.opt.rtp:prepend(directory)
  vim.o.termguicolors = true

  require("orbit").setup()
  assert(package.loaded.tokyonight == nil, "root setup imported tokyonight")
  local spec = require("orbit.modules.theme").spec()[1]
  spec.config(spec, spec.opts)
  assert(vim.g.colors_name == "tokyonight-night", tostring(vim.g.colors_name))
  local palette = require("tokyonight.colors").setup({ style = "night" })
  local function hex(value)
    return tonumber(value:sub(2), 16)
  end
  assert(hl("FloatBorder").fg == hex(palette.blue), "FloatBorder must use tokyonight blue")
  assert(hl("DiagnosticVirtualTextError").fg == hl("DiagnosticError").fg)
  print("PASS real tokyonight starts with Orbit overrides")

  require("orbit").setup({ modules = { theme = { colorscheme = "tokyonight-day" } } })
  assert(vim.g.colors_name == "tokyonight-day" and vim.o.background == "light")
  assert(hl("SnacksPickerMatch").bold and hl("FloatBorder").fg == hl("Function").fg)
  print("PASS real tokyonight variant change keeps overrides")
end, debug.traceback)

vim.fn.delete(directory, "rf")
assert(ok, tostring(err))
print("Pinned upstream theme integration tests passed.")
