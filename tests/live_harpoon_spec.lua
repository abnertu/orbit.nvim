-- Exercise the actual pinned Harpoon fork and Plenary without plugin mocks.
-- This suite requires Git and network; keep it outside hermetic validation.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)

local dependencies = {
  {
    name = "plenary",
    source = "https://github.com/nvim-lua/plenary.nvim.git",
    revision = "74b06c6c75e4eeb3108ec01852001636d85a932b",
  },
  {
    name = "harpoon",
    source = "https://github.com/Orbit-Lua/harpoon.git",
    revision = "d0bd47625cb7b3e7d73a6ae3dc4f4921554f5279",
  },
}
local workspace = vim.fn.tempname() .. " live harpoon with spaces"
local project = vim.fs.joinpath(workspace, "project with spaces")
local cwd = vim.fn.getcwd()

local function run(argv)
  local result = vim.system(argv, { text = true, timeout = 120000 }):wait()
  assert(result.code == 0, vim.inspect(argv) ..
    " failed: " .. tostring(result.stderr or result.stdout))
  return result.stdout or ""
end

local ok, err = xpcall(function()
  assert(vim.fn.executable("git") == 1, "Git is required")
  assert(vim.fn.mkdir(workspace, "p") == 1)
  for _, dependency in ipairs(dependencies) do
    local directory = vim.fs.joinpath(workspace, dependency.name)
    assert(vim.fn.mkdir(directory, "p") == 1)
    run({ "git", "init", directory })
    run({ "git", "-C", directory, "fetch", "--depth", "1",
      dependency.source, dependency.revision })
    run({ "git", "-C", directory, "checkout", "--detach", "FETCH_HEAD" })
    local actual = run({ "git", "-C", directory, "rev-parse", "HEAD" })
      :gsub("%s+$", "")
    assert(actual == dependency.revision,
      "upstream " .. dependency.name .. " revision mismatch")
    vim.opt.rtp:prepend(directory)
  end

  local orbit = require("orbit")
  local navigation = require("orbit.modules.navigation")
  orbit.setup()
  assert(package.loaded.harpoon == nil,
    "configuration setup must not import Harpoon")

  local spec
  for _, candidate in ipairs(navigation.spec()) do
    if candidate[1] == "Orbit-Lua/harpoon" then
      spec = candidate
      break
    end
  end
  assert(spec and type(spec.config) == "function",
    "Harpoon Lazy spec missing")

  assert(vim.fn.mkdir(vim.fs.joinpath(project, "nested"), "p") == 1)
  local filename = vim.fs.joinpath(project, "nested", "sample.lua")
  assert(vim.fn.writefile({ "local x = 1", "local y = 2" }, filename) == 0)
  vim.api.nvim_set_current_dir(project)
  vim.cmd.edit({ args = { filename } })
  vim.api.nvim_win_set_cursor(0, { 2, 3 })

  spec.config()
  local harpoon = require("harpoon")
  local list = harpoon:list()
  list:clear()
  list:add()
  assert(list:length() == 1, "real Harpoon list did not add the buffer")
  local item = list:get(1)
  assert(item.value == "nested/sample.lua",
    "Harpoon item path did not use the project root")
  assert(item.context.row == 2 and item.context.col == 3,
    "Harpoon item lost the cursor position")
  assert(list:display()[1]:find("sample.lua", 1, true),
    "Harpoon list display lost the filename")
  print("PASS real Harpoon list and orbit navigation callback")

  harpoon.ui:toggle_quick_menu(list)
  assert(vim.api.nvim_win_is_valid(harpoon.ui.win_id),
    "real Harpoon popup did not open")
  local marks = vim.api.nvim_buf_get_extmarks(
    harpoon.ui.bufnr, vim.api.nvim_get_namespaces()["orbit.harpoon"],
    0, -1, { details = true })
  assert(#marks > 0, "current file highlight missing from real popup")
  harpoon.ui:toggle_quick_menu(list)
  assert(harpoon.ui.win_id == nil, "real Harpoon popup did not close")
  print("PASS real Harpoon popup and current-file highlight")

  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  list:select(1)
  assert(vim.api.nvim_win_get_cursor(0)[1] == 2,
    "real Harpoon navigation did not restore the saved cursor")
  print("PASS real Harpoon navigation to saved position")
end, debug.traceback)

vim.api.nvim_set_current_dir(cwd)
vim.fn.delete(workspace, "rf")
assert(ok, tostring(err))
print("Pinned upstream Harpoon integration tests passed.")
