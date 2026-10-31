-- Real, pinned upstream mini.icons runtime check (no plugin mocks).
-- Requires Git and network; run separately from hermetic unit suites.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)

local pinned = "eab3e692d796d78ea6ffc978d8a380ff26fcf4e3"
local source = "https://github.com/nvim-mini/mini.icons.git"
local directory = vim.fn.tempname() .. " live mini icons"

local function run(argv)
  local result = vim.system(argv, {
    text = true,
    timeout = 120000,
  }):wait()
  assert(result.code == 0,
    vim.inspect(argv) .. " failed: " ..
      tostring(result.stderr or result.stdout or result.code))
  return result.stdout or ""
end

local ok, err = xpcall(function()
  assert(vim.fn.executable("git") == 1, "Git is required for live plugin tests")
  assert(vim.fn.mkdir(directory, "p") == 1)
  run({ "git", "init", directory })
  run({ "git", "-C", directory, "fetch", "--depth", "1", source, pinned })
  run({ "git", "-C", directory, "checkout", "--detach", "FETCH_HEAD" })
  local sha = run({ "git", "-C", directory, "rev-parse", "HEAD" })
    :gsub("%s+$", "")
  assert(sha == pinned, "upstream mini.icons checkout is not pinned")

  vim.opt.rtp:prepend(directory)
  local orbit = require("orbit")
  local icons = require("orbit.modules.icons")
  orbit.setup({ modules = {
    icons = { enabled = true, mock_devicons = true },
  } })
  assert(package.loaded["mini.icons"] == nil,
    "setup unexpectedly imported the upstream icon plugin")
  local spec = icons.spec()[1]
  assert(spec[1] == "nvim-mini/mini.icons")
  assert(type(spec.config) == "function")
  spec.config()

  local mini = require("mini.icons")
  local glyph, group = mini.get("file", "init.lua")
  assert(type(glyph) == "string" and glyph ~= "", "missing real Lua icon")
  assert(type(group) == "string" and group ~= "", "missing icon highlight")

  local devicons = require("nvim-web-devicons")
  assert(type(devicons.get_icon) == "function",
    "upstream devicons compatibility adapter missing")
  local compatible, compatible_hl = devicons.get_icon("init.lua", "lua",
    { default = true })
  assert(type(compatible) == "string" and compatible ~= "")
  assert(type(compatible_hl) == "string" and compatible_hl ~= "")

  print("PASS real upstream mini.icons setup")
  print("PASS real mini.icons.get(file, init.lua)")
  print("PASS real nvim-web-devicons compatibility API")
  print("Pinned upstream revision: " .. pinned)
end, debug.traceback)

vim.fn.delete(directory, "rf")
assert(ok, tostring(err))
print("Live mini.icons integration tests passed.")
