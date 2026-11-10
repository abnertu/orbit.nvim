-- Exercise the pinned nvim-tree border next to a horizontal split under the Orbit theme.
-- This test intentionally uses network and runs outside hermetic suites.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
local lock = dofile(root .. "/tests/support/live_lock.lua")
local pins = {
  { "tokyonight.nvim", "folke/tokyonight.nvim" },
  { "nvim-tree.lua", "nvim-tree/nvim-tree.lua" },
}
local base = vim.fn.tempname() .. " live navigation layout with spaces"

---@return integer
local function tree_window()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.bo[vim.api.nvim_win_get_buf(win)].filetype == "NvimTree" then
      return win
    end
  end
  error("nvim-tree did not open a window")
end

---@param name string
---@return vim.api.keyset.get_hl_info
local function hl(name)
  return vim.api.nvim_get_hl(0, { name = name, link = false })
end

---@param row integer
---@param col integer
---@return string, integer
local function cell(row, col)
  return vim.fn.screenstring(row, col), vim.fn.screenattr(row, col)
end

-- Check the tree separator column around the junction of a split to its right.
---@param label string
local function assert_junction(label)
  vim.cmd("redraw!")
  local tree = tree_window()
  local position = vim.api.nvim_win_get_position(tree)
  local column = position[2] + vim.api.nvim_win_get_width(tree) + 1
  local main = vim.api.nvim_get_current_win()
  local junction = vim.api.nvim_win_get_position(main)[1] + vim.api.nvim_win_get_height(main) + 1
  local joint, joint_attr = cell(junction, column)
  local _, line_attr = cell(junction, column + 1)
  assert(joint == "├", label .. ": no junction at the tree border, found " .. vim.inspect(joint))
  for _, row in ipairs({ junction - 1, junction + 1 }) do
    local text, attr = cell(row, column)
    assert(text == "│", label .. ": tree border row " .. row .. " shows " .. vim.inspect(text))
    assert(
      attr == joint_attr and attr == line_attr,
      string.format(
        "%s: tree border row %d uses attr %d, junction %d",
        label,
        row,
        attr,
        joint_attr
      )
    )
  end
  -- The tabline row keeps its own background, so compare the separator foreground.
  local offset = cell(1, column)
  assert(offset == "│", label .. ": tabline offset separator shows " .. vim.inspect(offset))
  local border = hl("WinSeparator")
  local sep = hl("OrbitTbOffsetSep")
  assert(sep.fg and sep.fg == border.fg, label .. ": tabline offset separator color differs")
  assert(sep.fg ~= hl("TabLineFill").bg, label .. ": tabline offset separator is invisible")
  print("PASS " .. label)
end

local ok, err = xpcall(function()
  for index, pin in ipairs(pins) do
    local directory = base .. "/" .. index
    lock.checkout(pin[1], pin[2], directory)
    vim.opt.rtp:prepend(directory)
  end
  vim.o.termguicolors = true
  vim.o.laststatus = 3

  require("orbit").setup()
  local theme = require("orbit.modules.theme").spec()[1]
  theme.config(theme, theme.opts)
  local tree
  for _, spec in ipairs(require("orbit.modules.navigation").spec()) do
    if spec[1] == "nvim-tree/nvim-tree.lua" then
      tree = spec
    end
  end
  assert(tree, "navigation did not declare nvim-tree")
  tree.config(tree, tree.opts)

  local api = require("nvim-tree.api")
  api.tree.open()
  vim.cmd("wincmd l")
  vim.cmd("split")
  assert_junction("tree border joins the split junction")

  vim.cmd("colorscheme tokyonight-night")
  assert_junction("tree border survives a theme reload")

  api.tree.close()
  api.tree.open()
  vim.cmd("wincmd l")
  assert_junction("tree border survives a tree reopen")
end, debug.traceback)

vim.fn.delete(base, "rf")
assert(ok, tostring(err))
print("Pinned upstream navigation layout integration tests passed.")
