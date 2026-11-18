-- Count real nvim-tree reloads for the events that run without filesystem watchers.
-- This test intentionally uses network and runs outside hermetic suites.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
local lock = dofile(root .. "/tests/support/live_lock.lua")
local base = vim.fn.tempname() .. " live navigation refresh with spaces"
local cwd = vim.fn.getcwd()

---@param path string
---@param text string
local function write_file(path, text)
  local file = assert(io.open(path, "wb"))
  file:write(text)
  file:close()
end

---@return integer
local function tree_window()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.bo[vim.api.nvim_win_get_buf(win)].filetype == "NvimTree" then
      return win
    end
  end
  error("nvim-tree did not open a window")
end

local ok, err = xpcall(function()
  local plugin = vim.fs.joinpath(base, "nvim-tree.lua")
  local workspace = vim.fs.joinpath(base, "workspace")
  vim.fn.mkdir(workspace, "p")
  lock.checkout("nvim-tree.lua", "nvim-tree/nvim-tree.lua", plugin)
  vim.opt.rtp:prepend(plugin)
  write_file(vim.fs.joinpath(workspace, "existing.txt"), "before\n")
  vim.api.nvim_set_current_dir(workspace)

  require("orbit").setup()
  local tree
  for _, spec in ipairs(require("orbit.modules.navigation").spec()) do
    if spec[1] == "nvim-tree/nvim-tree.lua" then
      tree = spec
    end
  end
  assert(tree, "navigation did not declare nvim-tree")
  tree.opts.filesystem_watchers.enable = false
  tree.config(tree, tree.opts)
  tree.config(tree, tree.opts)

  local api = require("nvim-tree.api")
  vim.cmd.edit(vim.fn.fnameescape(vim.fs.joinpath(workspace, "existing.txt")))
  local editor = vim.api.nvim_get_current_win()
  api.tree.open()
  vim.wait(100)
  vim.api.nvim_set_current_win(editor)

  local explorer = assert(require("nvim-tree.core").get_explorer())
  local reload_explorer = explorer.reload_explorer
  local reloads = 0
  explorer.reload_explorer = function(self)
    reloads = reloads + 1
    return reload_explorer(self)
  end

  ---@param expected integer
  ---@param label string
  ---@param action fun()
  local function expect(expected, label, action)
    reloads = 0
    action()
    vim.wait(100)
    assert(
      reloads == expected,
      string.format("%s: expected %d reloads, got %d", label, expected, reloads)
    )
    print("PASS " .. label)
  end

  ---@param event string
  ---@param pattern? string
  local function fire(event, pattern)
    vim.api.nvim_exec_autocmds(event, { pattern = pattern, modeline = false })
  end

  expect(0, "writing an existing file does not reload", function()
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "after" })
    vim.cmd("silent write")
  end)
  expect(0, "focusing the tree does not reload", function()
    vim.api.nvim_set_current_win(tree_window())
  end)
  expect(0, "leaving the tree does not reload", function()
    vim.api.nvim_set_current_win(editor)
  end)
  expect(1, "writing a new file reloads", function()
    vim.cmd.edit(vim.fn.fnameescape(vim.fs.joinpath(workspace, "created.txt")))
    vim.cmd("silent write")
  end)
  expect(1, "regaining focus reloads", function()
    fire("FocusGained")
  end)
  expect(1, "leaving a terminal reloads", function()
    fire("TermLeave")
  end)
  expect(1, "a shell command reloads", function()
    fire("ShellCmdPost")
  end)
  expect(1, "an Oil mutation reloads", function()
    fire("User", "OilActionsPost")
  end)
  expect(1, "events of one turn share a reload", function()
    fire("FocusGained")
    fire("TermLeave")
    fire("ShellCmdPost")
  end)

  write_file(vim.fs.joinpath(workspace, "external.txt"), "outside\n")
  fire("FocusGained")
  assert(
    vim.wait(2000, function()
      local buffer = vim.api.nvim_win_get_buf(tree_window())
      return table
        .concat(vim.api.nvim_buf_get_lines(buffer, 0, -1, false), "\n")
        :find("external.txt", 1, true) ~= nil
    end, 20),
    "a reload did not show the external file"
  )
  print("PASS a reload shows external changes")

  api.tree.close()
  expect(0, "a hidden tree does not reload", function()
    fire("FocusGained")
  end)
  expect(1, "opening the tree reloads once", function()
    api.tree.open()
  end)
end, debug.traceback)

vim.api.nvim_set_current_dir(cwd)
vim.fn.delete(base, "rf")
assert(ok, tostring(err))
print("Pinned nvim-tree refresh integration tests passed.")
