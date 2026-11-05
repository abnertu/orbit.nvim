-- Exercise the actual pinned Harpoon fork and Plenary without plugin mocks.
-- This suite requires Git and network; keep it outside hermetic validation.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)

local lock = dofile(root .. "/tests/support/live_lock.lua")
local dependencies = {
  { name = "plenary.nvim", repository = "nvim-lua/plenary.nvim" },
  { name = "harpoon", repository = "Orbit-Lua/harpoon" },
}
local workspace = vim.fn.tempname() .. " live harpoon with spaces"
local project = vim.fs.joinpath(workspace, "project with spaces")
local cwd = vim.fn.getcwd()

local ok, err = xpcall(function()
  assert(vim.fn.mkdir(workspace, "p") == 1)
  -- Lazy bootstrap normally creates the Neovim data root before plugins run.
  -- The standalone live fixture must establish the same prerequisite.
  local data_root = vim.fn.stdpath("data")
  vim.fn.mkdir(data_root, "p")
  assert(
    vim.fn.isdirectory(data_root) == 1,
    "Neovim data directory is required by upstream Harpoon"
  )
  for _, dependency in ipairs(dependencies) do
    local directory = vim.fs.joinpath(workspace, dependency.name)
    lock.checkout(dependency.name, dependency.repository, directory)
    vim.opt.rtp:prepend(directory)
  end

  local orbit = require("orbit")
  local navigation = require("orbit.modules.navigation")
  orbit.setup()
  assert(package.loaded.harpoon == nil, "configuration setup must not import Harpoon")

  local spec
  for _, candidate in ipairs(navigation.spec()) do
    if candidate[1] == "Orbit-Lua/harpoon" then
      spec = candidate
      break
    end
  end
  assert(spec and type(spec.config) == "function", "Harpoon Lazy spec missing")

  assert(vim.fn.mkdir(vim.fs.joinpath(project, "nested"), "p") == 1)
  local filename = vim.fs.joinpath(project, "nested", "sample.lua")
  assert(vim.fn.writefile({ "local x = 1", "local y = 2" }, filename) == 0)
  vim.api.nvim_set_current_dir(project)
  vim.cmd.edit({ args = { filename } })
  vim.api.nvim_win_set_cursor(0, { 2, 3 })

  -- Redirect upstream Harpoon persistence to the isolated live fixture.
  -- This avoids modifying a developer's real Harpoon data when run locally.
  local persistence_path = vim.fs.joinpath(workspace, "harpoon-state.json")
  require("harpoon.data").test.set_fullpath(function()
    return persistence_path
  end)

  spec.config()
  local harpoon = require("harpoon")
  local list = harpoon:list()
  list:clear()
  list:add()
  assert(list:length() == 1, "real Harpoon list did not add the buffer")
  local item = list:get(1)
  assert(item.value == "nested/sample.lua", "Harpoon item path did not use the project root")
  assert(item.context.row == 2 and item.context.col == 3, "Harpoon item lost the cursor position")
  assert(list:display()[1]:find("sample.lua", 1, true), "Harpoon list display lost the filename")
  print("PASS real Harpoon list and orbit navigation callback")

  harpoon.ui:toggle_quick_menu(list)
  assert(vim.api.nvim_win_is_valid(harpoon.ui.win_id), "real Harpoon popup did not open")
  local marks = vim.api.nvim_buf_get_extmarks(
    harpoon.ui.bufnr,
    vim.api.nvim_get_namespaces()["orbit.harpoon"],
    0,
    -1,
    { details = true }
  )
  assert(#marks > 0, "current file highlight missing from real popup")
  harpoon.ui:toggle_quick_menu(list)
  assert(harpoon.ui.win_id == nil, "real Harpoon popup did not close")
  print("PASS real Harpoon popup and current-file highlight")

  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  list:select(1)
  assert(
    vim.api.nvim_win_get_cursor(0)[1] == 2,
    "real Harpoon navigation did not restore the saved cursor"
  )
  print("PASS real Harpoon navigation to saved position")

  -- Read the on-disk list through a new upstream data instance, rather
  -- than trusting the in-memory list that performed the write.
  harpoon:sync()
  assert(
    vim.fn.filereadable(persistence_path) == 1,
    "real Harpoon did not persist its project list"
  )
  local project_key = harpoon.config.settings.key()
  local persisted = require("harpoon.data").Data:new(harpoon.config)
  assert(not persisted.has_error, "real Harpoon could not reopen saved state")
  local decoded =
    require("harpoon.list").decode(list.config, list.name, persisted:data(project_key, list.name))
  assert(decoded:length() == 1, "reloaded Harpoon list lost the project entry")
  local saved_item = decoded:get(1)
  assert(
    saved_item.value == "nested/sample.lua"
      and saved_item.context.row == 2
      and saved_item.context.col == 3,
    "reloaded Harpoon entry lost its relative path or cursor: " .. vim.inspect(saved_item)
  )
  print("PASS real Harpoon persisted list survives an independent data reload")

  local other_project = vim.fs.joinpath(workspace, "other project with spaces")
  assert(vim.fn.mkdir(other_project, "p") == 1)
  vim.api.nvim_set_current_dir(other_project)
  assert(
    harpoon:list():length() == 0,
    "Harpoon leaked the first project's list into another directory"
  )
  vim.api.nvim_set_current_dir(project)
  assert(harpoon:list():length() == 1, "Harpoon did not recover the original project's list")
  print("PASS real Harpoon project lists remain isolated")

  -- A new Neovim process reads the saved list through Orbit's spec config.
  local child = vim.fs.joinpath(workspace, "restart child.lua")
  local result = vim.fs.joinpath(workspace, "restart result.json")
  assert(vim.fn.writefile({
    "for _, path in ipairs(" .. vim.inspect({
      root,
      vim.fs.joinpath(workspace, "plenary.nvim"),
      vim.fs.joinpath(workspace, "harpoon"),
    }) .. ") do vim.opt.rtp:prepend(path) end",
    "vim.api.nvim_set_current_dir(" .. vim.inspect(project) .. ")",
    "require('harpoon.data').test.set_fullpath(function() return "
      .. vim.inspect(persistence_path)
      .. " end)",
    "require('orbit').setup()",
    "for _, spec in ipairs(require('orbit.modules.navigation').spec()) do",
    "  if spec[1] == 'Orbit-Lua/harpoon' then spec.config() end",
    "end",
    "local list = require('harpoon'):list()",
    "local item = list:get(1) or {}",
    "vim.fn.writefile({ vim.json.encode({ length = list:length(),",
    "  value = item.value, context = item.context }) }, " .. vim.inspect(result) .. ")",
  }, child) == 0)
  local restarted = vim
    .system(
      { vim.v.progpath, "--headless", "-u", "NONE", "-i", "NONE", "-l", child },
      { text = true, timeout = 60000 }
    )
    :wait()
  assert(restarted.code == 0, "restarted Neovim failed: " .. tostring(restarted.stderr))
  local reopened = vim.json.decode(table.concat(vim.fn.readfile(result), "\n"))
  assert(
    reopened.length == 1
      and reopened.value == "nested/sample.lua"
      and reopened.context.row == 2
      and reopened.context.col == 3,
    "restarted Neovim lost the Harpoon list: " .. vim.inspect(reopened)
  )
  print("PASS real Harpoon list survives a Neovim process restart")
end, debug.traceback)

vim.api.nvim_set_current_dir(cwd)
vim.fn.delete(workspace, "rf")
assert(ok, tostring(err))
print("Pinned upstream Harpoon integration tests passed.")
